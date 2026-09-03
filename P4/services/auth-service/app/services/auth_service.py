"""Casos de uso de autenticación y control de acceso.

Depende únicamente de abstracciones (`RepositorioUsuarios`,
`ClienteAutorizacion`, `ServicioToken`), nunca de sus implementaciones
concretas: Dependency Inversion aplicado.
"""

from dataclasses import dataclass
from uuid import uuid4

from app.core.crypto import hashear_password, verificar_password
from app.domain.entities import Rol, Usuario
from app.domain.exceptions import (
    AccesoDenegadoError,
    CorreoYaRegistradoError,
    CredencialesInvalidasError,
    NoAutenticadoError,
)
from app.domain.repositories import ClienteAutorizacion, RepositorioUsuarios
from app.services.token_service import Credencial, ResultadoToken, ServicioToken


@dataclass(frozen=True, slots=True)
class SesionIniciada:
    """Resultado de un login o de una renovación de sesión."""

    usuario: Usuario
    token: str


@dataclass(frozen=True, slots=True)
class SesionVigente:
    """Sesión validada en una petición a una ruta protegida.

    `token_renovado` viene con valor solo cuando el token presentado
    estaba expirado pero dentro de la ventana de gracia. La capa de API
    lo usa para reescribir la cookie de forma transparente.
    """

    usuario: Usuario
    token_renovado: str | None


class ServicioAutenticacion:
    """Orquesta registro, login y validación de sesiones."""

    def __init__(
        self,
        repositorio: RepositorioUsuarios,
        servicio_token: ServicioToken,
        cliente_autorizacion: ClienteAutorizacion,
    ) -> None:
        self._repositorio = repositorio
        self._token = servicio_token
        self._autorizacion = cliente_autorizacion

    def registrar(
        self, nombre: str, correo: str, password: str, rol: Rol
    ) -> SesionIniciada:
        """Da de alta un usuario nuevo y abre su sesión."""
        if self._repositorio.obtener_por_correo(correo) is not None:
            raise CorreoYaRegistradoError

        usuario = Usuario(
            id=uuid4(),
            nombre=nombre,
            correo=correo,
            rol=rol,
            password_hash=hashear_password(password),
        )
        creado = self._repositorio.crear(usuario)
        return SesionIniciada(creado, self._token.emitir(creado.id, creado.rol))

    def iniciar_sesion(self, correo: str, password: str) -> SesionIniciada:
        """Valida las credenciales y emite un token de acceso."""
        usuario = self._repositorio.obtener_por_correo(correo)

        if usuario is None or not verificar_password(password, usuario.password_hash):
            # Un único error para ambos casos: distinguirlos permitiría
            # averiguar qué correos están registrados.
            raise CredencialesInvalidasError

        return SesionIniciada(usuario, self._token.emitir(usuario.id, usuario.rol))

    def validar_sesion(self, token: str | None) -> SesionVigente:
        """Comprueba el token y renueva si corresponde.

        Es el punto donde se materializa el requisito 5: un token
        expirado dentro de la ventana de gracia produce uno nuevo de
        forma automática, sin que el usuario vuelva a autenticarse.
        """
        if not token:
            raise NoAutenticadoError("No se encontró una sesión activa.")

        credencial = self._token.verificar(token)
        if credencial is None or credencial.resultado is ResultadoToken.RECHAZADO:
            raise NoAutenticadoError

        usuario = self._repositorio.obtener_por_id(credencial.usuario_id)
        if usuario is None:
            # El token es válido pero el usuario ya no existe: la sesión
            # no puede sostenerse.
            raise NoAutenticadoError("El usuario de la sesión ya no existe.")

        return SesionVigente(
            usuario=usuario,
            token_renovado=self._renovar_si_corresponde(credencial, usuario),
        )

    def exigir_permiso(self, usuario: Usuario, permiso: str) -> None:
        """Consulta al microservicio de autorización y bloquea si deniega."""
        if not self._autorizacion.tiene_permiso(usuario.rol.value, permiso):
            raise AccesoDenegadoError(permiso)

    def _renovar_si_corresponde(
        self, credencial: Credencial, usuario: Usuario
    ) -> str | None:
        """Emite un token nuevo solo si el anterior era renovable."""
        if credencial.resultado is not ResultadoToken.RENOVABLE:
            return None
        return self._token.emitir(usuario.id, usuario.rol)
