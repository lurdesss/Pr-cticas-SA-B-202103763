"""Modelo de datos del inventario: insumos y sus movimientos."""

from __future__ import annotations

from datetime import datetime
from decimal import Decimal

from sqlalchemy import CheckConstraint, DateTime, ForeignKey, Numeric, String, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db import Base

TIPOS_DE_MOVIMIENTO = ("entrada", "salida", "ajuste")


class Insumo(Base):
    __tablename__ = "insumos"

    id: Mapped[int] = mapped_column(primary_key=True)
    nombre: Mapped[str] = mapped_column(String(120), unique=True, nullable=False)
    unidad: Mapped[str] = mapped_column(String(20), nullable=False, default="unidad")
    existencia: Mapped[Decimal] = mapped_column(Numeric(12, 2), nullable=False, default=0)
    minimo: Mapped[Decimal] = mapped_column(Numeric(12, 2), nullable=False, default=0)
    actualizado_en: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )

    movimientos: Mapped[list["Movimiento"]] = relationship(
        back_populates="insumo", cascade="all, delete-orphan"
    )

    __table_args__ = (CheckConstraint("existencia >= 0", name="ck_existencia_no_negativa"),)


class Movimiento(Base):
    __tablename__ = "movimientos"

    id: Mapped[int] = mapped_column(primary_key=True)
    insumo_id: Mapped[int] = mapped_column(ForeignKey("insumos.id", ondelete="CASCADE"), index=True)
    tipo: Mapped[str] = mapped_column(String(20), nullable=False)
    cantidad: Mapped[Decimal] = mapped_column(Numeric(12, 2), nullable=False)
    motivo: Mapped[str] = mapped_column(String(200), nullable=False, default="")
    usuario_id: Mapped[str] = mapped_column(String(80), nullable=False, default="")
    creado_en: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())

    insumo: Mapped[Insumo] = relationship(back_populates="movimientos")

    __table_args__ = (
        CheckConstraint("cantidad > 0", name="ck_cantidad_positiva"),
        CheckConstraint(
            "tipo IN ('entrada', 'salida', 'ajuste')", name="ck_tipo_de_movimiento"
        ),
    )
