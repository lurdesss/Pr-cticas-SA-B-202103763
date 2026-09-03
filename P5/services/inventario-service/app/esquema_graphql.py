"""API GraphQL del inventario, construida con Strawberry."""

from __future__ import annotations

from decimal import Decimal

import strawberry
from strawberry.types import Info

from app.db import abrir_sesion
from app.servicio import (
    ErrorDeInventario,
    crear_insumo,
    insumo_por_id,
    insumos_bajo_minimo,
    listar_insumos,
    movimientos_de,
    registrar_movimiento,
)


@strawberry.type(description="Materia prima que consume la cafeteria.")
class InsumoTipo:
    id: strawberry.ID
    nombre: str
    unidad: str
    existencia: float
    minimo: float
    bajo_minimo: bool
    actualizado_en: str


@strawberry.type(description="Entrada, salida o ajuste de existencia.")
class MovimientoTipo:
    id: strawberry.ID
    insumo_id: strawberry.ID
    tipo: str
    cantidad: float
    motivo: str
    usuario_id: str
    creado_en: str


def _a_insumo(modelo) -> InsumoTipo:
    return InsumoTipo(
        id=strawberry.ID(str(modelo.id)),
        nombre=modelo.nombre,
        unidad=modelo.unidad,
        existencia=float(modelo.existencia),
        minimo=float(modelo.minimo),
        bajo_minimo=modelo.existencia <= modelo.minimo,
        actualizado_en=modelo.actualizado_en.isoformat() if modelo.actualizado_en else "",
    )


def _a_movimiento(modelo) -> MovimientoTipo:
    return MovimientoTipo(
        id=strawberry.ID(str(modelo.id)),
        insumo_id=strawberry.ID(str(modelo.insumo_id)),
        tipo=modelo.tipo,
        cantidad=float(modelo.cantidad),
        motivo=modelo.motivo,
        usuario_id=modelo.usuario_id,
        creado_en=modelo.creado_en.isoformat() if modelo.creado_en else "",
    )


def _exigir_admin(info: Info) -> str:
    """El gateway ya limito la ruta a Admin; esto es defensa en profundidad."""
    contexto = info.context
    if contexto.get("rol") != "admin":
        raise ErrorDeInventario("Esta operacion requiere el rol Admin.")
    return contexto.get("usuario_id", "")


@strawberry.type
class Consulta:
    @strawberry.field(description="Todos los insumos, ordenados por nombre.")
    def insumos(self) -> list[InsumoTipo]:
        with abrir_sesion() as sesion:
            return [_a_insumo(insumo) for insumo in listar_insumos(sesion)]

    @strawberry.field(description="Un insumo por su identificador.")
    def insumo(self, id: strawberry.ID) -> InsumoTipo | None:
        with abrir_sesion() as sesion:
            modelo = insumo_por_id(sesion, int(id))
            return _a_insumo(modelo) if modelo else None

    @strawberry.field(description="Insumos que llegaron a su nivel minimo.")
    def insumos_bajo_minimo(self) -> list[InsumoTipo]:
        with abrir_sesion() as sesion:
            return [_a_insumo(insumo) for insumo in insumos_bajo_minimo(sesion)]

    @strawberry.field(description="Historial reciente de un insumo.")
    def movimientos(self, insumo_id: strawberry.ID, limite: int = 20) -> list[MovimientoTipo]:
        with abrir_sesion() as sesion:
            return [_a_movimiento(m) for m in movimientos_de(sesion, int(insumo_id), limite)]


@strawberry.type
class Mutacion:
    @strawberry.mutation(description="Registra entrada, salida o ajuste. Solo Admin.")
    def registrar_movimiento(
        self,
        info: Info,
        insumo_id: strawberry.ID,
        tipo: str,
        cantidad: float,
        motivo: str = "",
    ) -> InsumoTipo:
        usuario_id = _exigir_admin(info)
        with abrir_sesion() as sesion:
            insumo = registrar_movimiento(
                sesion,
                insumo_id=int(insumo_id),
                tipo=tipo.lower(),
                cantidad=Decimal(str(cantidad)),
                motivo=motivo,
                usuario_id=usuario_id,
            )
            return _a_insumo(insumo)

    @strawberry.mutation(description="Da de alta un insumo nuevo. Solo Admin.")
    def crear_insumo(
        self,
        info: Info,
        nombre: str,
        unidad: str = "unidad",
        existencia: float = 0.0,
        minimo: float = 0.0,
    ) -> InsumoTipo:
        _exigir_admin(info)
        with abrir_sesion() as sesion:
            insumo = crear_insumo(
                sesion,
                nombre=nombre.strip(),
                unidad=unidad,
                existencia=Decimal(str(existencia)),
                minimo=Decimal(str(minimo)),
            )
            return _a_insumo(insumo)


esquema = strawberry.Schema(query=Consulta, mutation=Mutacion)
