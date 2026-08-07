"""Contratos de persistencia definidos por el dominio (DIP + ISP)."""

from abc import ABC, abstractmethod
from uuid import UUID

from app.domain.entities import Usuario


class LectorUsuarios(ABC):
    """Operaciones de solo lectura sobre usuarios."""

    @abstractmethod
    def obtener_por_correo(self, correo: str) -> Usuario | None:
        """Devuelve el usuario dueño del correo, o `None` si no existe."""

    @abstractmethod
    def obtener_por_id(self, usuario_id: UUID) -> Usuario | None:
        """Devuelve el usuario con ese identificador, o `None`."""


class EscritorUsuarios(ABC):
    """Operaciones de escritura sobre usuarios."""

    @abstractmethod
    def crear(self, usuario: Usuario) -> Usuario:
        """Persiste un usuario nuevo."""


class RepositorioUsuarios(LectorUsuarios, EscritorUsuarios, ABC):
    """Repositorio completo: composición de los dos contratos anteriores."""


class ClienteAutorizacion(ABC):
    """Contrato del microservicio de autorización.

    Está declarado en el dominio para que el servicio de aplicación no
    dependa de HTTP ni de httpx. Si mañana la autorización se consulta
    por gRPC o por cola de mensajes, solo cambia la implementación.
    """

    @abstractmethod
    def tiene_permiso(self, rol: str, permiso: str) -> bool:
        """Consulta si un rol posee el permiso indicado.

        Debe lanzar `ServicioAutorizacionNoDisponibleError` si no logra
        una respuesta; devolver `False` ante un fallo de red confundiría
        'sin permiso' con 'no pude preguntar'.
        """
