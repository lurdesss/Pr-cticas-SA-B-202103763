"""Composición de dependencias y guardas de acceso.

Este es el único archivo donde las abstracciones se atan a
implementaciones concretas, y donde se maneja la cookie que transporta
el token.
"""

from collections.abc import Callable
from typing import Annotated

from fastapi import Cookie, Depends, Response
from sqlalchemy.orm import Session

from app.core.config import Settings, get_settings
from app.core.database import get_session
from app.domain.entities import Usuario
from app.domain.repositories import ClienteAutorizacion, RepositorioUsuarios
from app.infrastructure.authz_client import ClienteAutorizacionHTTP
from app.infrastructure.postgres_repository import RepositorioUsuariosPostgres
from app.services.auth_service import ServicioAutenticacion
from app.services.token_service import ServicioToken

SettingsDep = Annotated[Settings, Depends(get_settings)]
SesionBD = Annotated[Session, Depends(get_session)]


def obtener_repositorio(session: SesionBD) -> RepositorioUsuarios:
    """Devuelve la implementación de repositorio en uso."""
    return RepositorioUsuariosPostgres(session)


def obtener_servicio_token(settings: SettingsDep) -> ServicioToken:
    """Construye el emisor y verificador de tokens."""
    return ServicioToken(settings)


def obtener_cliente_autorizacion(settings: SettingsDep) -> ClienteAutorizacion:
    """Devuelve el cliente del microservicio de autorización."""
    return ClienteAutorizacionHTTP(settings)


def obtener_servicio_auth(
    repositorio: Annotated[RepositorioUsuarios, Depends(obtener_repositorio)],
    servicio_token: Annotated[ServicioToken, Depends(obtener_servicio_token)],
    autorizacion: Annotated[
        ClienteAutorizacion, Depends(obtener_cliente_autorizacion)
    ],
) -> ServicioAutenticacion:
    """Arma el servicio de autenticación con sus dependencias resueltas."""
    return ServicioAutenticacion(repositorio, servicio_token, autorizacion)


ServicioAuthDep = Annotated[ServicioAutenticacion, Depends(obtener_servicio_auth)]


def escribir_cookie_sesion(
    respuesta: Response, token: str, settings: Settings
) -> None:
    """Coloca el token en una cookie HTTP-only (requisito 3).

    `httponly=True` impide que `document.cookie` lo lea desde JavaScript,
    lo que neutraliza el robo de sesión por XSS. `secure` y `samesite`
    son configurables porque en desarrollo local se trabaja sobre HTTP.

    `max_age` es deliberadamente mayor que la vida del JWT: la cookie
    debe seguir llegando al servidor durante la ventana de gracia, o el
    backend no tendría qué renovar.
    """
    respuesta.set_cookie(
        key=settings.cookie_nombre,
        value=token,
        httponly=True,
        secure=settings.cookie_secure,
        samesite=settings.cookie_samesite,
        max_age=settings.jwt_ttl_segundos + settings.jwt_gracia_renovacion_segundos,
        path="/",
    )


def borrar_cookie_sesion(respuesta: Response, settings: Settings) -> None:
    """Elimina la cookie de sesión al cerrar sesión."""
    respuesta.delete_cookie(key=settings.cookie_nombre, path="/")


async def obtener_usuario_actual(
    respuesta: Response,
    servicio: ServicioAuthDep,
    settings: SettingsDep,
    acceso_token: Annotated[str | None, Cookie()] = None,
) -> Usuario:
    """Valida la sesión y renueva la cookie de forma transparente.

    Si el token venía expirado pero dentro de la ventana de gracia, el
    servicio emite uno nuevo y aquí se reescribe la cookie. El cliente no
    hace nada especial: su siguiente petición ya lleva el token fresco.
    """
    sesion = servicio.validar_sesion(acceso_token)

    if sesion.token_renovado is not None:
        escribir_cookie_sesion(respuesta, sesion.token_renovado, settings)
        # Cabecera informativa para poder demostrar la renovación en la
        # evidencia de pruebas; no es necesaria para el funcionamiento.
        respuesta.headers["X-Token-Renovado"] = "true"

    return sesion.usuario


UsuarioActualDep = Annotated[Usuario, Depends(obtener_usuario_actual)]


def exigir_permiso(permiso: str) -> Callable[..., Usuario]:
    """Crea una dependencia que exige un permiso concreto.

    Es una fábrica de guardas: en lugar de escribir una función distinta
    por cada ruta protegida, cada endpoint declara qué permiso necesita.
    Agregar una ruta nueva no obliga a modificar este código (OCP).
    """

    def guarda(usuario: UsuarioActualDep, servicio: ServicioAuthDep) -> Usuario:
        servicio.exigir_permiso(usuario, permiso)
        return usuario

    return guarda
