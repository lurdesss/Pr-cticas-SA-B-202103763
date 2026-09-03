"""Reglas del inventario. No sabe nada de GraphQL ni de HTTP."""

from __future__ import annotations

from decimal import Decimal

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.modelos import TIPOS_DE_MOVIMIENTO, Insumo, Movimiento


class ErrorDeInventario(Exception):
    """Regla de negocio incumplida."""


def listar_insumos(sesion: Session) -> list[Insumo]:
    return list(sesion.scalars(select(Insumo).order_by(Insumo.nombre)))


def insumo_por_id(sesion: Session, insumo_id: int) -> Insumo | None:
    return sesion.get(Insumo, insumo_id)


def insumos_bajo_minimo(sesion: Session) -> list[Insumo]:
    consulta = select(Insumo).where(Insumo.existencia <= Insumo.minimo).order_by(Insumo.nombre)
    return list(sesion.scalars(consulta))


def crear_insumo(
    sesion: Session, nombre: str, unidad: str, existencia: Decimal, minimo: Decimal
) -> Insumo:
    if sesion.scalar(select(Insumo).where(Insumo.nombre == nombre)) is not None:
        raise ErrorDeInventario(f"Ya existe un insumo llamado {nombre}.")

    insumo = Insumo(nombre=nombre, unidad=unidad, existencia=existencia, minimo=minimo)
    sesion.add(insumo)
    sesion.flush()
    return insumo


def registrar_movimiento(
    sesion: Session,
    insumo_id: int,
    tipo: str,
    cantidad: Decimal,
    motivo: str,
    usuario_id: str,
) -> Insumo:
    if tipo not in TIPOS_DE_MOVIMIENTO:
        raise ErrorDeInventario(f"Tipo de movimiento invalido: {tipo}.")
    if cantidad <= 0:
        raise ErrorDeInventario("La cantidad debe ser mayor que cero.")

    insumo = sesion.get(Insumo, insumo_id)
    if insumo is None:
        raise ErrorDeInventario("Ese insumo no existe.")

    nueva_existencia = _aplicar(insumo.existencia, tipo, cantidad)
    if nueva_existencia < 0:
        raise ErrorDeInventario(
            f"No hay existencia suficiente de {insumo.nombre}: hay {insumo.existencia} y se piden {cantidad}."
        )

    insumo.existencia = nueva_existencia
    sesion.add(
        Movimiento(
            insumo_id=insumo.id,
            tipo=tipo,
            cantidad=cantidad,
            motivo=motivo,
            usuario_id=usuario_id,
        )
    )
    sesion.flush()
    return insumo


def movimientos_de(sesion: Session, insumo_id: int, limite: int = 20) -> list[Movimiento]:
    consulta = (
        select(Movimiento)
        .where(Movimiento.insumo_id == insumo_id)
        .order_by(Movimiento.creado_en.desc())
        .limit(limite)
    )
    return list(sesion.scalars(consulta))


def _aplicar(existencia: Decimal, tipo: str, cantidad: Decimal) -> Decimal:
    if tipo == "entrada":
        return existencia + cantidad
    if tipo == "salida":
        return existencia - cantidad
    return cantidad  # ajuste: la cantidad es el valor real contado en bodega
