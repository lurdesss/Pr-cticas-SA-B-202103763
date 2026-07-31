"""Configuración de la aplicación.

Única fuente de verdad para las variables de entorno. Ningún otro módulo
lee `os.environ` directamente: así se cumple SRP y se evita filtrar
credenciales en el código fuente.
"""

from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Variables de entorno validadas al momento de arrancar la aplicación."""

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    database_url: str
    app_name: str = "API de Solicitudes Operativas"
    app_version: str = "1.0.0"
    debug: bool = False


@lru_cache
def get_settings() -> Settings:
    """Devuelve la configuración cacheada (se lee del disco una sola vez)."""
    return Settings()
