"""Crea las tablas en la base de datos configurada en .env.

Uso:
    python scripts_init_db.py
"""

from app.core.database import create_tables

if __name__ == "__main__":
    create_tables()
    print("Tablas creadas correctamente.")
