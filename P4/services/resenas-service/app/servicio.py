"""Reglas de las resenas. Sin dependencias de FastAPI."""

from __future__ import annotations

from collections import Counter

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.modelos import Resena


class ResenaDuplicadaError(Exception):
    """El usuario ya opino sobre ese producto."""


def listar(sesion: Session, producto_id: str | None = None, limite: int = 100) -> list[Resena]:
    consulta = select(Resena).order_by(Resena.creado_en.desc()).limit(limite)
    if producto_id:
        consulta = consulta.where(Resena.producto_id == producto_id)
    return list(sesion.scalars(consulta))


def crear(
    sesion: Session,
    producto_id: str,
    usuario_id: str,
    usuario_nombre: str,
    calificacion: int,
    comentario: str,
) -> Resena:
    existente = sesion.scalar(
        select(Resena).where(Resena.producto_id == producto_id, Resena.usuario_id == usuario_id)
    )
    if existente is not None:
        raise ResenaDuplicadaError

    resena = Resena(
        producto_id=producto_id,
        usuario_id=usuario_id,
        usuario_nombre=usuario_nombre,
        calificacion=calificacion,
        comentario=comentario.strip(),
    )
    sesion.add(resena)
    sesion.commit()
    sesion.refresh(resena)
    return resena


def eliminar(sesion: Session, resena_id: int) -> bool:
    resena = sesion.get(Resena, resena_id)
    if resena is None:
        return False
    sesion.delete(resena)
    sesion.commit()
    return True


def resumen(sesion: Session, producto_id: str) -> dict:
    filas = list(
        sesion.execute(
            select(Resena.calificacion).where(Resena.producto_id == producto_id)
        ).scalars()
    )
    conteo = Counter(filas)
    total = len(filas)
    promedio = round(sum(filas) / total, 2) if total else 0.0

    return {
        "producto_id": producto_id,
        "total": total,
        "promedio": promedio,
        "distribucion": {estrella: conteo.get(estrella, 0) for estrella in range(1, 6)},
    }


def promedios_por_producto(sesion: Session) -> list[dict]:
    filas = sesion.execute(
        select(
            Resena.producto_id,
            func.count(Resena.id),
            func.avg(Resena.calificacion),
        ).group_by(Resena.producto_id)
    ).all()

    return [
        {"producto_id": producto_id, "total": total, "promedio": round(float(promedio), 2)}
        for producto_id, total, promedio in filas
    ]
