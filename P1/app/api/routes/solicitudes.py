"""Endpoints REST de solicitudes operativas.

La única responsabilidad de esta capa es traducir HTTP a llamadas del
servicio y devolver el código de estado correcto. No contiene reglas de
negocio ni consultas a la base de datos.
"""

from uuid import UUID

from fastapi import APIRouter, status

from app.api.deps import ServicioSolicitudesDep
from app.schemas.solicitud import (
    EstadoActualizar,
    SolicitudCrear,
    SolicitudReemplazar,
    SolicitudRespuesta,
)

router = APIRouter(prefix="/api/v1/solicitudes", tags=["Solicitudes operativas"])


@router.get("", response_model=list[SolicitudRespuesta])
def listar_solicitudes(servicio: ServicioSolicitudesDep) -> list[SolicitudRespuesta]:
    """Obtiene todas las solicitudes operativas."""
    return servicio.listar()


@router.get("/{solicitud_id}", response_model=SolicitudRespuesta)
def obtener_solicitud(
    solicitud_id: UUID, servicio: ServicioSolicitudesDep
) -> SolicitudRespuesta:
    """Obtiene una solicitud puntual por su identificador."""
    return servicio.obtener(solicitud_id)


@router.post("", response_model=SolicitudRespuesta, status_code=status.HTTP_201_CREATED)
def registrar_solicitud(
    datos: SolicitudCrear, servicio: ServicioSolicitudesDep
) -> SolicitudRespuesta:
    """Registra una nueva solicitud operativa."""
    return servicio.registrar(**datos.model_dump())


@router.put("/{solicitud_id}", response_model=SolicitudRespuesta)
def reemplazar_solicitud(
    solicitud_id: UUID,
    datos: SolicitudReemplazar,
    servicio: ServicioSolicitudesDep,
) -> SolicitudRespuesta:
    """Reemplaza por completo la información de una solicitud existente."""
    return servicio.reemplazar(solicitud_id, **datos.model_dump())


@router.patch("/{solicitud_id}/estado", response_model=SolicitudRespuesta)
def actualizar_estado(
    solicitud_id: UUID,
    datos: EstadoActualizar,
    servicio: ServicioSolicitudesDep,
) -> SolicitudRespuesta:
    """Actualiza exclusivamente el estado de una solicitud."""
    return servicio.cambiar_estado(solicitud_id, datos.estado)


@router.delete("/{solicitud_id}", status_code=status.HTTP_204_NO_CONTENT)
def eliminar_solicitud(solicitud_id: UUID, servicio: ServicioSolicitudesDep) -> None:
    """Elimina una solicitud operativa."""
    servicio.eliminar(solicitud_id)
