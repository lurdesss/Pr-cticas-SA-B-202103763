# Preguntas teóricas y de defensa

Preparación para la calificación (criterio 1.5 de la rúbrica: *Preguntas teóricas*, 10 pts).

---

## Arquitectura

**1. ¿Por qué microservicios y no un monolito modular?**
Un monolito modular ordenaría el código, pero no resuelve el problema del enunciado: en el pico de cierre de mes se degrada todo junto porque comparte proceso, base y despliegue. Se necesita escalar la carga de archivos sin escalar la aprobación, y cambiar una regla sin redesplegar el envío al core. Eso exige unidades desplegables por separado.

**2. ¿Cuál es el costo de esta decisión?**
Complejidad operativa: siete servicios, mensajería, trazabilidad distribuida y consistencia eventual. Se acepta porque el sistema es de alta demanda y auditable. En un sistema pequeño la respuesta correcta sería el monolito.

**3. ¿Cómo se decidió el límite de cada microservicio?**
Por capacidad de negocio y ritmo de cambio, no por capa técnica. La pregunta guía: *¿qué motivo distinto obligaría a modificar esto?* La aprobación cambia con las políticas de control; la validación de archivos, con el formato de carga. Son dos servicios.

**4. ¿Por qué una base de datos por microservicio?**
Porque compartir base reintroduce el acoplamiento del monolito: dos servicios que comparten tabla no evolucionan por separado. El costo es perder las llaves foráneas entre servicios; se compensa con eventos e idempotencia.

**5. Sin llaves foráneas entre bases, ¿cómo se garantiza la integridad?**
Se guarda el identificador externo y la consistencia se logra por eventos: es consistencia eventual. Donde debe ser fuerte —las tres decisiones de un mismo flujo— todo ocurre dentro de una sola base, con transacción.

**6. ¿Por qué el diagrama de arquitectura general no lleva tecnologías ni íconos?**
Porque modela el negocio y los requerimientos: qué hace cada parte y cómo se comunican. Las tecnologías son una decisión aparte y se declaran en la sección de requerimientos técnicos. Mezclarlas envejece el diagrama y confunde la vista lógica con la física.

**7. ¿Por qué no se incluyó Docker ni Kubernetes?**
El enunciado los declara opcionales y ningún elemento del alcance los pide. Incluirlos habría obligado a dibujar infraestructura dentro de una vista de negocio. Se prefirió cumplir el alcance con precisión antes que agregar cajas que no se piden.

---

## Autenticación y autorización

**8. ¿Por qué dos mecanismos de identidad si el enunciado ya pide OAuth?**
Responden preguntas distintas. El token corporativo de 12 h acredita que quien pide es un empleado vigente; la sesión de la Práctica 2 acredita que **esta** sesión sigue siendo válida y dura minutos. Un token de 12 h como credencial única deja una ventana de un día entero si se intercepta.

**9. ¿Dónde se guarda el token de sesión y por qué?**
En cookie HTTP-only, igual que en la Práctica 2. En `localStorage` quedaría legible por cualquier script de la página; con `httponly` un XSS no puede leerlo ni enviarlo a otro servidor.

**10. ¿Por qué la vida de la cookie es mayor que la del JWT?**
Si la cookie caducara junto con el token, el navegador dejaría de enviarla justo cuando el backend la necesita para renovarla, y la ventana de gracia nunca se usaría. Por eso `max_age = ttl + gracia`.

**11. ¿Cómo funciona la renovación automática?**
Al verificar se distinguen tres estados: válido, expirado pero renovable y rechazado. En el segundo se emite un token nuevo y se reescribe la cookie. Para leer un token expirado se desactiva **solo** la comprobación de expiración: la verificación de firma sigue activa, así que un token expirado y falsificado se rechaza igual.

**12. ¿Por qué la autorización es un servicio aparte?**
Porque el backend sabe *quién* es el usuario y el servicio de permisos sabe *qué puede hacer cada rol*: son preguntas distintas que cambian a distinto ritmo. Además, si el backend guardara copia de la matriz, las dos versiones se desincronizarían; al estar obligado a preguntar, no puede ocurrir.

**13. Si `ms-autorizacion` está caído, ¿se responde 403?**
No: 503. Un 403 afirma que el usuario no tiene permiso, y si nadie pudo comprobarlo esa afirmación es falsa. Se reintenta con espera creciente y, agotados los intentos, 503.

---

## Flujo de aprobación

**14. ¿Qué es maker–checker–authorizer y por qué tres pasos?**
Es separar el ciclo de una operación en registro, verificación y autorización, ejecutados por personas distintas. Con dos pasos bastaría un cómplice; con tres se exige la colusión de tres personas con permisos distintos, lo que encarece mucho el fraude.

