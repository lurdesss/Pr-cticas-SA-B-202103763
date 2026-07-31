"""Contratos de persistencia definidos por el dominio.

El dominio declara lo que necesita; la infraestructura se adapta.
Las interfaces están segregadas (ISP): un consumidor que solo lee no
queda obligado a conocer los métodos de escritura.
"""

from abc import ABC, abstractmethod
from uuid import UUID

from app.domain.entities import EstadoSolicitud, SolicitudOperativa


class LectorSolicitudes(ABC):
    """Operaciones de solo lectura."""

    @abstractmethod
    def listar(self) -> list[SolicitudOperativa]:
        """Devuelve todas las solicitudes registradas."""

    @abstractmethod
    def obtener_por_id(self, solicitud_id: UUID) -> SolicitudOperativa | None:
        """Devuelve una solicitud o `None` si no existe."""


class EscritorSolicitudes(ABC):
    """Operaciones de escritura."""

    @abstractmethod
    def crear(self, solicitud: SolicitudOperativa) -> SolicitudOperativa:
        """Persiste una solicitud nueva."""

    @abstractmethod
    def reemplazar(self, solicitud: SolicitudOperativa) -> SolicitudOperativa | None:
        """Sustituye todos los atributos de una solicitud existente."""

    @abstractmethod
    def cambiar_estado(
        self, solicitud_id: UUID, estado: EstadoSolicitud
    ) -> SolicitudOperativa | None:
        """Actualiza únicamente el estado, sin tocar el resto de campos."""

    @abstractmethod
    def eliminar(self, solicitud_id: UUID) -> bool:
        """Elimina la solicitud. Devuelve `False` si no existía."""


class RepositorioSolicitudes(LectorSolicitudes, EscritorSolicitudes, ABC):
    """Repositorio completo: composición de los dos contratos anteriores."""
