"""Implementación del repositorio de usuarios sobre PostgreSQL.

Las consultas usan el lenguaje de expresiones de SQLAlchemy, que envía
los valores como parámetros ligados. No se concatena texto SQL en ningún
punto: eso elimina por diseño el riesgo de inyección SQL (OWASP A03).

El cifrado y descifrado ocurren en esta capa, de modo que el resto de la
aplicación trabaja siempre con datos en claro y nunca tiene que recordar
cifrar antes de guardar.
"""

from uuid import UUID

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.crypto import cifrar, descifrar, indice_ciego
from app.domain.entities import Rol, Usuario
from app.domain.repositories import RepositorioUsuarios
from app.infrastructure.models import UsuarioModel


def _a_entidad(fila: UsuarioModel) -> Usuario:
    """Traduce una fila del ORM a la entidad de dominio, descifrando."""
    return Usuario(
        id=fila.id,
        nombre=descifrar(fila.nombre_cifrado),
        correo=descifrar(fila.correo_cifrado),
        rol=Rol(fila.rol),
        password_hash=fila.password_hash,
    )


class RepositorioUsuariosPostgres(RepositorioUsuarios):
    """Persistencia real de usuarios con datos sensibles cifrados."""

    def __init__(self, session: Session) -> None:
        self._session = session

    def obtener_por_correo(self, correo: str) -> Usuario | None:
        sentencia = select(UsuarioModel).where(
            UsuarioModel.correo_indice == indice_ciego(correo)
        )
        fila = self._session.scalars(sentencia).first()
        return _a_entidad(fila) if fila else None

    def obtener_por_id(self, usuario_id: UUID) -> Usuario | None:
        fila = self._session.get(UsuarioModel, usuario_id)
        return _a_entidad(fila) if fila else None

    def crear(self, usuario: Usuario) -> Usuario:
        fila = UsuarioModel(
            id=usuario.id,
            nombre_cifrado=cifrar(usuario.nombre),
            correo_cifrado=cifrar(usuario.correo),
            correo_indice=indice_ciego(usuario.correo),
            password_hash=usuario.password_hash,
            rol=usuario.rol.value,
        )
        self._session.add(fila)
        self._session.commit()
        return _a_entidad(fila)
