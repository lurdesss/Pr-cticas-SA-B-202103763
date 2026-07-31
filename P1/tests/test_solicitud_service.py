"""Pruebas del servicio usando el repositorio en memoria.

Que estas pruebas pasen sin tocar PostgreSQL es la evidencia práctica de
que el servicio depende de la abstracción y no de la implementación.
"""

from decimal import Decimal
from uuid import uuid4

import pytest

from app.domain.entities import EstadoSolicitud
from app.domain.exceptions import (
    SolicitudNoEncontradaError,
    TransicionEstadoInvalidaError,
)
from app.domain.policies import TransicionSecuencial
from app.infrastructure.memory_repository import RepositorioSolicitudesMemoria
from app.services.solicitud_service import ServicioSolicitudes


@pytest.fixture
def servicio() -> ServicioSolicitudes:
    return ServicioSolicitudes(RepositorioSolicitudesMemoria(), TransicionSecuencial())


def registrar_ejemplo(servicio: ServicioSolicitudes):
    return servicio.registrar(
        titulo="Adquisición de nuevo servidor",
        area_solicitante="Infraestructura TI",
        prioridad=3,
        costo_estimado=Decimal("2500.00"),
        estado=EstadoSolicitud.REGISTRADA,
    )


def test_registrar_asigna_identificador(servicio: ServicioSolicitudes) -> None:
    solicitud = registrar_ejemplo(servicio)
    assert solicitud.id is not None
    assert servicio.obtener(solicitud.id) == solicitud


def test_cambiar_estado_avanza_el_flujo(servicio: ServicioSolicitudes) -> None:
    solicitud = registrar_ejemplo(servicio)
    actualizada = servicio.cambiar_estado(solicitud.id, EstadoSolicitud.EN_PROCESO)

    assert actualizada.estado == EstadoSolicitud.EN_PROCESO
    assert actualizada.titulo == solicitud.titulo  # el resto no se modificó


def test_no_se_puede_retroceder_de_finalizada(servicio: ServicioSolicitudes) -> None:
    solicitud = registrar_ejemplo(servicio)
    servicio.cambiar_estado(solicitud.id, EstadoSolicitud.FINALIZADA)

    with pytest.raises(TransicionEstadoInvalidaError):
        servicio.cambiar_estado(solicitud.id, EstadoSolicitud.EN_PROCESO)


def test_obtener_inexistente_lanza_error(servicio: ServicioSolicitudes) -> None:
    with pytest.raises(SolicitudNoEncontradaError):
        servicio.obtener(uuid4())


def test_eliminar_quita_la_solicitud(servicio: ServicioSolicitudes) -> None:
    solicitud = registrar_ejemplo(servicio)
    servicio.eliminar(solicitud.id)

    assert servicio.listar() == []
