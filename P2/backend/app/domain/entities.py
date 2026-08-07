"""Entidades del dominio de autenticación.

Este módulo no importa FastAPI, SQLAlchemy ni la librería de JWT: el
dominio no debe saber cómo se persiste ni cómo se transporta.
"""

from dataclasses import dataclass
from enum import StrEnum
from uuid import UUID


class Rol(StrEnum):
    """Roles del sistema. Enumerado cerrado: no se aceptan cadenas libres."""

    ADMIN = "admin"
    CLIENTE = "cliente"


@dataclass(frozen=True, slots=True)
class Usuario:
    """Usuario registrado.

    El `password_hash` nunca sale de esta capa hacia la API: los esquemas
    de respuesta no lo incluyen.
    """

    id: UUID
    nombre: str
    correo: str
    rol: Rol
    password_hash: str
