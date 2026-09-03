"""Microservicio de resenas. Python + FastAPI. API REST."""

from __future__ import annotations

from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

from fastapi import Depends, FastAPI, HTTPException, Query, status
from sqlalchemy.orm import Session

from app import servicio
from app.db import crear_esquema, esperar_base_de_datos, obtener_sesion
from app.esquemas import ResenaEntrada, ResenaSalida, ResumenSalida
from app.identidad import Identidad, identidad_actual


@asynccontextmanager
async def ciclo_de_vida(_aplicacion: FastAPI) -> AsyncIterator[None]:
    esperar_base_de_datos()
    crear_esquema()
    yield


aplicacion = FastAPI(
    title="Aroma - Resenas",
    description="Opiniones de las personas sobre los productos del menu. API REST.",
    version="1.0.0",
    lifespan=ciclo_de_vida,
)

SesionDep = Depends(obtener_sesion)
IdentidadDep = Depends(identidad_actual)


@aplicacion.get("/salud", tags=["salud"])
def salud() -> dict:
    return {"servicio": "resenas-service", "estado": "arriba", "api": "REST", "lenguaje": "Python"}


@aplicacion.get("/resenas", response_model=list[ResenaSalida], tags=["resenas"])
def listar_resenas(
    producto_id: str | None = Query(default=None, max_length=40),
    sesion: Session = SesionDep,
    _identidad: Identidad = IdentidadDep,
) -> list[ResenaSalida]:
    return [ResenaSalida.model_validate(r) for r in servicio.listar(sesion, producto_id)]


@aplicacion.get("/resenas/promedios", tags=["resenas"])
def promedios(sesion: Session = SesionDep, _identidad: Identidad = IdentidadDep) -> list[dict]:
    return servicio.promedios_por_producto(sesion)


@aplicacion.get("/resenas/resumen/{producto_id}", response_model=ResumenSalida, tags=["resenas"])
def resumen_de_producto(
    producto_id: str,
    sesion: Session = SesionDep,
    _identidad: Identidad = IdentidadDep,
) -> ResumenSalida:
    return ResumenSalida(**servicio.resumen(sesion, producto_id))


@aplicacion.post(
    "/resenas",
    response_model=ResenaSalida,
    status_code=status.HTTP_201_CREATED,
    tags=["resenas"],
)
def crear_resena(
    entrada: ResenaEntrada,
    sesion: Session = SesionDep,
    identidad: Identidad = IdentidadDep,
) -> ResenaSalida:
    try:
        resena = servicio.crear(
            sesion,
            producto_id=entrada.producto_id,
            usuario_id=identidad.id,
            usuario_nombre=identidad.nombre,
            calificacion=entrada.calificacion,
            comentario=entrada.comentario,
        )
    except servicio.ResenaDuplicadaError:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Ya escribiste una resena de este producto. Borrala para escribir otra.",
        ) from None

    return ResenaSalida.model_validate(resena)


@aplicacion.delete("/resenas/{resena_id}", status_code=status.HTTP_204_NO_CONTENT, tags=["resenas"])
def eliminar_resena(
    resena_id: int,
    sesion: Session = SesionDep,
    identidad: Identidad = IdentidadDep,
) -> None:
    # Doble control: el gateway ya exigio resenas:moderar, pero el servicio
    # tampoco se fia de que siempre vaya a existir esa regla.
    if not identidad.es_admin:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Solo Admin puede moderar resenas.")

    if not servicio.eliminar(sesion, resena_id):
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Esa resena no existe.")


app = aplicacion
