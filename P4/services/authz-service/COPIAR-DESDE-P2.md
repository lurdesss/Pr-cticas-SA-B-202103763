# Como poblar esta carpeta

Aqui va el **microservicio de autorizacion de la Practica 2**, sin cambios
salvo una adicion a la matriz de permisos.

## 1. Copiar el codigo

**Windows PowerShell**

```powershell
Copy-Item -Path "P2\authz-service\app"              -Destination "P4\services\authz-service\" -Recurse -Force
Copy-Item -Path "P2\authz-service\requirements.txt" -Destination "P4\services\authz-service\" -Force
```

**Linux / macOS**

```bash
cp -r P2/authz-service/app              P4/services/authz-service/
cp    P2/authz-service/requirements.txt P4/services/authz-service/
```

## 2. Agregar los permisos de la Practica 4

Abre `app/politicas.py` y **agrega** los permisos nuevos a la matriz. No
borres los de la Practica 2: `ruta1:leer` y `ruta2:leer` siguen sirviendo
para demostrar el modulo anterior.

Este es el paso que hace visible el principio abierto/cerrado: la politica
de acceso de todo el sistema crece agregando entradas a un diccionario, sin
tocar el gateway ni ningun microservicio.

```python
PERMISOS_POR_ROL = {
    "admin": {
        # Practica 2
        "ruta1:leer",
        "ruta2:leer",
        # Practica 4
        "catalogo:usar",
        "inventario:gestionar",
        "pedidos:leer",
        "pedidos:crear",
        "pedidos:gestionar",
        "resenas:leer",
        "resenas:escribir",
        "resenas:moderar",
    },
    "cliente": {
        # Practica 2
        "ruta2:leer",
        # Practica 4
        "catalogo:usar",
        "pedidos:leer",
        "pedidos:crear",
        "resenas:leer",
        "resenas:escribir",
    },
}
```

Adapta los nombres a como este escrita tu matriz (puede ser un `dict` de
listas, un `frozenset`, etc.). Lo unico que importa es que
`POST /autorizacion/verificar` con `{"rol": "admin", "permiso": "pedidos:crear"}`
responda `{"permitido": true}`.

## 3. Comprobar

Con el sistema levantado:

```bash
curl http://localhost:8082/autorizacion/politicas
```

O, ya con sesion iniciada en el navegador, abre
<http://localhost:8080/api/diagnostico>: el gateway pregunta uno por uno
todos los permisos que declara y te dice cuales faltan.

> Si olvidas este paso, el login funciona pero todas las pantallas
> devuelven **403**. Es el error mas comun al levantar el sistema.

docker compose build authz-service gateway
docker compose up -d authz-service gateway
pwsh -ExecutionPolicy Bypass -File scripts\prueba-humo.ps1