**15. ¿Cómo se impide que la misma persona apruebe dos pasos?**
Se valida en la entidad `FlujoAprobacion` y además con una restricción única en la base: un mismo usuario no puede aparecer en dos decisiones del mismo flujo. Si una refactorización rompiera la validación de aplicación, la base rechaza igual.

**16. ¿Qué pasa si un lote se rechaza en el paso 2?**
El flujo se cierra como `RECHAZADO` con motivo obligatorio y no se envía nada al core. Si el error es corregible, el checker lo devuelve: el lote corregido abre un flujo nuevo, nunca reabre el anterior, para que el rastro de auditoría no se pueda reescribir.

**17. ¿Y si nadie decide?**
Cada paso tiene fecha límite por política. Vencido el plazo el flujo pasa a `VENCIDO` y hay que someterlo de nuevo, para no aprobar un lote con información de dos semanas atrás.

---

## Comunicación e integración

**18. ¿Cuándo REST y cuándo mensajería?**
Si quien llama necesita la respuesta para continuar, REST: verificación de permiso, consulta de saldo, lista de beneficiarios. Si no la necesita, evento: envío al core, notificación y bitácora.

**19. ¿Qué pasa si se cambia el estado pero el evento no se publica?**
Es el problema de la doble escritura. Se resuelve escribiendo el evento en una tabla de salida dentro de la misma transacción que el cambio de estado; un publicador lo lleva al bus después. O pasan ambas cosas o ninguna.

**20. ¿Y si un evento llega dos veces?**
Cada consumidor guarda la clave del evento procesado y descarta el repetido. En el envío al core, además, la clave de idempotencia viaja hacia el core, que reconoce el duplicado y no repite el débito.

**21. ¿Qué pasa si el core bancario no responde?**
Cuatro intentos con espera creciente, siempre con la misma clave de idempotencia. Agotados, el envío pasa a cola de fallidos con alerta y **nunca** se marca como enviado. También hay corte de circuito para dejar de golpear a un servicio caído.

**22. ¿Por qué el evento `LoteAprobado` no lleva los correos de los beneficiarios?**
Porque un tema de mensajería con retención sería un depósito de datos personales fuera del control del servicio que los posee. `ms-notificaciones` los consulta a `ms-lotes` cuando los necesita.

---

## Archivos, logging y auditoría

**23. ¿Por qué el CSV no se guarda en la base de datos?**
Porque un archivo de planilla puede pesar decenas de megabytes: infla las copias de respaldo, degrada las consultas y complica la descarga. En la base van la ruta y el hash.

**24. ¿Cómo se descarga un archivo sin exponerlo?**
Con un enlace temporal de cinco minutos emitido tras verificar el permiso. El archivo no atraviesa el microservicio y el enlace caduca solo.

**25. ¿Qué diferencia hay entre el log técnico y la bitácora?**
El log técnico sirve para diagnosticar, vive 30 días y se puede rotar. La bitácora responde «quién hizo qué y cuándo» ante un auditor, es relacional, solo admite inserción, se conserva 7 años y está encadenada por hash. Mezclarlos deja la evidencia regulatoria sujeta a una rotación de índices.

**26. ¿Cómo se detecta si alguien manipuló la bitácora?**
Cada evento guarda `SHA-256(hash_previo + contenido)`. Al borrar o editar una fila la cadena se rompe y el verificador lo reporta.

**27. ¿Cómo se sigue un lote de punta a punta?**
Por el identificador de correlación que genera el Gateway y que viaja en toda llamada, todo evento y todo registro. Con un solo valor se ve la carga, la validación, las tres decisiones, los intentos contra el core y los correos.

---

## Diseño

**28. ¿Dónde se ve el principio abierto/cerrado?**
Una regla de validación nueva es una clase que implementa `ReglaValidacion` y se registra: no se modifica `Lote` ni `ServicioLotes`. Un rol nuevo es una fila en la matriz de permisos. Un consumidor nuevo se suscribe a un evento sin tocar al productor.

**29. ¿Y la inversión de dependencias?**
Los servicios de aplicación reciben interfaces por constructor: repositorio, almacén de archivos, cliente de autorización, publicador de eventos. El dominio no conoce HTTP, SQL ni el proveedor de almacenamiento; por eso cambiar la nube por un SFTP es escribir otro adaptador.

**30. ¿Cómo se migraría desde el monolito actual?**
Por estrangulamiento: el Gateway enruta un flujo a la vez hacia los servicios nuevos, empezando por la consulta del historial —solo lectura, riesgo bajo— y terminando por el envío al core. Cada etapa admite volver atrás.
