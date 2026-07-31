"""Entidades del dominio.

Este módulo no importa FastAPI, SQLAlchemy ni ninguna librería de
infraestructura: el dominio no debe saber cómo se persiste ni cómo se
expone por HTTP.
"""

from dataclasses import dataclass, replace
from decimal import Decimal
from enum import StrEnum
from uuid import UUID


class EstadoSolicitud(StrEnum):
    """Estados válidos del ciclo de vida de una solicitud operativa."""

    REGISTRADA = "registrada"
    EN_PROCESO = "en_proceso"
    FINALIZADA = "finalizada"


@dataclass(frozen=True, slots=True)
class SolicitudOperativa:
    """Solicitud interna de la academia.

    Es inmutable (`frozen=True`): cualquier cambio produce una instancia
    nueva mediante `con_estado`, lo que evita mutaciones accidentales
    compartidas entre capas.
    """

    id: UUID
    titulo: str
    area_solicitante: str
    prioridad: int
    costo_estimado: Decimal
    estado: EstadoSolicitud

    def con_estado(self, nuevo_estado: EstadoSolicitud) -> "SolicitudOperativa":
        """Devuelve una copia de la solicitud con el estado cambiado."""
        return replace(self, estado=nuevo_estado)
