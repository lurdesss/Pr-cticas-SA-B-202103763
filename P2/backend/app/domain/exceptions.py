"""Errores del dominio de autenticación.

No heredan de `HTTPException`: la traducción a códigos HTTP ocurre en la
capa de API.
"""


class DominioError(Exception):
    """Base de todos los errores de negocio."""


class CorreoYaRegistradoError(DominioError):
    """Se intentó registrar un correo que ya existe."""

    def __init__(self) -> None:
        super().__init__("El correo ya se encuentra registrado.")


class CredencialesInvalidasError(DominioError):
    """Correo o contraseña incorrectos.

    El mensaje es deliberadamente ambiguo: distinguir entre 'el correo no
    existe' y 'la contraseña es incorrecta' permitiría enumerar qué
    correos están registrados (OWASP A07).
    """

    def __init__(self) -> None:
        super().__init__("Correo o contraseña incorrectos.")


class NoAutenticadoError(DominioError):
    """No se presentó un token, o el presentado ya no es recuperable."""

    def __init__(self, detalle: str = "Sesión no válida o expirada.") -> None:
        super().__init__(detalle)


class AccesoDenegadoError(DominioError):
    """El rol del usuario no tiene el permiso solicitado."""

    def __init__(self, permiso: str) -> None:
        self.permiso = permiso
        super().__init__(f"El rol no cuenta con el permiso '{permiso}'.")


class ServicioAutorizacionNoDisponibleError(DominioError):
    """El microservicio de autorización no respondió tras los reintentos."""

    def __init__(self, intentos: int) -> None:
        self.intentos = intentos
        super().__init__(
            f"El servicio de autorización no respondió tras {intentos} intentos."
        )
