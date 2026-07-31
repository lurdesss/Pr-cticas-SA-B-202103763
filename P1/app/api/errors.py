"""Traducción de errores del dominio a respuestas HTTP.

Centralizar el manejo de errores evita repetir bloques `try/except` en
cada endpoint y garantiza que la API nunca devuelva trazas internas al
cliente (OWASP A05:2021 - Security Misconfiguration).
"""

import logging

from fastapi import FastAPI, Request, status
from fastapi.responses import JSONResponse

from app.domain.exceptions import (
    SolicitudNoEncontradaError,
    TransicionEstadoInvalidaError,
)

logger = logging.getLogger(__name__)


async def manejar_no_encontrada(
    _: Request, exc: SolicitudNoEncontradaError
) -> JSONResponse:
    return JSONResponse(
        status_code=status.HTTP_404_NOT_FOUND,
        content={"detalle": str(exc)},
    )


async def manejar_transicion_invalida(
    _: Request, exc: TransicionEstadoInvalidaError
) -> JSONResponse:
    return JSONResponse(
        status_code=status.HTTP_409_CONFLICT,
        content={"detalle": str(exc)},
    )


async def manejar_error_inesperado(_: Request, exc: Exception) -> JSONResponse:
    """Registra el detalle en el log y responde con un mensaje genérico."""
    logger.exception("Error no controlado: %s", exc)
    return JSONResponse(
        status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
        content={"detalle": "Ocurrió un error interno al procesar la solicitud."},
    )


def registrar_manejadores(app: FastAPI) -> None:
    """Asocia cada excepción de dominio con su respuesta HTTP."""
    app.add_exception_handler(SolicitudNoEncontradaError, manejar_no_encontrada)
    app.add_exception_handler(
        TransicionEstadoInvalidaError, manejar_transicion_invalida
    )
    app.add_exception_handler(Exception, manejar_error_inesperado)
