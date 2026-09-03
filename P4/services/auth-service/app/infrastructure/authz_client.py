"""Cliente del microservicio de autorización.

Implementa el requisito 9 del enunciado: ante fallas temporales o
timeouts, el backend reintenta con espera creciente (backoff exponencial)
hasta un máximo configurable antes de denegar el acceso por error de
comunicación.

Distinción importante entre dos situaciones que no deben confundirse:

- El servicio **responde** que el rol no tiene el permiso  → acceso
  denegado (403). No se reintenta: la respuesta es definitiva.
- El servicio **no responde** (timeout, conexión rechazada, error 5xx)
  → se reintenta. Agotados los intentos, se lanza una excepción propia
  que la API traduce a 503, no a 403. Un problema de infraestructura no
  debe reportarse como falta de permisos.
"""

import logging
import time

import httpx

from app.core.config import Settings
from app.domain.exceptions import ServicioAutorizacionNoDisponibleError
from app.domain.repositories import ClienteAutorizacion

logger = logging.getLogger(__name__)

_MILISEGUNDOS_POR_SEGUNDO = 1000


class ClienteAutorizacionHTTP(ClienteAutorizacion):
    """Consulta el microservicio de autorización por HTTP."""

    def __init__(self, settings: Settings) -> None:
        self._url = settings.authz_url.rstrip("/")
        self._max_reintentos = settings.authz_max_reintentos
        self._backoff_inicial = (
            settings.authz_backoff_inicial_ms / _MILISEGUNDOS_POR_SEGUNDO
        )
        self._backoff_factor = settings.authz_backoff_factor
        self._timeout = settings.authz_timeout_ms / _MILISEGUNDOS_POR_SEGUNDO

    def tiene_permiso(self, rol: str, permiso: str) -> bool:
        """Pregunta al microservicio si el rol posee el permiso.

        Recorre hasta `authz_max_reintentos` intentos, esperando cada vez
        más entre uno y otro. Si alguno obtiene respuesta, se devuelve de
        inmediato sin agotar el resto.
        """
        espera = self._backoff_inicial

        for intento in range(1, self._max_reintentos + 1):
            respuesta = self._consultar_una_vez(rol, permiso, intento)
            if respuesta is not None:
                return respuesta

            if intento < self._max_reintentos:
                logger.warning(
                    "Autorización sin respuesta (intento %s/%s). "
                    "Reintentando en %.2f s.",
                    intento,
                    self._max_reintentos,
                    espera,
                )
                time.sleep(espera)
                espera *= self._backoff_factor

        logger.error(
            "Autorización agotó %s intentos para rol=%s permiso=%s.",
            self._max_reintentos,
            rol,
            permiso,
        )
        raise ServicioAutorizacionNoDisponibleError(self._max_reintentos)

    def _consultar_una_vez(self, rol: str, permiso: str, intento: int) -> bool | None:
        """Realiza un intento único.

        Devuelve `True`/`False` si el servicio dio un veredicto, o `None`
        si el intento debe repetirse por un fallo transitorio.
        """
        try:
            with httpx.Client(timeout=self._timeout) as cliente:
                respuesta = cliente.post(
                    f"{self._url}/autorizacion/verificar",
                    json={"rol": rol, "permiso": permiso},
                )

            if respuesta.status_code >= 500:
                # Error del servidor: puede ser transitorio, se reintenta.
                return None

            if respuesta.status_code != httpx.codes.OK:
                # 4xx: la petición está mal formada. Reintentar no la
                # va a arreglar, así que se trata como denegación.
                logger.error(
                    "Autorización respondió %s en el intento %s.",
                    respuesta.status_code,
                    intento,
                )
                return False

            return bool(respuesta.json().get("permitido", False))

        except (httpx.TimeoutException, httpx.TransportError):
            # Timeout o conexión rechazada: candidatos claros a reintento.
            return None
        except ValueError:
            # Respuesta 200 con cuerpo que no es JSON válido.
            logger.error("Autorización devolvió un cuerpo no interpretable.")
            return None
