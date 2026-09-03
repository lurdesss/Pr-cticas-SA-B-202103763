"""Contratos de entrada y salida de la API REST."""

from __future__ import annotations

from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field


class ResenaEntrada(BaseModel):
    producto_id: str = Field(min_length=1, max_length=40)
    calificacion: int = Field(ge=1, le=5)
    comentario: str = Field(default="", max_length=500)


class ResenaSalida(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    producto_id: str
    usuario_id: str
    usuario_nombre: str
    calificacion: int
    comentario: str
    creado_en: datetime


class ResumenSalida(BaseModel):
    producto_id: str
    total: int
    promedio: float
    distribucion: dict[int, int]
