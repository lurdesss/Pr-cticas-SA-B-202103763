"""Identidad recibida en cabeceras.

Nota de alcance (Practica 5): el gateway de esta practica es un
"simulador" sin verificacion de sesion (ver services/gateway). Estas
cabeceras viajan sin firmar y sin exigirse: si faltan, se asume un
visitante anonimo con rol "cliente" en vez de rechazar la peticion. Sirve
para probar el enrutado por rol (por ejemplo moderar una resena con
X-Usuario-Rol: admin), pero no es un mecanismo de seguridad. La
verificacion real vive en la Practica 4 (auth-service + authz-service).
"""

from __future__ import annotations

from dataclasses import dataclass
from urllib.parse import unquote

from fastapi import Depends, Header


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
    return Identidad(
        id=x_usuario_id or "anonimo",
        rol=(x_usuario_rol or "cliente").lower(),
        nombre=unquote(x_usuario_nombre) if x_usuario_nombre else "Invitado",
    )


IdentidadDep = Depends(identidad_actual)
