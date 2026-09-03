"""Emisión y validación de JSON Web Tokens.

Aquí vive la lógica del requisito 5 del enunciado: un token expirado
puede renovarse automáticamente si aún está dentro de una ventana de
gracia configurable. Pasada esa ventana, el usuario debe autenticarse
de nuevo.

Línea de tiempo de un token:

    emisión                 exp                  exp + gracia
       |------- válido -------|--- renovable ---|--- rechazado --->
"""

from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from enum import Enum, auto
from uuid import UUID

import jwt

from app.core.config import Settings
from app.domain.entities import Rol


class ResultadoToken(Enum):
    """Estado en que se encuentra un token presentado por el cliente."""

    VALIDO = auto()
    RENOVABLE = auto()  # expirado, pero dentro de la ventana de gracia
    RECHAZADO = auto()  # inválido, manipulado o fuera de la ventana


@dataclass(frozen=True, slots=True)
class Credencial:
    """Identidad extraída de un token, junto con su estado."""

    usuario_id: UUID
    rol: Rol
    resultado: ResultadoToken


class ServicioToken:
    """Genera y verifica los tokens de acceso.

    Recibe la configuración por constructor en lugar de leerla de forma
    global, para que las pruebas puedan inyectar tiempos muy cortos sin
    tocar variables de entorno.
    """

    def __init__(self, settings: Settings) -> None:
        self._settings = settings

    def emitir(self, usuario_id: UUID, rol: Rol) -> str:
        """Crea un token firmado para el usuario indicado."""
        ahora = datetime.now(UTC)
        expiracion = ahora + timedelta(seconds=self._settings.jwt_ttl_segundos)

        cuerpo = {
            "sub": str(usuario_id),
            "rol": rol.value,
            "iat": int(ahora.timestamp()),
            "exp": int(expiracion.timestamp()),
        }
        return jwt.encode(
            cuerpo,
            self._settings.jwt_secreto,
            algorithm=self._settings.jwt_algoritmo,
        )

    def verificar(self, token: str) -> Credencial | None:
        """Determina si un token es válido, renovable o debe rechazarse.

        Devuelve `None` cuando el token no es interpretable en absoluto
        (firma inválida, formato corrupto o campos faltantes). En ese caso
        no hay identidad que reportar.
        """
        try:
            cuerpo = self._decodificar(token, verificar_expiracion=True)
            return self._construir_credencial(cuerpo, ResultadoToken.VALIDO)

        except jwt.ExpiredSignatureError:
            return self._evaluar_ventana_de_gracia(token)

        except jwt.InvalidTokenError:
            # Firma incorrecta, algoritmo distinto o token manipulado.
            return None

    def _evaluar_ventana_de_gracia(self, token: str) -> Credencial | None:
        """Decide si un token expirado todavía puede renovarse.

        Se vuelve a decodificar desactivando **solo** la comprobación de
        expiración. La verificación de firma sigue activa: un token
        expirado y además falsificado se rechaza igual.
        """
        try:
            cuerpo = self._decodificar(token, verificar_expiracion=False)
        except jwt.InvalidTokenError:
            return None

        expiracion = cuerpo.get("exp")
        if not isinstance(expiracion, int):
            return None

        segundos_vencido = datetime.now(UTC).timestamp() - expiracion
        dentro_de_gracia = (
            segundos_vencido <= self._settings.jwt_gracia_renovacion_segundos
        )

        estado = (
            ResultadoToken.RENOVABLE if dentro_de_gracia else ResultadoToken.RECHAZADO
        )
        return self._construir_credencial(cuerpo, estado)

    def _decodificar(self, token: str, *, verificar_expiracion: bool) -> dict:
        """Decodifica el token verificando siempre la firma."""
        return jwt.decode(
            token,
            self._settings.jwt_secreto,
            algorithms=[self._settings.jwt_algoritmo],
            options={"verify_exp": verificar_expiracion, "require": ["sub", "exp"]},
        )

    @staticmethod
    def _construir_credencial(
        cuerpo: dict, resultado: ResultadoToken
    ) -> Credencial | None:
        """Traduce el cuerpo del token a una credencial de dominio."""
        try:
            return Credencial(
                usuario_id=UUID(cuerpo["sub"]),
                rol=Rol(cuerpo["rol"]),
                resultado=resultado,
            )
        except (KeyError, ValueError):
            # Un rol desconocido o un identificador malformado invalidan
            # el token aunque la firma sea correcta.
            return None
