"""Repositorio en memoria usado por las pruebas automatizadas.

Cumple exactamente el mismo contrato que el repositorio de PostgreSQL,
por lo que el servicio funciona con cualquiera de los dos sin cambiar
una sola línea (Liskov + Open/Closed).
"""

from uuid import UUID

from app.domain.entities import EstadoSolicitud, SolicitudOperativa
from app.domain.repositories import RepositorioSolicitudes


class RepositorioSolicitudesMemoria(RepositorioSolicitudes):
    """Almacena las solicitudes en un diccionario en memoria."""

    def __init__(self) -> None:
        self._datos: dict[UUID, SolicitudOperativa] = {}

    def listar(self) -> list[SolicitudOperativa]:
        return sorted(self._datos.values(), key=lambda item: item.prioridad)

    def obtener_por_id(self, solicitud_id: UUID) -> SolicitudOperativa | None:
        return self._datos.get(solicitud_id)

    def crear(self, solicitud: SolicitudOperativa) -> SolicitudOperativa:
        self._datos[solicitud.id] = solicitud
        return solicitud

    def reemplazar(self, solicitud: SolicitudOperativa) -> SolicitudOperativa | None:
        if solicitud.id not in self._datos:
            return None

        self._datos[solicitud.id] = solicitud
        return solicitud

    def cambiar_estado(
        self, solicitud_id: UUID, estado: EstadoSolicitud
    ) -> SolicitudOperativa | None:
        solicitud = self._datos.get(solicitud_id)
        if solicitud is None:
            return None

        actualizada = solicitud.con_estado(estado)
        self._datos[solicitud_id] = actualizada
        return actualizada

    def eliminar(self, solicitud_id: UUID) -> bool:
        return self._datos.pop(solicitud_id, None) is not None
