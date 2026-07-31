"""Casos de uso de las solicitudes operativas.

Depende de las abstracciones `RepositorioSolicitudes` y
`PoliticaTransicionEstado`, nunca de sus implementaciones concretas
(Dependency Inversion). Es la única capa que conoce las reglas de negocio.
"""

from uuid import UUID, uuid4

from app.domain.entities import EstadoSolicitud, SolicitudOperativa
from app.domain.exceptions import (
    SolicitudNoEncontradaError,
    TransicionEstadoInvalidaError,
)
from app.domain.policies import PoliticaTransicionEstado
from app.domain.repositories import RepositorioSolicitudes


class ServicioSolicitudes:
    """Orquesta las operaciones sobre solicitudes operativas."""

    def __init__(
        self,
        repositorio: RepositorioSolicitudes,
        politica_estado: PoliticaTransicionEstado,
    ) -> None:
        self._repositorio = repositorio
        self._politica_estado = politica_estado

    def listar(self) -> list[SolicitudOperativa]:
        return self._repositorio.listar()

    def obtener(self, solicitud_id: UUID) -> SolicitudOperativa:
        solicitud = self._repositorio.obtener_por_id(solicitud_id)
        if solicitud is None:
            raise SolicitudNoEncontradaError(solicitud_id)
        return solicitud

    def registrar(
        self,
        titulo: str,
        area_solicitante: str,
        prioridad: int,
        costo_estimado,
        estado: EstadoSolicitud,
    ) -> SolicitudOperativa:
        nueva = SolicitudOperativa(
            id=uuid4(),
            titulo=titulo,
            area_solicitante=area_solicitante,
            prioridad=prioridad,
            costo_estimado=costo_estimado,
            estado=estado,
        )
        return self._repositorio.crear(nueva)

    def reemplazar(
        self,
        solicitud_id: UUID,
        titulo: str,
        area_solicitante: str,
        prioridad: int,
        costo_estimado,
        estado: EstadoSolicitud,
    ) -> SolicitudOperativa:
        actualizada = SolicitudOperativa(
            id=solicitud_id,
            titulo=titulo,
            area_solicitante=area_solicitante,
            prioridad=prioridad,
            costo_estimado=costo_estimado,
            estado=estado,
        )
        resultado = self._repositorio.reemplazar(actualizada)
        if resultado is None:
            raise SolicitudNoEncontradaError(solicitud_id)
        return resultado

    def cambiar_estado(
        self, solicitud_id: UUID, nuevo_estado: EstadoSolicitud
    ) -> SolicitudOperativa:
        actual = self.obtener(solicitud_id)
        if not self._politica_estado.es_permitida(actual.estado, nuevo_estado):
            raise TransicionEstadoInvalidaError(actual.estado, nuevo_estado)

        resultado = self._repositorio.cambiar_estado(solicitud_id, nuevo_estado)
        if resultado is None:
            raise SolicitudNoEncontradaError(solicitud_id)
        return resultado

    def eliminar(self, solicitud_id: UUID) -> None:
        if not self._repositorio.eliminar(solicitud_id):
            raise SolicitudNoEncontradaError(solicitud_id)
