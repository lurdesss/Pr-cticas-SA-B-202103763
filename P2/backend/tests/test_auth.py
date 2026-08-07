"""Pruebas de la lógica de seguridad.

Se ejercitan con el repositorio en memoria y un cliente de autorización
falso, sin tocar PostgreSQL ni levantar el microservicio: eso demuestra
que el servicio depende de abstracciones y no de implementaciones.
"""

import time

import pytest

from app.core.config import Settings
from app.core.crypto import cifrar, descifrar, hashear_password, indice_ciego
from app.domain.entities import Rol
from app.domain.exceptions import (
    AccesoDenegadoError,
    CorreoYaRegistradoError,
    CredencialesInvalidasError,
    NoAutenticadoError,
    ServicioAutorizacionNoDisponibleError,
)
from app.domain.repositories import ClienteAutorizacion
from app.infrastructure.memory_repository import RepositorioUsuariosMemoria
from app.services.auth_service import ServicioAutenticacion
from app.services.token_service import ResultadoToken, ServicioToken

CLAVE_PRUEBA = "clave_de_prueba_con_mas_de_treinta_y_dos_caracteres"


def construir_settings(ttl: int = 2, gracia: int = 2) -> Settings:
    """Configuración con tiempos muy cortos para no ralentizar la suite."""
    return Settings(
        database_url="postgresql+psycopg://u:p@localhost:5432/db",
        jwt_secreto=CLAVE_PRUEBA,
        jwt_ttl_segundos=ttl,
        jwt_gracia_renovacion_segundos=gracia,
        aes_clave=CLAVE_PRUEBA,
        indice_ciego_clave=CLAVE_PRUEBA + "_distinta",
    )


class AutorizacionFalsa(ClienteAutorizacion):
    """Réplica en memoria de la matriz de permisos del microservicio."""

    _PERMISOS = {
        "admin": {"ruta1:leer", "ruta2:leer"},
        "cliente": {"ruta2:leer"},
    }

    def tiene_permiso(self, rol: str, permiso: str) -> bool:
        return permiso in self._PERMISOS.get(rol, set())


class AutorizacionCaida(ClienteAutorizacion):
    """Simula el microservicio inalcanzable tras agotar los reintentos."""

    def tiene_permiso(self, rol: str, permiso: str) -> bool:
        raise ServicioAutorizacionNoDisponibleError(4)


@pytest.fixture
def servicio() -> ServicioAutenticacion:
    return ServicioAutenticacion(
        RepositorioUsuariosMemoria(),
        ServicioToken(construir_settings()),
        AutorizacionFalsa(),
    )


def registrar_admin(servicio: ServicioAutenticacion):
    return servicio.registrar(
        nombre="Ana Administradora",
        correo="admin@academia.test",
        password="ClaveSegura123",
        rol=Rol.ADMIN,
    )


# --- Cifrado ---


def test_cifrado_aes_es_reversible(monkeypatch) -> None:
    monkeypatch.setenv("AES_CLAVE", CLAVE_PRUEBA)
    monkeypatch.setenv("INDICE_CIEGO_CLAVE", CLAVE_PRUEBA)
    monkeypatch.setenv("JWT_SECRETO", CLAVE_PRUEBA)
    monkeypatch.setenv("DATABASE_URL", "postgresql+psycopg://u:p@localhost:5432/db")

    from app.core.config import get_settings

    get_settings.cache_clear()

    original = "correo@ejemplo.test"
    assert descifrar(cifrar(original)) == original


def test_cifrado_produce_texto_distinto_cada_vez(monkeypatch) -> None:
    """Dos cifrados del mismo valor no deben coincidir.

    Es lo que impide deducir que dos usuarios comparten un dato con solo
    mirar la base de datos, y la razón por la que hace falta el índice
    ciego para poder buscar.
    """
    monkeypatch.setenv("AES_CLAVE", CLAVE_PRUEBA)
    monkeypatch.setenv("INDICE_CIEGO_CLAVE", CLAVE_PRUEBA)
    monkeypatch.setenv("JWT_SECRETO", CLAVE_PRUEBA)
    monkeypatch.setenv("DATABASE_URL", "postgresql+psycopg://u:p@localhost:5432/db")

    from app.core.config import get_settings

    get_settings.cache_clear()

    assert cifrar("mismo valor") != cifrar("mismo valor")
    assert indice_ciego("Correo@Test.com") == indice_ciego("correo@test.com")


def test_password_se_hashea_y_no_se_guarda_en_claro() -> None:
    hash_generado = hashear_password("ClaveSegura123")
    assert "ClaveSegura123" not in hash_generado
    assert hash_generado.startswith("$2b$")


# --- Tokens ---


def test_token_recien_emitido_es_valido() -> None:
    servicio_token = ServicioToken(construir_settings())
    from uuid import uuid4

    usuario_id = uuid4()
    credencial = servicio_token.verificar(
        servicio_token.emitir(usuario_id, Rol.ADMIN)
    )

    assert credencial is not None
    assert credencial.resultado is ResultadoToken.VALIDO
    assert credencial.usuario_id == usuario_id


