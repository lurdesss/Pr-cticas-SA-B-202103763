"""Identidad inyectada por el API Gateway."""

from __future__ import annotations

from dataclasses import dataclass
from urllib.parse import unquote

from fastapi import Depends, Header, HTTPException, status


@dataclass(frozen=True)
class Identidad:
    id: str
    rol: str
    nombre: str

    @property
    def es_admin(self) -> bool:
        return self.rol == "admin"


def identidad_actual(
    x_usuario_id: str | None = Header(default=None),
    x_usuario_rol: str | None = Header(default=None),
    x_usuario_nombre: str | None = Header(default=None),
) -> Identidad:
    if not x_usuario_id:
        # Solo ocurre si alguien llega al servicio sin pasar por el gateway.
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Falta la identidad; entra por el API Gateway.",
        )

    return Identidad(
        id=x_usuario_id,
        rol=(x_usuario_rol or "").lower(),
        nombre=unquote(x_usuario_nombre) if x_usuario_nombre else "",
    )


IdentidadDep = Depends(identidad_actual)
