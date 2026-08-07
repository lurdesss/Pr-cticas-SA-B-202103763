"""Rutas protegidas por rol (requisito 8 del enunciado).

| Ruta                  | Permiso requerido | Admin | Cliente |
|-----------------------|-------------------|-------|---------|
| /recursos/ruta1       | ruta1:leer        | Sí    | No      |
| /recursos/ruta2       | ruta2:leer        | Sí    | Sí      |

El endpoint no sabe qué roles existen ni qué permisos tiene cada uno:
solo declara el permiso que necesita. Quién lo posee lo decide el
microservicio de autorización.
"""

from typing import Annotated

from fastapi import APIRouter, Depends

from app.api.deps import exigir_permiso
from app.domain.entities import Usuario
from app.schemas.auth import RecursoProtegidoRespuesta, UsuarioRespuesta

router = APIRouter(prefix="/recursos", tags=["Rutas protegidas"])

PERMISO_RUTA1 = "ruta1:leer"
PERMISO_RUTA2 = "ruta2:leer"


@router.get("/ruta1", response_model=RecursoProtegidoRespuesta)
def ruta_solo_admin(
    usuario: Annotated[Usuario, Depends(exigir_permiso(PERMISO_RUTA1))],
) -> RecursoProtegidoRespuesta:
    """Ruta 1: exclusiva del rol Admin."""
    return RecursoProtegidoRespuesta(
        mensaje="Acceso concedido al panel administrativo.",
        permiso_requerido=PERMISO_RUTA1,
        usuario=UsuarioRespuesta.model_validate(usuario),
    )


@router.get("/ruta2", response_model=RecursoProtegidoRespuesta)
def ruta_compartida(
    usuario: Annotated[Usuario, Depends(exigir_permiso(PERMISO_RUTA2))],
) -> RecursoProtegidoRespuesta:
    """Ruta 2: accesible por Admin y por Cliente."""
    return RecursoProtegidoRespuesta(
        mensaje="Acceso concedido al área compartida.",
        permiso_requerido=PERMISO_RUTA2,
        usuario=UsuarioRespuesta.model_validate(usuario),
    )
