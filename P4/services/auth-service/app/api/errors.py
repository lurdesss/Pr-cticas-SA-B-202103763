"""Traducción de errores del dominio a respuestas HTTP.

Centralizar el manejo evita repetir `try/except` en cada endpoint y
garantiza que la API nunca devuelva trazas internas al cliente
(OWASP A05).
"""

import logging

from fastapi import FastAPI, Request, status
from fastapi.responses import JSONResponse

from app.domain.exceptions import (
    AccesoDenegadoError,
    CorreoYaRegistradoError,
    CredencialesInvalidasError,
    NoAutenticadoError,
    ServicioAutorizacionNoDisponibleError,
)

logger = logging.getLogger(__name__)


def _respuesta(codigo: int, detalle: str) -> JSONResponse:
    return JSONResponse(status_code=codigo, content={"detalle": detalle})


def registrar_manejadores(app: FastAPI) -> None:
    """Asocia cada excepción de dominio con su código HTTP."""

    @app.exception_handler(CorreoYaRegistradoError)
    async def _correo_duplicado(_: Request, exc: CorreoYaRegistradoError):
        return _respuesta(status.HTTP_409_CONFLICT, str(exc))

    @app.exception_handler(CredencialesInvalidasError)
    async def _credenciales(_: Request, exc: CredencialesInvalidasError):
        return _respuesta(status.HTTP_401_UNAUTHORIZED, str(exc))

    @app.exception_handler(NoAutenticadoError)
    async def _no_autenticado(_: Request, exc: NoAutenticadoError):
        return _respuesta(status.HTTP_401_UNAUTHORIZED, str(exc))

    @app.exception_handler(AccesoDenegadoError)
    async def _denegado(_: Request, exc: AccesoDenegadoError):
        return _respuesta(status.HTTP_403_FORBIDDEN, str(exc))

    @app.exception_handler(ServicioAutorizacionNoDisponibleError)
    async def _authz_caido(_: Request, exc: ServicioAutorizacionNoDisponibleError):
        # 503 y no 403: el acceso no se denegó por falta de permisos,
        # sino porque no se pudo consultar quién los tiene.
        return _respuesta(status.HTTP_503_SERVICE_UNAVAILABLE, str(exc))

    @app.exception_handler(Exception)
    async def _inesperado(_: Request, exc: Exception):
        logger.exception("Error no controlado: %s", exc)
        return _respuesta(
            status.HTTP_500_INTERNAL_SERVER_ERROR,
            "Ocurrió un error interno al procesar la solicitud.",
        )
