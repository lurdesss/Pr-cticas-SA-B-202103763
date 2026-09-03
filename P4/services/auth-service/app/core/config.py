"""Configuración del servicio de autenticación.

Única fuente de verdad para las variables de entorno. Los tiempos de vida
del JWT y de la ventana de renovación son configurables aquí, tal como
exige el enunciado: no hay ningún valor de tiempo escrito en el código.
"""

from functools import lru_cache

from pydantic import Field, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Variables de entorno validadas al arrancar la aplicación."""

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    # --- Base de datos ---
    database_url: str

    # --- Firma del JWT ---
    jwt_secreto: str = Field(min_length=32)
    jwt_algoritmo: str = "HS256"

    # --- Tiempos configurables (requisitos 4 y 5 del enunciado) ---
    jwt_ttl_segundos: int = Field(default=180, gt=0)
    jwt_gracia_renovacion_segundos: int = Field(default=60, gt=0)

    # --- Cifrado AES de datos sensibles ---
    aes_clave: str = Field(min_length=32)
    indice_ciego_clave: str = Field(min_length=32)

    # --- Cliente del microservicio de autorización ---
    authz_url: str = "http://127.0.0.1:8001"
    authz_max_reintentos: int = Field(default=4, ge=1)
    authz_backoff_inicial_ms: int = Field(default=200, gt=0)
    authz_backoff_factor: float = Field(default=2.0, ge=1.0)
    authz_timeout_ms: int = Field(default=1500, gt=0)

    # --- Cookie ---
    cookie_nombre: str = "acceso_token"
    cookie_secure: bool = False  # True obligatorio en producción (HTTPS)
    cookie_samesite: str = "lax"

    # --- Metadatos ---
    app_name: str = "Servicio de Autenticación"
    app_version: str = "1.0.0"
    debug: bool = False
    origenes_permitidos: str = "http://127.0.0.1:5500,http://localhost:5500"

    @field_validator("cookie_samesite")
    @classmethod
    def validar_samesite(cls, valor: str) -> str:
        """Rechaza valores que el navegador no reconoce."""
        permitidos = {"lax", "strict", "none"}
        if valor.lower() not in permitidos:
            raise ValueError(f"cookie_samesite debe ser uno de {permitidos}.")
        return valor.lower()

    @property
    def lista_origenes(self) -> list[str]:
        """Convierte la cadena de orígenes CORS en una lista."""
        return [origen.strip() for origen in self.origenes_permitidos.split(",")]


@lru_cache
def get_settings() -> Settings:
    """Devuelve la configuración cacheada (se lee del disco una sola vez)."""
    return Settings()
