"""Endpoints de autenticación.

El token nunca se devuelve en el cuerpo de la respuesta: viaja solo en
la cookie HTTP-only que se escribe aquí.
"""

from fastapi import APIRouter, Response, status

from app.api.deps import (
    ServicioAuthDep,
    SettingsDep,
    UsuarioActualDep,
    borrar_cookie_sesion,
    escribir_cookie_sesion,
)
from app.schemas.auth import (
    LoginPeticion,
    MensajeRespuesta,
    RegistroPeticion,
    UsuarioRespuesta,
)

router = APIRouter(prefix="/auth", tags=["Autenticación"])


@router.post(
    "/registro", response_model=UsuarioRespuesta, status_code=status.HTTP_201_CREATED
)
def registrar(
    datos: RegistroPeticion,
    respuesta: Response,
    servicio: ServicioAuthDep,
    settings: SettingsDep,
) -> UsuarioRespuesta:
    """Registra un usuario nuevo y abre su sesión."""
    sesion = servicio.registrar(
        nombre=datos.nombre,
        correo=datos.correo,
        password=datos.password,
        rol=datos.rol,
    )
    escribir_cookie_sesion(respuesta, sesion.token, settings)
    return UsuarioRespuesta.model_validate(sesion.usuario)


@router.post("/login", response_model=UsuarioRespuesta)
def iniciar_sesion(
    datos: LoginPeticion,
    respuesta: Response,
    servicio: ServicioAuthDep,
    settings: SettingsDep,
) -> UsuarioRespuesta:
    """Valida credenciales y entrega la cookie de sesión."""
    sesion = servicio.iniciar_sesion(correo=datos.correo, password=datos.password)
    escribir_cookie_sesion(respuesta, sesion.token, settings)
    return UsuarioRespuesta.model_validate(sesion.usuario)


@router.get("/yo", response_model=UsuarioRespuesta)
def sesion_actual(usuario: UsuarioActualDep) -> UsuarioRespuesta:
    """Devuelve el usuario de la sesión activa.

    La página de confirmación posterior al login consume este endpoint
    para mostrar los datos sin que el token pase por JavaScript.
    """
    return UsuarioRespuesta.model_validate(usuario)


@router.post("/logout", response_model=MensajeRespuesta)
def cerrar_sesion(respuesta: Response, settings: SettingsDep) -> MensajeRespuesta:
    """Elimina la cookie de sesión."""
    borrar_cookie_sesion(respuesta, settings)
    return MensajeRespuesta(mensaje="Sesión cerrada correctamente.")
