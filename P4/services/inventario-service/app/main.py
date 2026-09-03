"""Microservicio de inventario. Python + FastAPI + Strawberry (GraphQL)."""

from __future__ import annotations

import os
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from urllib.parse import unquote

from fastapi import FastAPI, Request
from strawberry.fastapi import GraphQLRouter

from app.db import abrir_sesion, crear_esquema, esperar_base_de_datos
from app.esquema_graphql import esquema
from app.semilla import sembrar


@asynccontextmanager
async def ciclo_de_vida(_aplicacion: FastAPI) -> AsyncIterator[None]:
    esperar_base_de_datos()
    crear_esquema()
    with abrir_sesion() as sesion:
        sembrar(sesion)
    yield


async def obtener_contexto(request: Request) -> dict:
    """La identidad llega en cabeceras que puso el gateway tras validarla."""
    nombre = request.headers.get("x-usuario-nombre", "")
    return {
        "request": request,
        "usuario_id": request.headers.get("x-usuario-id", ""),
        "rol": request.headers.get("x-usuario-rol", "").lower(),
        "nombre": unquote(nombre) if nombre else "",
    }


aplicacion = FastAPI(
    title="Aroma - Inventario",
    description="Existencias de insumos. API GraphQL.",
    version="1.0.0",
    lifespan=ciclo_de_vida,
)

aplicacion.include_router(GraphQLRouter(esquema, context_getter=obtener_contexto), prefix="/graphql")


@aplicacion.get("/salud", tags=["salud"])
def salud() -> dict:
    return {
        "servicio": "inventario-service",
        "estado": "arriba",
        "api": "GraphQL",
        "lenguaje": "Python",
        "puerto": int(os.getenv("PUERTO", "4002")),
    }


app = aplicacion
