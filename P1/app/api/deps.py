"""Composición de dependencias.

Este es el único lugar donde las abstracciones se atan a implementaciones
concretas. Cambiar de PostgreSQL a otro motor implica modificar
únicamente este archivo.
"""

from typing import Annotated

from fastapi import Depends
from sqlalchemy.orm import Session

from app.core.database import get_session
from app.domain.policies import PoliticaTransicionEstado, TransicionSecuencial
from app.domain.repositories import RepositorioSolicitudes
from app.infrastructure.postgres_repository import RepositorioSolicitudesPostgres
from app.services.solicitud_service import ServicioSolicitudes

SesionBD = Annotated[Session, Depends(get_session)]


def obtener_repositorio(session: SesionBD) -> RepositorioSolicitudes:
    """Devuelve la implementación de repositorio en uso."""
    return RepositorioSolicitudesPostgres(session)


def obtener_politica_estado() -> PoliticaTransicionEstado:
    """Devuelve la política de transición de estados configurada."""
    return TransicionSecuencial()


def obtener_servicio(
    repositorio: Annotated[RepositorioSolicitudes, Depends(obtener_repositorio)],
    politica: Annotated[PoliticaTransicionEstado, Depends(obtener_politica_estado)],
) -> ServicioSolicitudes:
    """Arma el servicio con sus dependencias ya resueltas."""
    return ServicioSolicitudes(repositorio, politica)


ServicioSolicitudesDep = Annotated[ServicioSolicitudes, Depends(obtener_servicio)]
