"""Modelo ORM de usuarios.

Las columnas `nombre` y `correo` guardan texto cifrado con AES-GCM, por
eso son `Text` y no tienen longitud acotada al dato original: el texto
cifrado en base64 es más largo que el texto plano.
"""

import uuid

from sqlalchemy import String, Text
from sqlalchemy.dialects import postgresql
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base
from app.domain.entities import Rol

ROLES_PERMITIDOS = ", ".join(f"'{rol.value}'" for rol in Rol)


class UsuarioModel(Base):
    """Representación en base de datos de un usuario."""

    __tablename__ = "usuarios"

    id: Mapped[uuid.UUID] = mapped_column(
        postgresql.UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )

    # Datos sensibles: cifrados con AES-GCM (requisito 6 del enunciado).
    nombre_cifrado: Mapped[str] = mapped_column(Text, nullable=False)
    correo_cifrado: Mapped[str] = mapped_column(Text, nullable=False)

    # Índice ciego: permite buscar por correo sin descifrar la tabla.
    correo_indice: Mapped[str] = mapped_column(
        String(64), nullable=False, unique=True, index=True
    )

    # Las contraseñas se hashean, no se cifran.
    password_hash: Mapped[str] = mapped_column(String(255), nullable=False)

    rol: Mapped[str] = mapped_column(String(20), nullable=False)
