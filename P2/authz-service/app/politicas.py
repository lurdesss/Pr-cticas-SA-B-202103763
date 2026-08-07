"""Matriz de permisos por rol.

Este es el corazón del microservicio: la única fuente de verdad sobre
quién puede hacer qué. El backend principal no tiene copia de esta
tabla, por eso está obligado a preguntar.

Agregar una ruta o un rol nuevo se hace añadiendo una entrada aquí, sin
tocar ni redesplegar el backend.
"""

from types import MappingProxyType

# MappingProxyType hace la estructura de solo lectura en tiempo de
# ejecución: ningún módulo puede alterar los permisos por accidente.
PERMISOS_POR_ROL = MappingProxyType(
    {
        "admin": frozenset({"ruta1:leer", "ruta2:leer"}),
        "cliente": frozenset({"ruta2:leer"}),
    }
)


def rol_tiene_permiso(rol: str, permiso: str) -> bool:
    """Indica si el rol posee el permiso solicitado.

    Un rol desconocido no obtiene permisos: la política es negar por
    defecto en lugar de asumir un valor seguro.
    """
    return permiso in PERMISOS_POR_ROL.get(rol.strip().lower(), frozenset())
