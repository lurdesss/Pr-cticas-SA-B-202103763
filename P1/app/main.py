"""Punto de entrada de la aplicación.

Se usa el patrón *application factory*: la app se construye dentro de una
función, lo que permite crear instancias distintas en las pruebas.
"""

import logging

from fastapi import FastAPI
from fastapi.responses import RedirectResponse

from app.api.errors import registrar_manejadores
from app.api.routes import solicitudes
from app.core.config import get_settings

logging.basicConfig(level=logging.INFO)


def crear_app() -> FastAPI:
    """Construye y configura la aplicación FastAPI."""
    settings = get_settings()

    app = FastAPI(
        title=settings.app_name,
        version=settings.app_version,
        description="API REST para la gestión de solicitudes operativas.",
    )

    registrar_manejadores(app)
    app.include_router(solicitudes.router)
    
    @app.get("/", include_in_schema=False)
    def ir_a_documentacion() -> RedirectResponse:
        """Redirige la raíz a la documentación interactiva."""
        return RedirectResponse(url="/docs")

    @app.get("/salud", tags=["Sistema"])
    def verificar_salud() -> dict[str, str]:
        """Endpoint de monitoreo."""
        return {"estado": "ok", "version": settings.app_version}

    return app


app = crear_app()
