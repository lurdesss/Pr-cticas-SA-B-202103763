"""Conexion a PostgreSQL y creacion del esquema."""

from __future__ import annotations

import os
import time
from collections.abc import Iterator
from contextlib import contextmanager

from sqlalchemy import create_engine
from sqlalchemy.exc import OperationalError
from sqlalchemy.orm import DeclarativeBase, Session, sessionmaker

URL_BASE_DE_DATOS = os.getenv(
    "DATABASE_URL",
    "postgresql+psycopg://aroma:aroma@postgres:5432/inventario_db",
)

motor = create_engine(URL_BASE_DE_DATOS, pool_pre_ping=True, future=True)
SesionLocal = sessionmaker(bind=motor, autoflush=False, expire_on_commit=False)


class Base(DeclarativeBase):
    """Base declarativa de los modelos del inventario."""


@contextmanager
def abrir_sesion() -> Iterator[Session]:
    sesion = SesionLocal()
    try:
        yield sesion
        sesion.commit()
    except Exception:
        sesion.rollback()
        raise
    finally:
        sesion.close()


def esperar_base_de_datos(intentos: int = 15, espera_segundos: float = 2.0) -> None:
    """PostgreSQL puede tardar en aceptar conexiones aunque el contenedor ya exista."""
    for intento in range(1, intentos + 1):
        try:
            with motor.connect() as conexion:
                conexion.exec_driver_sql("SELECT 1")
            return
        except OperationalError as error:
            print(f"[inventario] PostgreSQL no responde (intento {intento}/{intentos}): {error}")
            time.sleep(espera_segundos)
    raise RuntimeError("PostgreSQL no respondio.")


def crear_esquema() -> None:
    Base.metadata.create_all(motor)