def test_token_expirado_dentro_de_gracia_es_renovable() -> None:
    """Requisito 5: expirado pero aún renovable."""
    servicio_token = ServicioToken(construir_settings(ttl=1, gracia=5))
    from uuid import uuid4

    token = servicio_token.emitir(uuid4(), Rol.CLIENTE)
    time.sleep(2)  # supera el ttl, no la gracia

    credencial = servicio_token.verificar(token)
    assert credencial is not None
    assert credencial.resultado is ResultadoToken.RENOVABLE


def test_token_fuera_de_la_ventana_de_gracia_se_rechaza() -> None:
    servicio_token = ServicioToken(construir_settings(ttl=1, gracia=1))
    from uuid import uuid4

    token = servicio_token.emitir(uuid4(), Rol.CLIENTE)
    time.sleep(3)  # supera ttl + gracia

    credencial = servicio_token.verificar(token)
    assert credencial is not None
    assert credencial.resultado is ResultadoToken.RECHAZADO


def test_token_con_firma_alterada_se_rechaza() -> None:
    """Un token manipulado no debe aceptarse ni siquiera como renovable."""
    servicio_token = ServicioToken(construir_settings())
    from uuid import uuid4

    token = servicio_token.emitir(uuid4(), Rol.CLIENTE)
    cuerpo, firma = token.rsplit(".", 1)
    alterado = f"{cuerpo}.{'a' * len(firma)}"

    assert servicio_token.verificar(alterado) is None


# --- Autenticación ---


def test_login_correcto_devuelve_sesion(servicio: ServicioAutenticacion) -> None:
    registrar_admin(servicio)
    sesion = servicio.iniciar_sesion("admin@academia.test", "ClaveSegura123")

    assert sesion.usuario.rol is Rol.ADMIN
    assert sesion.token


def test_password_incorrecto_falla(servicio: ServicioAutenticacion) -> None:
    registrar_admin(servicio)
    with pytest.raises(CredencialesInvalidasError):
        servicio.iniciar_sesion("admin@academia.test", "ClaveEquivocada")


def test_correo_inexistente_da_el_mismo_error(
    servicio: ServicioAutenticacion,
) -> None:
    """El mensaje no debe permitir enumerar correos registrados."""
    registrar_admin(servicio)

    with pytest.raises(CredencialesInvalidasError) as sin_usuario:
        servicio.iniciar_sesion("nadie@academia.test", "ClaveSegura123")
    with pytest.raises(CredencialesInvalidasError) as mal_password:
        servicio.iniciar_sesion("admin@academia.test", "Equivocada")

    assert str(sin_usuario.value) == str(mal_password.value)


def test_correo_duplicado_se_rechaza(servicio: ServicioAutenticacion) -> None:
    registrar_admin(servicio)
    with pytest.raises(CorreoYaRegistradoError):
        registrar_admin(servicio)


def test_sesion_sin_token_falla(servicio: ServicioAutenticacion) -> None:
    with pytest.raises(NoAutenticadoError):
        servicio.validar_sesion(None)


def test_sesion_renueva_token_dentro_de_gracia() -> None:
    """Comprobación de extremo a extremo de la renovación automática."""
    repositorio = RepositorioUsuariosMemoria()
    servicio = ServicioAutenticacion(
        repositorio,
        ServicioToken(construir_settings(ttl=1, gracia=5)),
        AutorizacionFalsa(),
    )
    sesion = servicio.registrar(
        nombre="Carlos Cliente",
        correo="cliente@academia.test",
        password="ClaveSegura123",
        rol=Rol.CLIENTE,
    )

    time.sleep(2)
    vigente = servicio.validar_sesion(sesion.token)

    assert vigente.token_renovado is not None
    assert vigente.token_renovado != sesion.token


# --- Autorización por rol ---


def test_admin_accede_a_ambas_rutas(servicio: ServicioAutenticacion) -> None:
    sesion = registrar_admin(servicio)
    servicio.exigir_permiso(sesion.usuario, "ruta1:leer")
    servicio.exigir_permiso(sesion.usuario, "ruta2:leer")


def test_cliente_solo_accede_a_la_ruta_compartida(
    servicio: ServicioAutenticacion,
) -> None:
    sesion = servicio.registrar(
        nombre="Carlos Cliente",
        correo="cliente@academia.test",
        password="ClaveSegura123",
        rol=Rol.CLIENTE,
    )

    servicio.exigir_permiso(sesion.usuario, "ruta2:leer")
    with pytest.raises(AccesoDenegadoError):
        servicio.exigir_permiso(sesion.usuario, "ruta1:leer")


def test_authz_caido_no_se_confunde_con_acceso_denegado() -> None:
    """Un fallo de infraestructura no debe reportarse como falta de permiso."""
    servicio = ServicioAutenticacion(
        RepositorioUsuariosMemoria(),
        ServicioToken(construir_settings()),
        AutorizacionCaida(),
    )
    sesion = registrar_admin(servicio)

    with pytest.raises(ServicioAutorizacionNoDisponibleError):
        servicio.exigir_permiso(sesion.usuario, "ruta1:leer")
