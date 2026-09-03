"""Insumos de ejemplo para que la demostracion tenga datos desde el inicio."""

from __future__ import annotations

from decimal import Decimal

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.modelos import Insumo

INSUMOS = [
    ("Cafe en grano Acatenango", "kg", Decimal("18.00"), Decimal("5.00")),
    ("Leche entera", "litro", Decimal("24.00"), Decimal("10.00")),
    ("Leche de avena", "litro", Decimal("6.00"), Decimal("8.00")),
    ("Cardamomo verde", "kg", Decimal("0.80"), Decimal("0.50")),
    ("Vasos de 12 onzas", "unidad", Decimal("340.00"), Decimal("100.00")),
    ("Filtros V60", "unidad", Decimal("90.00"), Decimal("50.00")),
]


def sembrar(sesion: Session) -> None:
    if sesion.scalar(select(func.count()).select_from(Insumo)):
        return

    for nombre, unidad, existencia, minimo in INSUMOS:
        sesion.add(Insumo(nombre=nombre, unidad=unidad, existencia=existencia, minimo=minimo))
    print("[inventario] insumos de ejemplo cargados.")
