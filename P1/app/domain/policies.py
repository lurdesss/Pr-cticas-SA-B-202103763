"""Reglas de negocio sobre el cambio de estado de una solicitud.

Se aísla en su propia clase para poder agregar políticas distintas
(por ejemplo, una que permita reabrir solicitudes finalizadas) sin tocar
el servicio que las consume: Open/Closed en la práctica.
"""

from abc import ABC, abstractmethod

from app.domain.entities import EstadoSolicitud


class PoliticaTransicionEstado(ABC):
    """Contrato de una política de transición de estados."""

    @abstractmethod
    def es_permitida(self, actual: EstadoSolicitud, nuevo: EstadoSolicitud) -> bool:
        """Indica si se puede pasar de `actual` a `nuevo`."""


class TransicionSecuencial(PoliticaTransicionEstado):
    """Política por defecto: el flujo avanza y no retrocede.

    registrada -> en_proceso -> finalizada
    """

    _TRANSICIONES_VALIDAS: dict[EstadoSolicitud, frozenset[EstadoSolicitud]] = {
        EstadoSolicitud.REGISTRADA: frozenset(
            {EstadoSolicitud.EN_PROCESO, EstadoSolicitud.FINALIZADA}
        ),
        EstadoSolicitud.EN_PROCESO: frozenset({EstadoSolicitud.FINALIZADA}),
        EstadoSolicitud.FINALIZADA: frozenset(),
    }

    def es_permitida(self, actual: EstadoSolicitud, nuevo: EstadoSolicitud) -> bool:
        if actual == nuevo:
            return True  # operación idempotente
        return nuevo in self._TRANSICIONES_VALIDAS[actual]
