# Diseño de Arquitectura — Sistema de Transacciones Bancarias en Lote

Práctica 3: Software Avanzado, Segundo Semestre 2026
Universidad de San Carlos de Guatemala · Facultad de Ingeniería · Ingeniería en Ciencias y Sistemas

Diseño de la solución que reemplaza el sistema monolítico de procesamiento de transacciones por una arquitectura de microservicios con API Gateway, carga y validación de archivos CSV, flujo de aprobación de tres pasos, envío a un core bancario externo, notificación a los clientes y logging centralizado auditable.

> **Esta práctica es de diseño.** No se desarrolla código en ningún momento. El módulo de autenticación de la Práctica 2 se **referencia y se integra**, no se vuelve a implementar. Las tecnologías se declaran únicamente en la sección de requerimientos técnicos; los diagramas de arquitectura no llevan tecnologías ni íconos.

---

## Índice

1. [Problema](#1-problema)
2. [Cumplimiento del alcance](#2-cumplimiento-del-alcance)
3. [Diagrama de arquitectura general](#3-diagrama-de-arquitectura-general)
4. [Diseño de microservicios](#4-diseño-de-microservicios)
5. [Integración con la Práctica 2](#5-integración-con-la-práctica-2)
6. [Reglas de validación del negocio](#6-reglas-de-validación-del-negocio)
7. [Flujo de aprobación de tres pasos](#7-flujo-de-aprobación-de-tres-pasos)
8. [Almacenamiento de los archivos CSV](#8-almacenamiento-de-los-archivos-csv)
9. [Historial consultable y notificación a clientes](#9-historial-consultable-y-notificación-a-clientes)
10. [Logging centralizado](#10-logging-centralizado)
11. [Comunicación entre servicios](#11-comunicación-entre-servicios)
12. [Propuesta de API Gateway](#12-propuesta-de-api-gateway)
13. [Requerimientos técnicos](#13-requerimientos-técnicos)
14. [Patrones de diseño](#14-patrones-de-diseño)
15. [Explicación de cada diagrama](#15-explicación-de-cada-diagrama)
16. [Principios SOLID en el diseño](#16-principios-solid-en-el-diseño)
17. [Autor](#17-autor)

---

## 1. Problema

El sistema actual procesa las transacciones bajo un esquema monolítico: la carga de archivos, la validación, la aprobación, el envío al core y el envío de correos comparten un mismo proceso, una misma base de datos y un mismo despliegue. En los picos de demanda —cierre de mes, planillas corporativas, temporada de impuestos— todo se degrada al mismo tiempo.

El problema de fondo es el acoplamiento: no se puede escalar la parte que sufre sin escalar el resto, ni corregir una regla de validación sin volver a desplegar el sistema completo.

**Objetivo del diseño.** Separar el sistema en servicios autónomos, desplegables y escalables por separado, sin perder los controles que exige una operación bancaria: tres aprobaciones humanas, trazabilidad completa y ningún envío duplicado al core.

---

## 2. Cumplimiento del alcance

Los doce elementos que pide la sección 3.2 del enunciado:

| # | Elemento solicitado | Dónde está |
|---|---|---|
| 1 | Diagrama de Arquitectura General | `diagramas/01-arquitectura-general.drawio` · secciones 3 y 15 |
| 2 | Uso e integración del servicio de autenticación de la Práctica 2 | Sección 5 · `diagramas/05` hoja *Sec 1* |
| 3 | Diseño de microservicios (mínimo 3) con separación de responsabilidades | Sección 4 (cinco microservicios propios) |
| 4 | Diagrama ER por cada microservicio | `diagramas/03-modelos-er.drawio` (6 hojas) |
| 5 | Diagrama de clases UML por cada microservicio | `diagramas/04-diagramas-clases.drawio` (6 hojas) |
| 6 | Diagramas de secuencia de los flujos críticos | `diagramas/05-diagramas-secuencia.drawio` (5 hojas) |
| 7 | Diagrama de componentes UML | `diagramas/02-diagrama-componentes.drawio` |
| 8 | Definición y documentación del flujo de aprobación de 3 pasos | Sección 7 |
| 9 | Estrategia de almacenamiento de archivos CSV | Sección 8 |
| 10 | Estrategia de logging centralizado | Sección 10 |
| 11 | Explicación de la comunicación entre servicios | Sección 11 |
| 12 | Propuesta de API Gateway | Sección 12 |

Requerimientos técnicos de la sección 3.3: arquitectura con API Gateway (sección 12), OAuth corporativo de 12 h más el módulo de la Práctica 2 (sección 5), una base de datos por microservicio (sección 4), almacenamiento de archivos (sección 8), logging centralizado (sección 10), comunicación REST y mensajería (sección 11), documentación UML (diagramas) y modelado en Draw.io.

**Docker y Kubernetes.** El enunciado los declara opcionales. **No se incluyen** en este diseño ni se dibuja un diagrama de despliegue, porque ninguno de los doce elementos del alcance lo pide y agregar una caja de Kubernetes a un diagrama de arquitectura general sería mezclar la vista del negocio con la de infraestructura. Las tecnologías quedan declaradas en la sección 13, que es donde el enunciado las pide.

---

## 3. Diagrama de arquitectura general

**Archivo:** `diagramas/01-arquitectura-general.drawio`

Modela el negocio y los requerimientos: qué hace cada parte del sistema y cómo se comunican entre sí. No incluye tecnologías, íconos ni infraestructura.

```text
Portal Web Corporativo  ──►  API Gateway  ──►  ms-lotes · ms-aprobaciones · ms-transacciones
   maker · checker             │                        │
   authorizer · auditor        ▼                        ▼
                        ms-autenticacion (P2)      Bus de eventos
                        ms-autorizacion (P2)             │
                               │                         ▼
                        OAuth Corporativo        ms-notificaciones · ms-bitacora
```

La explicación bloque por bloque está en la sección 15.

---

## 4. Diseño de microservicios

Cinco microservicios propios, más los dos que aporta la Práctica 2. Cada uno tiene su base de datos independiente y nadie consulta la base de otro.

| Microservicio | Responsabilidad | Lo que **no** hace | Base de datos |
|---|---|---|---|
| **ms-lotes** | Recibe el CSV, lo guarda, lo interpreta, aplica las reglas de validación y expone el historial y las descargas. | No aprueba, no envía al core, no decide permisos. | `lotes_db` |
| **ms-aprobaciones** | Conduce el flujo maker–checker–authorizer y custodia la segregación de funciones. | No valida el contenido del lote ni lo envía al core. | `aprobaciones_db` |
| **ms-transacciones** | Envía el lote aprobado al core bancario con idempotencia y reintentos, y concilia la respuesta. | No decide si el lote debía enviarse. | `transacciones_db` |
| **ms-notificaciones** | Envía el correo a cada beneficiario del lote aprobado y da seguimiento a la entrega. | No conoce el flujo de aprobación. | `notificaciones_db` |
| **ms-bitacora** | Recibe y conserva de forma inalterable todo evento auditable, y permite consultarlo. | No participa en ninguna decisión de negocio. | `bitacora_db` |
| **ms-autenticacion** (P2) | Autentica al usuario, emite y renueva la sesión, integra el OAuth corporativo. | No decide qué puede hacer cada rol. | `autenticacion_db` |
| **ms-autorizacion** (P2) | Responde si un rol tiene un permiso. | No conoce usuarios, lotes ni transacciones. | `autorizacion_db` |

### Criterio de separación

Los límites se trazaron por **capacidad de negocio** y **ritmo de cambio**, no por capa técnica. La pregunta guía fue: *¿qué motivo distinto obligaría a modificar esto?*

- La **aprobación** cambia cuando cambian las políticas internas de control; la **validación de archivos** cambia cuando cambia el formato de carga. Son motivos distintos, por lo tanto servicios distintos.
- El **envío al core** depende de un tercero con formato, certificados y ventanas horarias propias. Aislarlo evita que un cambio del core toque el resto del sistema.
- La **notificación** puede tardar minutos sin ningún daño; la **aprobación** no puede esperar a que se envíen 1 200 correos. Separarlos permite que cada uno vaya a su ritmo.

### Por qué no se separó más

Se consideró separar el historial y la consulta en un sexto microservicio. Se descartó: el historial se alimenta del mismo modelo de datos que ms-lotes ya posee, y un servicio adicional agregaría sincronización sin resolver ningún problema real de este alcance.

---

## 5. Integración con la Práctica 2

**Diagrama:** `diagramas/05-diagramas-secuencia.drawio`, hoja *Sec 1*.
**Referencia:** el módulo está documentado en el `README.md` de la Práctica 2, incluido en los artefactos del proyecto.

### 5.1 Dos identidades complementarias

El enunciado pide un OAuth corporativo con token de 12 horas **complementado** con el módulo de la Práctica 2. Resuelven cosas distintas:

| | OAuth corporativo | Módulo de la Práctica 2 |
|---|---|---|
| Qué acredita | Que quien pide es un empleado vigente | Que **esta** sesión sigue siendo válida |
| Vida | 12 horas | 3 minutos + 1 minuto de ventana de gracia |
| Dónde vive | Directorio corporativo (externo) | `ms-autenticacion`, en cookie HTTP-only |
| Cuándo se revoca | Al dar de baja al empleado | Ante cualquier anomalía de la sesión |

Un token de 12 horas como credencial única es cómodo y riesgoso: si se intercepta en la mañana, sirve hasta la noche. La sesión corta de la Práctica 2 acota esa ventana a minutos, y como se renueva sola dentro de la ventana de gracia, el operador nunca lo nota.

### 5.2 Recorrido de una petición

1. El operador se autentica una vez contra el OAuth corporativo y obtiene el token de 12 horas.
2. `ms-autenticacion` valida ese token, ubica al usuario y emite su propia sesión: JWT firmado en **cookie HTTP-only**, con `max_age = ttl + gracia`, tal como se construyó en la Práctica 2.
3. El **API Gateway** delega en `ms-autenticacion` la validación de cada petición. Si la sesión está expirada pero dentro de la ventana de gracia, se renueva y se devuelve la cookie nueva.
4. El Gateway propaga `X-Usuario`, `X-Rol` y `X-Correlacion` al microservicio destino.
5. El microservicio, antes de ejecutar, pregunta a `ms-autorizacion` si ese rol tiene el permiso requerido. Ningún servicio guarda copia de la matriz de permisos.

### 5.3 Qué se conserva de la Práctica 2

| Mecanismo de la P2 | Uso en la P3 |
|---|---|
| JWT en cookie HTTP-only | Sesión del portal; el token nunca es legible por JavaScript |
| Renovación dentro de la ventana de gracia | Evita cortar al operador a mitad de una carga de miles de registros |
| Cifrado AES-256-GCM con índice ciego | Correos de beneficiarios en `ms-notificaciones` y de usuarios en `ms-autenticacion` |
| Cliente de autorización con reintentos y backoff | Reutilizado por `ms-lotes`, `ms-aprobaciones` y `ms-bitacora` |
| Distinción 403 / 503 | Se mantiene: un servicio caído nunca se reporta como falta de permisos |

### 5.4 Matriz de permisos del nuevo dominio

Vive en `ms-autorizacion` y crece agregando filas, sin tocar ningún otro servicio.

| Permiso | MAKER | CHECKER | AUTHORIZER | AUDITOR | ADMIN |
|---|:--:|:--:|:--:|:--:|:--:|
| `lote:cargar` | ✔ | | | | ✔ |
| `lote:leer` | ✔ | ✔ | ✔ | ✔ | ✔ |
| `lote:descargar` | ✔ | ✔ | ✔ | ✔ | ✔ |
| `aprobacion:registrar` | ✔ | | | | |
| `aprobacion:verificar` | | ✔ | | | |
| `aprobacion:autorizar` | | | ✔ | | |
| `transaccion:reprocesar` | | | | | ✔ |
| `bitacora:consultar` | | | | ✔ | ✔ |

Ningún rol acumula dos permisos del circuito de aprobación: eso es lo que hace posible la segregación de funciones.

---

## 6. Reglas de validación del negocio

Se aplican en `ms-lotes` antes de que el lote pueda entrar al flujo de aprobación.

| # | Regla | Fuente del dato | Si falla |
|---|---|---|---|
| R1 | Formato del archivo: extensión, codificación, cabecera y tamaño máximo | El propio archivo | Rechazo inmediato, no se crea el lote |
| R2 | Cuenta destino existente y activa | Consulta al core bancario | Error bloqueante en la línea |
| R3 | Cuenta origen pertenece a la empresa que carga el lote | Core bancario + identidad | Error bloqueante |
| R4 | Saldo disponible ≥ suma del lote | Core bancario | El lote no es aprobable |
| R5 | Límite por transacción y límite diario acumulado | Parámetros del producto | Error bloqueante en la línea |
| R6 | Sin registros duplicados dentro del mismo lote | El propio lote | Advertencia o bloqueo, según parámetro |
| R7 | Prevención de fraude: listas restringidas, montos inusuales, cuentas de alta reciente | Reglas configurables de `ms-lotes` | Bloqueo del lote o marca de revisión obligatoria en el paso 2 |

Un lote con errores **no se descarta**: queda con estado `RECHAZADO` y el detalle de cada hallazgo por número de línea, para que el operador sepa qué corregir. Lo contrario obligaría a adivinar por qué falló un archivo de miles de registros.

---

## 7. Flujo de aprobación de tres pasos

**Diagrama:** `diagramas/05-diagramas-secuencia.drawio`, hoja *Sec 3*.

### 7.1 Esquema maker–checker–authorizer

| Paso | Rol | Qué hace | Permiso |
|---|---|---|---|
| 1 · Registro | **Maker** | Carga el lote, revisa el resultado de la validación y lo somete | `aprobacion:registrar` |
| 2 · Verificación | **Checker** | Contrasta el contenido contra el respaldo del cliente y confirma los datos | `aprobacion:verificar` |
| 3 · Autorización | **Authorizer** | Autoriza el desembolso; su decisión libera el lote hacia el core | `aprobacion:autorizar` |

### 7.2 Estados del flujo

```text
                     ┌────────────► RECHAZADO (final)
                     │
  VALIDADO ──► PENDIENTE_PASO_2 ──► PENDIENTE_PASO_3 ──► APROBADO ──► ENVIADO
   (paso 1)          │ (paso 2)          │ (paso 3)
                     └──────► DEVUELTO ──┘        VENCIDO: nadie decidió a tiempo
```

### 7.3 Reglas del circuito

1. **Segregación de funciones.** Un mismo usuario no puede resolver dos pasos del mismo flujo. Se valida en la entidad `FlujoAprobacion` y además con una restricción única en la base: si la capa de aplicación fallara, la base rechaza igual. El intento devuelve `409` y queda en la bitácora.
2. **El rol no basta.** Cada paso exige un permiso concreto, otorgado por `ms-autorizacion`.
3. **Rechazo.** En cualquier paso detiene el flujo con motivo obligatorio; no se envía nada al core.
4. **Devolución.** El checker puede devolver el lote al maker para corregirlo. El lote corregido abre un flujo **nuevo**: el anterior nunca se reabre, para que el rastro de auditoría no se pueda reescribir.
5. **Vencimiento.** Cada paso tiene fecha límite. Vencido el plazo el flujo pasa a `VENCIDO` y hay que someterlo de nuevo, para que no se apruebe un lote con información de hace dos semanas.
6. **Política por monto.** Montos mayores pueden exigir más pasos o un autorizador de nivel superior; se ajusta cambiando la fila de `politica_aprobacion`.
7. **Todo se asienta.** Cada decisión guarda usuario, rol, resultado, comentario, IP y marca de tiempo.
8. **Un solo disparador.** El evento `LoteAprobado` se publica únicamente al cerrarse el paso 3, en la misma transacción que el cambio de estado: o se aprueba y se publica, o no ocurre ninguna de las dos cosas.

---

## 8. Almacenamiento de los archivos CSV

Los archivos van a un **almacenamiento de objetos** (nube) o a un **servidor SFTP institucional**, nunca dentro de la base de datos: un CSV de planilla puede pesar decenas de megabytes, e incrustarlo infla las copias de respaldo, degrada las consultas y complica la descarga.

```text
/{idEmpresa}/{año}/{mes}/{idLote}/
├── original.csv     tal como lo subió el operador, inmutable
├── resultado.csv    con el estado y el código de respuesta por línea
└── comprobante.pdf  generado al completarse el envío al core
```

| Control | Decisión |
|---|---|
| Cifrado | En reposo con llave administrada por el banco; en tránsito, siempre sobre canal cifrado |
| Versionado | Activado: ningún archivo se sobrescribe ni se pierde por error |
| Inmutabilidad | `original.csv` no se puede modificar: es la evidencia de lo que el cliente pidió |
| Integridad | Hash SHA-256 calculado al subir y verificado al descargar |
| Análisis previo | El archivo se revisa antes de procesarlo; viene de fuera del sistema |
| Acceso | Nunca público. La descarga se sirve con un **enlace temporal de 5 minutos** emitido por `ms-lotes` |
| Retención | 90 días en línea y archivado frío por 7 años |
| Auditoría | Toda subida y toda descarga generan un evento auditable |

La base de datos guarda solamente la ruta y el hash del archivo. El acceso pasa por la interfaz `AlmacenArchivos`, así que cambiar de nube a SFTP es escribir otro adaptador y no tocar el dominio.

---

## 9. Historial consultable y notificación a clientes

### 9.1 Historial

`ms-lotes` expone el historial de todos los lotes procesados: búsqueda por rango de fechas, estado, empresa y monto; detalle del lote con el resultado de cada transacción; y descarga del CSV original, del CSV de resultado y del comprobante. Las cuentas se muestran enmascaradas y toda consulta y descarga queda registrada.

### 9.2 Notificación

`ms-notificaciones` consume `LoteAprobado` y envía un correo a cada beneficiario informando que su transacción está **en proceso**.

| Aspecto | Decisión |
|---|---|
| Disparador | El evento `LoteAprobado`, nunca una llamada directa desde `ms-aprobaciones` |
| Datos del beneficiario | Se consultan a `ms-lotes` por REST; el evento no transporta correos ni montos individuales |
| Idempotencia | Si el evento llega dos veces, el segundo se descarta sin enviar nada |
| Contenido | Referencia, monto y fecha estimada; el asunto no revela datos sensibles |
| Precisión | Dice «en proceso», no «acreditada»: la acreditación depende del core |
| Volumen | Envío por bloques con control de tasa |
| Fallo de entrega | No revierte nada: el dinero ya se envió. Un rebote permanente marca al destinatario y alerta al operador |

Esa última fila explica por qué la notificación es asíncrona: si el correo fuera parte de la transacción de aprobación, una caída del proveedor bloquearía la operación bancaria.

---

## 10. Logging centralizado

El diseño separa dos cosas que suelen confundirse:

| | Log técnico | Bitácora de auditoría (`ms-bitacora`) |
|---|---|---|
| Para qué | Diagnosticar fallos | Responder «quién hizo qué y cuándo» ante un auditor |
| Formato | Texto estructurado a la salida estándar | Registro relacional con esquema fijo |
| Destino | Agregador central de logs | `bitacora_db` |
| Retención | 30 días | 7 años |
| Se puede borrar | Sí, rota por índices | **No**: solo inserción, encadenado por hash |

Confundirlos deja la evidencia regulatoria a merced de una rotación de índices.

**Trazabilidad.** El API Gateway genera un `X-Correlacion` por petición que viaja en toda llamada REST, en toda cabecera de evento y en todo registro. Con un solo valor se reconstruye la historia completa de un lote: carga, validación, las tres decisiones, los intentos contra el core y los correos enviados.

**Integridad.** Cada evento guarda `hash_actual = SHA-256(hash_previo + contenido)`. Si alguien borra o edita una fila, la cadena se rompe y el verificador lo detecta. Eso convierte la bitácora en evidencia y no en un simple registro de texto.

**Qué se registra:** autenticación, decisión de permiso, carga de archivo, resultado de validación, cada decisión de aprobación, cada intento contra el core con su latencia, envío de notificaciones, consultas y descargas.
**Qué nunca se registra:** contraseñas, tokens completos, números de cuenta completos ni el contenido íntegro de un CSV.

---

## 11. Comunicación entre servicios

Regla de decisión: **si quien llama necesita la respuesta para continuar, es REST; si no, es evento.**

| Interacción | Tipo | Por qué |
|---|---|---|
| API Gateway → cualquier microservicio | REST | El usuario está esperando la respuesta |
| Cualquier servicio → `ms-autorizacion` | REST con reintentos y backoff | Sin veredicto no se puede ejecutar la acción |
| `ms-lotes` → core bancario | REST | El saldo decide si el lote es válido |
| `ms-transacciones` → core bancario | REST | Es el contrato del tercero |
| `ms-notificaciones` → `ms-lotes` | REST | Necesita la lista de beneficiarios para enviar |
| `ms-aprobaciones` → `ms-transacciones` | **Evento** `LoteAprobado` | El autorizador no debe esperar a que responda el core |
| `ms-aprobaciones` → `ms-notificaciones` | **Evento** `LoteAprobado` | Miles de correos no pueden bloquear una aprobación |
| Todos → `ms-bitacora` | **Evento** | El registro no debe frenar la operación |

### Catálogo de eventos

| Evento | Publica | Consumen |
|---|---|---|
| `LoteValidado` | `ms-lotes` | `ms-bitacora` |
| `LoteAprobado` | `ms-aprobaciones` | `ms-transacciones`, `ms-notificaciones`, `ms-bitacora` |
| `LoteRechazado` | `ms-lotes` / `ms-aprobaciones` | `ms-bitacora` |
| `TransaccionEnviada` | `ms-transacciones` | `ms-lotes` (historial), `ms-bitacora` |
| `NotificacionEnviada` | `ms-notificaciones` | `ms-bitacora` |

### Garantías

| Riesgo | Mecanismo |
|---|---|
| Se cambia el estado pero el evento se pierde | Tabla de eventos salientes escrita en la misma transacción, publicada después |
| El evento llega dos veces | Cada consumidor guarda la clave del evento procesado |
| El consumidor falla siempre | Cola de mensajes fallidos con alerta; nunca se descarta en silencio |
| Se envía dos veces al core | Clave de idempotencia derivada del lote, que el core reconoce |
| El orden importa | Partición por identificador de lote: sus eventos se procesan en orden |

---

## 12. Propuesta de API Gateway

Punto único de entrada. Ningún microservicio se expone directamente.

| Función | Detalle |
|---|---|
| Enrutamiento | `/api/lotes/*` → `ms-lotes`, `/api/aprobaciones/*` → `ms-aprobaciones`, etc. |
| Terminación de TLS | Certificado institucional; todo el tráfico externo va cifrado |
| Validación de identidad | Verifica la firma y vigencia del token corporativo y delega la sesión en `ms-autenticacion` |
| Propagación de contexto | Inyecta `X-Usuario`, `X-Rol` y `X-Correlacion` |
| Límite de uso | Por usuario y por empresa; protege ante cargas masivas accidentales |
| Tamaño de carga | Tope al archivo de subida antes de que llegue al servicio |
| Resiliencia | Tiempo de espera, corte de circuito y reintento solo en operaciones idempotentes |
| Versionado | Prefijo `/v1`, para permitir la convivencia de dos versiones durante una migración |
| Observabilidad | Toda petición genera métrica, traza y registro con el mismo identificador de correlación |

**Lo que el Gateway no hace:** decidir permisos. Verifica que la sesión sea válida, pero si un rol puede ejecutar una acción concreta lo responde `ms-autorizacion`, consultado por el servicio dueño de esa acción. Concentrar los permisos en el Gateway crearía un segundo lugar donde vive la política, con el riesgo de que las dos versiones se desincronicen.

**Rutas expuestas**

| Servicio | Rutas principales |
|---|---|
| `ms-lotes` | `POST /lotes` · `GET /lotes` · `GET /lotes/{id}` · `GET /lotes/{id}/hallazgos` · `GET /lotes/{id}/descarga` · `GET /historial` |
| `ms-aprobaciones` | `POST /flujos` · `GET /flujos` · `GET /flujos/{id}` · `POST /flujos/{id}/decisiones` |
| `ms-transacciones` | `GET /envios/{idLote}` · `POST /envios/{idLote}/reprocesar` |
| `ms-notificaciones` | `GET /notificaciones/{idLote}` |
| `ms-bitacora` | `GET /bitacora/eventos` · `GET /bitacora/integridad` |
| `ms-autenticacion` (P2) | `GET /auth/oauth/inicio` · `POST /auth/validar-sesion` · `GET /auth/yo` · `POST /auth/logout` |
| `ms-autorizacion` (P2) | `POST /autorizacion/verificar` · `GET /autorizacion/politicas` |

---

## 13. Requerimientos técnicos

Declaración de las tecnologías con que se construiría la solución. **No hay desarrollo en esta práctica**; esta tabla existe porque la sección 3.3 del enunciado la pide.

| Componente | Tecnología propuesta | Justificación |
|---|---|---|
| Lenguaje y framework | Python 3.11 + FastAPI | Continuidad con las prácticas 1 y 2; inyección de dependencias y documentación automática |
| API Gateway | Kong Gateway | Enrutamiento, validación de token, límite de uso y correlación por configuración, sin atarse a un proveedor de nube |
| Identidad corporativa | Keycloak (OAuth 2.0 / OIDC) | Estándar, autohospedable, vida de token configurable a 12 horas |
| Autenticación de sesión | Módulo de la Práctica 2 (JWT en cookie HTTP-only) | Ya construido y probado |
| Base de datos | PostgreSQL, una por microservicio | Transaccional y con particionado para la bitácora |
| Mensajería asíncrona | RabbitMQ | Suficiente para el volumen del caso, más simple de operar que Kafka; el diseño no depende del producto |
| Almacenamiento de archivos | Almacenamiento de objetos en nube (AWS S3) o servidor SFTP institucional | Versionado, inmutabilidad y enlaces temporales |
| Logs técnicos | Agregador central de logs | Consulta por identificador de correlación |
| Cifrado de datos sensibles | AES-256-GCM e índice ciego HMAC-SHA256 (Práctica 2) | Recuperable donde debe serlo, buscable sin descifrar la tabla |
| Contraseñas | bcrypt (Práctica 2) | Irreversible incluso para el propio sistema |
| Modelado | Draw.io (archivos `.drawio`) | Formato editable y versionable en el repositorio |
| Docker / Kubernetes | **No incluidos** | Opcionales según el enunciado y no requeridos por ningún elemento del alcance |

---

## 14. Patrones de diseño

| Patrón | Dónde | Problema que resuelve |
|---|---|---|
| API Gateway | Entrada del sistema | Un solo punto de exposición, seguridad y correlación |
| Base de datos por servicio | Los siete servicios | Elimina el acoplamiento por esquema compartido |
| Puertos y adaptadores | Todos los servicios | El dominio no conoce HTTP, SQL ni el proveedor de almacenamiento |
| Eventos salientes en la misma transacción | `ms-lotes`, `ms-aprobaciones`, `ms-transacciones` | Cambio de estado y publicación: ambos o ninguno |
| Idempotencia por clave | `ms-transacciones`, `ms-notificaciones` | Evita el pago doble y el correo duplicado |
| Reintentos con espera creciente | Autorización, core bancario, correo | Absorbe fallos transitorios sin saturar al destino |
| Corte de circuito | `ms-transacciones` → core | Deja de golpear a un servicio caído |
| Cola de mensajes fallidos | Todos los consumidores | Ningún mensaje se pierde en silencio |
| Máquina de estados | `ms-aprobaciones` | Transiciones válidas explícitas |
| Publicador–suscriptor | Bus de eventos | Agregar un consumidor no toca al productor |
| Cifrado con índice ciego | `ms-autenticacion`, `ms-notificaciones` | Buscar por correo sin descifrar la tabla |
| Registro encadenado por hash | `ms-bitacora` | Detecta manipulación de la auditoría |

---

## 15. Explicación de cada diagrama

### 15.1 Arquitectura general — `01-arquitectura-general.drawio`

**Qué modela:** el negocio y los requerimientos. Responde *qué* hace el sistema, no con qué está construido. Por eso no lleva tecnologías, íconos ni contenedores de infraestructura.

| Bloque | Qué representa |
|---|---|
| **Portal Web Corporativo** | El único canal de entrada de los usuarios internos: maker, checker, authorizer y auditor. Se dibuja como un solo bloque porque desde la arquitectura es un solo consumidor de la API. |
| **API Gateway** | Banda horizontal porque atraviesa a todo el sistema: nada entra sin pasar por él. Concentra enrutamiento, validación del token, límite de uso e identificador de correlación. |
| **ms-lotes, ms-aprobaciones, ms-transacciones** | Fila superior de microservicios: es el camino principal del negocio, en el orden en que ocurre —se carga, se aprueba, se envía—. Ese orden de izquierda a derecha es intencional y se lee como el recorrido del lote. |
| **ms-notificaciones, ms-bitacora** | Fila inferior: no participan en el camino principal, reaccionan a lo que ya ocurrió. Están debajo del bus porque solo se enteran por eventos. |
| **Bus de eventos** | Banda intermedia que separa las dos filas. Su posición no es decorativa: todo lo que está encima publica y todo lo que está debajo consume. |
| **Cilindros** | Una base de datos por microservicio, dibujada pegada a su dueño para dejar claro que nadie más la toca. |
| **Columna derecha** | Lo que el sistema no controla. Arriba, la identidad: OAuth Corporativo (externo) y los dos servicios de la Práctica 2. Abajo, los terceros con los que el negocio conversa: core bancario, servicio de correo y almacenamiento de archivos. |
| **Borde continuo / punteado** | Continuo: microservicio propio, con base independiente. Punteado: sistema externo a la solución. Es la única distinción visual del diagrama, y sustituye al uso de colores. |
| **Flecha llena / punteada** | Llena: llamada síncrona REST, quien llama espera respuesta. Punteada: evento asíncrono, quien publica no espera a nadie. |

**Divisiones que no existen y por qué:** no hay caja de Kubernetes, de nube ni de red. Agrupar los microservicios dentro de un contenedor de infraestructura mezclaría la vista lógica con la física y ataría el diagrama a una decisión de despliegue que el enunciado declaró opcional.

### 15.2 Componentes UML — `02-diagrama-componentes.drawio`

**Qué modela:** la relación entre microservicios, API Gateway y sistemas externos en notación UML de componentes.

| Elemento | Significado |
|---|---|
| Caja con el ícono de componente y `«component»` | Unidad desplegable de forma independiente |
| Caja con borde punteado y `«external system»` | Sistema fuera del alcance del diseño |
| Círculo sobre cada componente | Interfaz **provista**: lo que ese componente ofrece a los demás (`ILotes`, `IAprobaciones`, `IAutorizacion`…) |
| Flecha punteada `«use»` hacia un círculo | Interfaz **requerida**: el componente necesita ese contrato para funcionar |
| Flecha punteada gris hacia el bus | Publicación o consumo de eventos |

**Cómo leerlo:** el portal solo depende de `IApiPublica`; el Gateway depende de las interfaces de los microservicios y de `IAutenticacion`; los microservicios de negocio dependen de `IAutorizacion` y de los sistemas externos. Ningún componente accede a la base de otro: toda colaboración pasa por una interfaz publicada o por el bus. Ese es exactamente el criterio que evita el acoplamiento indebido entre servicios.

### 15.3 Modelos ER — `03-modelos-er.drawio` (6 hojas)

Una hoja por microservicio más una de referencia de la Práctica 2. Cada hoja es una **base de datos completa e independiente**: no hay ninguna relación que cruce de una hoja a otra, y eso es la evidencia visual de que se cumple «una base de datos por microservicio».

| Hoja | División interna |
|---|---|
| `ms-lotes` | El archivo y el lote a la izquierda (lo que llega), las transacciones a la derecha (el contenido), y abajo la validación: la regla y el hallazgo que produjo, más el registro de descargas |
| `ms-aprobaciones` | Política → flujo → paso → decisión, de izquierda a derecha: es la misma cadena del negocio. `evento_saliente` queda aparte porque no pertenece al modelo del dominio, sirve para publicar sin perder el evento |
| `ms-transacciones` | El envío al centro y a su alrededor lo que le ocurre: sus ítems, sus intentos, las respuestas del core y la conciliación final |
| `ms-notificaciones` | Solicitud → destinatario → envío de correo; la plantilla se separa porque se administra por su cuenta y se reutiliza entre lotes |
| `ms-bitacora` | El evento al centro, con actor y recurso afectado colgando de él; `politica_retencion` es configuración, no parte de la cadena de auditoría |
| Práctica 2 | Usuario, rol y sesión en `ms-autenticacion`; permiso y rol_permiso en `ms-autorizacion`. Están en la misma hoja para mostrar la relación conceptual, **pero son dos bases distintas**: el backend nunca consulta las tablas de permisos, pregunta por HTTP |

Cuando una tabla necesita apuntar a un dato de otro servicio se guarda el identificador externo (`id_lote_externo`) sin llave foránea. Es el precio de la autonomía y se paga a conciencia.

### 15.4 Diagramas de clases — `04-diagramas-clases.drawio` (6 hojas)

Una hoja por microservicio. Cada hoja se organiza en tres zonas:

1. **Arriba: entidades del dominio.** Las que tienen las reglas del negocio. En `ms-aprobaciones`, por ejemplo, `FlujoAprobacion` es quien sabe si un usuario puede decidir un paso —la regla no vive en el endpoint.
2. **En medio: el servicio de aplicación.** Coordina el caso de uso y recibe todas sus dependencias como interfaces.
3. **Abajo: las interfaces y sus implementaciones.** `RepositorioLotes`, `AlmacenArchivos`, `ClienteAutorizacion`, `ProveedorCorreo`. Lo que las implementa se dibuja debajo, conectado con una flecha punteada de realización.

Esa división vertical —dominio arriba, infraestructura abajo— es la evidencia de la inversión de dependencias: las flechas de realización apuntan siempre hacia arriba, nunca al revés.

Las enumeraciones (`EstadoLote`, `EstadoFlujo`, `ResultadoDecision`) se dibujan aparte porque no tienen comportamiento: solo fijan los valores válidos, y son las que hacen imposible un estado inventado.

### 15.5 Diagramas de secuencia — `05-diagramas-secuencia.drawio` (5 hojas)

Cada línea de vida es un participante; el orden de izquierda a derecha sigue el recorrido del mensaje.

| Hoja | Flujo | Por qué es crítico |
|---|---|---|
| **Sec 1** | Autenticación e integración con la Práctica 2 | Muestra cómo conviven el token corporativo de 12 h y la sesión corta de la P2, y en qué momento se pregunta el permiso |
| **Sec 2** | Carga y validación del CSV | Muestra dónde se guarda el archivo, dónde se consultan saldos y cuentas, y en qué punto se aplican las reglas |
| **Sec 3** | Aprobación de tres pasos | El flujo central del enunciado: tres actores, tres permisos y la validación de segregación entre pasos |
| **Sec 4** | Envío al core bancario | Muestra la idempotencia, los reintentos con espera creciente y qué pasa si el core no responde |
| **Sec 5** | Notificación a los clientes | Muestra que el correo se dispara por evento y no bloquea la aprobación |

**Convenciones:** flecha llena, mensaje síncrono; flecha punteada, retorno; flecha abierta, mensaje asíncrono. Las cajas `alt` y `loop` son marcos de interacción UML y encierran los pasos donde hay alternativa (permitido / denegado / sin respuesta) o repetición (un correo por beneficiario). Las notas al margen justifican la decisión de diseño que se toma en ese punto.

---

## 16. Principios SOLID en el diseño

| Principio | Con mis palabras | Evidencia |
|---|---|---|
| **S** · Responsabilidad única | Cada pieza debe tener una sola razón para cambiar | `ms-aprobaciones` cambia cuando cambian las políticas de control; `ms-lotes` cuando cambia el formato de carga. Dentro de `ms-lotes`, `MotorValidacion` evalúa, `AlmacenArchivos` guarda y `ServicioLotes` coordina |
| **O** · Abierto/cerrado | Agregar comportamiento sin editar lo que ya funciona | Una regla nueva es una clase que implementa `ReglaValidacion` y se registra: no se modifica `Lote` ni `ServicioLotes`. Un rol nuevo es una fila en la matriz de `ms-autorizacion`. Un consumidor nuevo se suscribe a `LoteAprobado` sin tocar a `ms-aprobaciones` |
| **L** · Sustitución de Liskov | Cualquier implementación de un contrato puede ocupar el lugar de otra | `AlmacenArchivos` tiene versión en nube y en SFTP: `ms-lotes` funciona igual con ambas |
| **I** · Segregación de interfaces | Nadie depende de métodos que no usa | `ClienteAutorizacion` expone un único método; `ProveedorCorreo` solo lo necesario para enviar |
| **D** · Inversión de dependencias | Las políticas no dependen de los detalles; ambos dependen de abstracciones | Todos los servicios de aplicación reciben interfaces: repositorio, almacén, cliente de autorización, publicador de eventos. Los adaptadores están en el borde |

Es el mismo criterio de la Práctica 2: allí `ClienteAutorizacion` permitía cambiar el microservicio de permisos sin tocar el backend; aquí ese patrón se repite en cada frontera con un tercero.

---

## 17. Autor

**Nombre:** Jennifer Yulissa Lourdes Taperio Manuel
**Carné:** 202103763
**Sección:** B
**Curso:** Software Avanzado — Segundo Semestre 2026

**Documento complementario:** `docs/preguntas-teoricas.md`
