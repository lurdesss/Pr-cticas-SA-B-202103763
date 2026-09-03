"""Modelo de datos de las resenas."""

from __future__ import annotations

from datetime import datetime

from sqlalchemy import CheckConstraint, DateTime, Integer, String, Text, UniqueConstraint, func
from sqlalchemy.orm import Mapped, mapped_column

from app.db import Base


class Resena(Base):
    __tablename__ = "resenas"

    id: Mapped[int] = mapped_column(primary_key=True)
    producto_id: Mapped[str] = mapped_column(String(40), nullable=False, index=True)
    usuario_id: Mapped[str] = mapped_column(String(80), nullable=False, index=True)
    usuario_nombre: Mapped[str] = mapped_column(String(120), nullable=False, default="")
    calificacion: Mapped[int] = mapped_column(Integer, nullable=False)
    comentario: Mapped[str] = mapped_column(Text, nullable=False, default="")
    creado_en: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())

    __table_args__ = (
        # Una persona opina una vez por producto: sin esto, un mismo usuario
        # podria inflar el promedio repitiendo la misma resena.
        UniqueConstraint("producto_id", "usuario_id", name="uq_resena_por_usuario"),
        CheckConstraint("calificacion BETWEEN 1 AND 5", name="ck_calificacion_1_a_5"),
    )
