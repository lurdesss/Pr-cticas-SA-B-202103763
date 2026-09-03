"""Repositorio de usuarios en memoria, usado por las pruebas.

Cumple el mismo contrato que la implementación de PostgreSQL, por lo que
el servicio funciona con cualquiera de las dos sin cambios (LSP).
"""

from uuid import UUID

from app.domain.entities import Usuario
from app.domain.repositories import RepositorioUsuarios


class RepositorioUsuariosMemoria(RepositorioUsuarios):
    """Almacena los usuarios en un diccionario en memoria."""

    def __init__(self) -> None:
        self._datos: dict[UUID, Usuario] = {}

    @staticmethod
    def _normalizar(correo: str) -> str:
        return correo.strip().lower()

    def obtener_por_correo(self, correo: str) -> Usuario | None:
        objetivo = self._normalizar(correo)
        for usuario in self._datos.values():
            if self._normalizar(usuario.correo) == objetivo:
                return usuario
        return None

    def obtener_por_id(self, usuario_id: UUID) -> Usuario | None:
        return self._datos.get(usuario_id)

    def crear(self, usuario: Usuario) -> Usuario:
        self._datos[usuario.id] = usuario
        return usuario
