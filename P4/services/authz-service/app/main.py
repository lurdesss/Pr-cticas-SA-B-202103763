"""Microservicio de autorización (requisito 9 del enunciado).

Servicio independiente y sin estado: recibe un rol y un permiso, y
responde si el acceso está permitido. No conoce usuarios, no consulta la
base de datos y no valida contraseñas; esa es responsabilidad del
servicio de autenticación.

Esta separación es la que permite que la política de acceso cambie sin
tocar el backend principal.
"""

import asyncio
import logging
import os

from fastapi import FastAPI
from pydantic import BaseModel, ConfigDict, Field

from app.politicas import PERMISOS_POR_ROL, rol_tiene_permiso

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(
    title="Microservicio de Autorización",
    version="1.0.0",
    description="Valida permisos por rol. No autentica usuarios.",
)

# Latencia artificial para poder demostrar el retry loop del backend.
# En condiciones normales vale 0.
RETRASO_SIMULADO_MS = int(os.getenv("AUTHZ_RETRASO_SIMULADO_MS", "0"))


class VerificacionPeticion(BaseModel):
    """Cuerpo de POST /autorizacion/verificar."""

    model_config = ConfigDict(str_strip_whitespace=True, extra="forbid")

    rol: str = Field(min_length=1, max_length=40)
    permiso: str = Field(min_length=1, max_length=60)


class VerificacionRespuesta(BaseModel):
    """Veredicto de autorización."""

    permitido: bool
    rol: str
    permiso: str


@app.post("/autorizacion/verificar", response_model=VerificacionRespuesta)
async def verificar(peticion: VerificacionPeticion) -> VerificacionRespuesta:
    """Responde si el rol indicado posee el permiso solicitado."""
    if RETRASO_SIMULADO_MS > 0:
        await asyncio.sleep(RETRASO_SIMULADO_MS / 1000)

    permitido = rol_tiene_permiso(peticion.rol, peticion.permiso)
    logger.info(
        "Autorización rol=%s permiso=%s -> %s",
        peticion.rol,
        peticion.permiso,
        "permitido" if permitido else "denegado",
    )
    return VerificacionRespuesta(
        permitido=permitido, rol=peticion.rol, permiso=peticion.permiso
    )


@app.get("/autorizacion/politicas", tags=["Consulta"])
def listar_politicas() -> dict[str, list[str]]:
    """Expone la matriz de permisos vigente, útil para auditoría."""
    return {rol: sorted(permisos) for rol, permisos in PERMISOS_POR_ROL.items()}


@app.get("/salud", tags=["Sistema"])
def verificar_salud() -> dict[str, str]:
    """Endpoint de monitoreo."""
    return {"estado": "ok", "servicio": "autorizacion"}
