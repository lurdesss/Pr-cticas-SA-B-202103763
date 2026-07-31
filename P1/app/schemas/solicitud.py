"""Esquemas de entrada y salida de la API (capa de validación).

Toda la validación de formato vive aquí. Los datos que llegan al servicio
ya están saneados: longitudes acotadas, rangos numéricos correctos y
estados dentro del enumerado. Es la primera barrera contra entradas
maliciosas o malformadas.
"""

from decimal import Decimal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, field_serializer, field_validator

from app.domain.entities import EstadoSolicitud

DOS_DECIMALES = Decimal("0.01")


class SolicitudBase(BaseModel):
    """Campos compartidos por las operaciones de escritura."""

    model_config = ConfigDict(str_strip_whitespace=True, extra="forbid")

    titulo: str = Field(min_length=3, max_length=120)
    area_solicitante: str = Field(min_length=3, max_length=80)
    prioridad: int = Field(ge=1, le=5)
    costo_estimado: Decimal = Field(ge=0, max_digits=12, decimal_places=2)
    estado: EstadoSolicitud = EstadoSolicitud.REGISTRADA

    @field_validator("titulo", "area_solicitante")
    @classmethod
    def validar_texto_no_vacio(cls, valor: str) -> str:
        """Rechaza cadenas que solo contienen espacios en blanco."""
        if not valor.strip():
            raise ValueError("El campo no puede estar vacío.")
        return valor


class SolicitudCrear(SolicitudBase):
    """Cuerpo del POST /solicitudes."""


class SolicitudReemplazar(SolicitudBase):
    """Cuerpo del PUT /solicitudes/{id}: reemplaza todos los atributos."""


class EstadoActualizar(BaseModel):
    """Cuerpo del PATCH /solicitudes/{id}/estado."""

    model_config = ConfigDict(extra="forbid")

    estado: EstadoSolicitud


class SolicitudRespuesta(BaseModel):
    """Representación pública de una solicitud."""

    model_config = ConfigDict(from_attributes=True)

    id: UUID
    titulo: str
    area_solicitante: str
    prioridad: int
    costo_estimado: Decimal
    estado: EstadoSolicitud

    @field_serializer("costo_estimado")
    def serializar_costo(self, valor: Decimal) -> str:
        """Devuelve el monto como texto con dos decimales.

        Se evita `float` a propósito: los montos de dinero pierden
        precisión en punto flotante binario (0.1 + 0.2 != 0.3).
        """
        return str(valor.quantize(DOS_DECIMALES))
