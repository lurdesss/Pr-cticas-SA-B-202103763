"""Implementación del repositorio sobre PostgreSQL.

Todas las consultas se construyen con el lenguaje de expresiones de
SQLAlchemy, que envía los valores como parámetros ligados (bind params).
No se concatena texto SQL en ningún punto: eso elimina por diseño el
riesgo de inyección SQL (OWASP A03:2021 - Injection).
"""

from uuid import UUID

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.domain.entities import EstadoSolicitud, SolicitudOperativa
from app.domain.repositories import RepositorioSolicitudes
from app.infrastructure.models import SolicitudOperativaModel


def _a_entidad(fila: SolicitudOperativaModel) -> SolicitudOperativa:
    """Traduce una fila del ORM a la entidad de dominio."""
    return SolicitudOperativa(
        id=fila.id,
        titulo=fila.titulo,
        area_solicitante=fila.area_solicitante,
        prioridad=fila.prioridad,
        costo_estimado=fila.costo_estimado,
        estado=EstadoSolicitud(fila.estado),
    )


class RepositorioSolicitudesPostgres(RepositorioSolicitudes):
    """Persistencia real de solicitudes operativas."""

    def __init__(self, session: Session) -> None:
        self._session = session

    def listar(self) -> list[SolicitudOperativa]:
        sentencia = select(SolicitudOperativaModel).order_by(
            SolicitudOperativaModel.prioridad
        )
        return [_a_entidad(fila) for fila in self._session.scalars(sentencia)]

    def obtener_por_id(self, solicitud_id: UUID) -> SolicitudOperativa | None:
        fila = self._session.get(SolicitudOperativaModel, solicitud_id)
        return _a_entidad(fila) if fila else None

    def crear(self, solicitud: SolicitudOperativa) -> SolicitudOperativa:
        fila = SolicitudOperativaModel(
            id=solicitud.id,
            titulo=solicitud.titulo,
            area_solicitante=solicitud.area_solicitante,
            prioridad=solicitud.prioridad,
            costo_estimado=solicitud.costo_estimado,
            estado=solicitud.estado.value,
        )
        self._session.add(fila)
        self._session.commit()
        return _a_entidad(fila)

    def reemplazar(self, solicitud: SolicitudOperativa) -> SolicitudOperativa | None:
        fila = self._session.get(SolicitudOperativaModel, solicitud.id)
        if fila is None:
            return None

        fila.titulo = solicitud.titulo
        fila.area_solicitante = solicitud.area_solicitante
        fila.prioridad = solicitud.prioridad
        fila.costo_estimado = solicitud.costo_estimado
        fila.estado = solicitud.estado.value
        self._session.commit()
        return _a_entidad(fila)

    def cambiar_estado(
        self, solicitud_id: UUID, estado: EstadoSolicitud
    ) -> SolicitudOperativa | None:
        fila = self._session.get(SolicitudOperativaModel, solicitud_id)
        if fila is None:
            return None

        fila.estado = estado.value
        self._session.commit()
        return _a_entidad(fila)

    def eliminar(self, solicitud_id: UUID) -> bool:
        fila = self._session.get(SolicitudOperativaModel, solicitud_id)
        if fila is None:
            return False

        self._session.delete(fila)
        self._session.commit()
        return True
