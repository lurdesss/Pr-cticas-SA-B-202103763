"""Errores del dominio.

No heredan de `HTTPException`: el dominio no conoce el protocolo HTTP.
La capa de API es la única que traduce estos errores a códigos de estado.
"""

from uuid import UUID

from app.domain.entities import EstadoSolicitud


class DominioError(Exception):
    """Base de todos los errores de negocio."""


class SolicitudNoEncontradaError(DominioError):
    """La solicitud solicitada no existe en el repositorio."""

    def __init__(self, solicitud_id: UUID) -> None:
        self.solicitud_id = solicitud_id
        super().__init__(f"No existe una solicitud con id {solicitud_id}.")


class TransicionEstadoInvalidaError(DominioError):
    """El cambio de estado solicitado viola las reglas de negocio."""

    def __init__(self, actual: EstadoSolicitud, nuevo: EstadoSolicitud) -> None:
        self.actual = actual
        self.nuevo = nuevo
        super().__init__(
            f"No se permite pasar del estado '{actual.value}' a '{nuevo.value}'."
        )
