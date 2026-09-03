"""Punto de entrada del servicio de autenticación."""

import logging

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import RedirectResponse

from app.api.errors import registrar_manejadores
from app.api.routes import auth, protegidas
from app.core.config import get_settings

logging.basicConfig(level=logging.INFO)


def crear_app() -> FastAPI:
    """Construye y configura la aplicación FastAPI."""
    settings = get_settings()

    app = FastAPI(
        title=settings.app_name,
        version=settings.app_version,
        description="Autenticación con JWT en cookie HTTP-only y roles.",
    )

    # El frontend corre en otro origen y debe poder enviar la cookie,
    # por eso allow_credentials=True. Los orígenes se listan de forma
    # explícita: con credenciales, el comodín '*' no está permitido.
    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.lista_origenes,
        allow_credentials=True,
        allow_methods=["GET", "POST"],
        allow_headers=["Content-Type"],
        expose_headers=["X-Token-Renovado"],
    )

    registrar_manejadores(app)
    app.include_router(auth.router)
    app.include_router(protegidas.router)

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
