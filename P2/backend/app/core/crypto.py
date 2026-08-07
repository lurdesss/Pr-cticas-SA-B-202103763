"""Primitivas criptográficas del sistema.

Se distinguen tres mecanismos con propósitos distintos:

1. **Cifrado AES-GCM** para datos sensibles que deben poder recuperarse
   en claro (nombre, correo). Es reversible por diseño.
2. **Índice ciego (HMAC-SHA256)** para poder *buscar* por correo sin
   descifrar toda la tabla. AES-GCM produce un texto cifrado distinto
   cada vez —lo cual es correcto y deseable—, así que no sirve para
   comparar en un `WHERE`.
3. **Hash bcrypt** para contraseñas. Una contraseña **no debe cifrarse**:
   debe ser irreversible incluso para el propio sistema.
"""

import base64
import hashlib
import hmac
import os

from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from passlib.context import CryptContext

from app.core.config import get_settings

_TAMANO_NONCE = 12  # 96 bits, el tamaño recomendado para AES-GCM
_LIMITE_BCRYPT_BYTES = 72  # bcrypt trunca silenciosamente más allá de esto

_contexto_password = CryptContext(schemes=["bcrypt"], deprecated="auto")


def _derivar_clave(material: str) -> bytes:
    """Deriva una clave AES de 256 bits a partir del texto del entorno.

    Se usa SHA-256 para garantizar la longitud exacta que exige AES-256
    sin importar qué escriba el operador en el archivo `.env`.
    """
    return hashlib.sha256(material.encode("utf-8")).digest()


def cifrar(texto_plano: str) -> str:
    """Cifra un valor con AES-256-GCM y lo devuelve en base64.

    GCM es un modo autenticado: si alguien modifica un byte del registro
    directamente en la base de datos, el descifrado falla en lugar de
    devolver basura silenciosamente.

    El nonce se genera al azar en cada llamada y se antepone al texto
    cifrado, porque reutilizar un nonce con la misma clave rompe por
    completo la seguridad de GCM.
    """
    clave = _derivar_clave(get_settings().aes_clave)
    nonce = os.urandom(_TAMANO_NONCE)
    cifrado = AESGCM(clave).encrypt(nonce, texto_plano.encode("utf-8"), None)
    return base64.b64encode(nonce + cifrado).decode("ascii")


def descifrar(texto_cifrado: str) -> str:
    """Revierte `cifrar`. Lanza excepción si el dato fue manipulado."""
    clave = _derivar_clave(get_settings().aes_clave)
    crudo = base64.b64decode(texto_cifrado.encode("ascii"))
    nonce, cifrado = crudo[:_TAMANO_NONCE], crudo[_TAMANO_NONCE:]
    return AESGCM(clave).decrypt(nonce, cifrado, None).decode("utf-8")


def indice_ciego(valor: str) -> str:
    """Genera un identificador determinista para poder buscar por correo.

    Es un HMAC con clave propia, no un hash simple: sin la clave, quien
    obtenga la base de datos no puede confirmar si un correo concreto
    está registrado probando candidatos.

    El valor se normaliza a minúsculas para que el correo sea
    insensible a mayúsculas, como esperan los usuarios.
    """
    clave = _derivar_clave(get_settings().indice_ciego_clave)
    normalizado = valor.strip().lower().encode("utf-8")
    return hmac.new(clave, normalizado, hashlib.sha256).hexdigest()


def hashear_password(password: str) -> str:
    """Deriva el hash bcrypt de una contraseña."""
    return _contexto_password.hash(_truncar_para_bcrypt(password))


def verificar_password(password: str, hash_almacenado: str) -> bool:
    """Compara una contraseña con su hash en tiempo constante."""
    return _contexto_password.verify(
        _truncar_para_bcrypt(password), hash_almacenado
    )


def _truncar_para_bcrypt(password: str) -> bytes:
    """Acota la contraseña al límite real del algoritmo.

    bcrypt ignora todo lo que exceda 72 bytes. Truncar explícitamente
    evita que la librería lance una excepción y deja el comportamiento
    documentado en lugar de implícito.
    """
    return password.encode("utf-8")[:_LIMITE_BCRYPT_BYTES]
