"""Infraestructura de conexión a PostgreSQL.

Responsabilidad única: crear el engine, la fábrica de sesiones y entregar
una sesión con ciclo de vida acotado a cada request HTTP.
"""

from collections.abc import Generator

from sqlalchemy import create_engine
from sqlalchemy.orm import DeclarativeBase, Session, sessionmaker

from app.core.config import get_settings


class Base(DeclarativeBase):
    """Clase base declarativa de la que heredan todos los modelos ORM."""


_settings = get_settings()

engine = create_engine(
    _settings.database_url,
    pool_pre_ping=True,  # descarta conexiones muertas (útil en Neon/Supabase)
    echo=_settings.debug,
)

SessionFactory = sessionmaker(bind=engine, autoflush=False, expire_on_commit=False)


def get_session() -> Generator[Session, None, None]:
    """Entrega una sesión y garantiza su cierre aunque ocurra una excepción."""
    with SessionFactory() as session:
        yield session


def create_tables() -> None:
    """Crea el esquema a partir de los modelos ORM (alternativa a schema.sql)."""
    from app.infrastructure import models  # noqa: F401  (registra los modelos)

    Base.metadata.create_all(bind=engine)
