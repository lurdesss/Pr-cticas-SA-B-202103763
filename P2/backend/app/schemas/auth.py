"""Esquemas de entrada y salida de la API de autenticación.

Ninguna respuesta incluye el hash de contraseña ni el token: el token
viaja exclusivamente en una cookie HTTP-only (requisito 3), de modo que
el JavaScript del navegador no puede leerlo.
"""

from uuid import UUID

from pydantic import BaseModel, ConfigDict, EmailStr, Field

from app.domain.entities import Rol


class RegistroPeticion(BaseModel):
    """Cuerpo de POST /auth/registro."""

    model_config = ConfigDict(str_strip_whitespace=True, extra="forbid")

    nombre: str = Field(min_length=3, max_length=80)
    correo: EmailStr
    password: str = Field(min_length=8, max_length=72)
    rol: Rol = Rol.CLIENTE


class LoginPeticion(BaseModel):
    """Cuerpo de POST /auth/login."""

    model_config = ConfigDict(str_strip_whitespace=True, extra="forbid")

    correo: EmailStr
    password: str = Field(min_length=1, max_length=72)


class UsuarioRespuesta(BaseModel):
    """Representación pública de un usuario. Sin hash ni token."""

    model_config = ConfigDict(from_attributes=True)

    id: UUID
    nombre: str
    correo: str
    rol: Rol


class MensajeRespuesta(BaseModel):
    """Respuesta simple con un mensaje descriptivo."""

    mensaje: str


class RecursoProtegidoRespuesta(BaseModel):
    """Cuerpo devuelto por las rutas protegidas por rol."""

    mensaje: str
    permiso_requerido: str
    usuario: UsuarioRespuesta
