# Diagramas

Formato **`.drawio`** (XML sin comprimir, versionable en Git).

**Abrir:** [app.diagrams.net](https://app.diagrams.net) → *Abrir archivo existente*; o la extensión *Draw.io Integration* en VS Code.
Los archivos con varias hojas se recorren con las **pestañas de abajo**.

| Archivo | Hojas | Contenido |
|---|---|---|
| `01-arquitectura-general.drawio` | 1 | Arquitectura general del sistema: negocio y requerimientos, sin tecnologías ni íconos |
| `02-diagrama-componentes.drawio` | 1 | Componentes UML: microservicios, API Gateway, bus de eventos y sistemas externos |
| `03-modelos-er.drawio` | 6 | Un modelo ER por microservicio, más la referencia de la Práctica 2 |
| `04-diagramas-clases.drawio` | 6 | Un diagrama de clases por microservicio, más la referencia de la Práctica 2 |
| `05-diagramas-secuencia.drawio` | 5 | Autenticación e integración P2 · carga y validación · aprobación de 3 pasos · envío al core · notificación |

La explicación de los bloques y divisiones de cada diagrama está en la sección 15 del `README.md`.

**Exportar a imagen:** *Archivo → Exportar como → PNG*, con **Recortar al contenido** y zoom 200 % en las hojas grandes.

**Convenciones**

- Notación UML en componentes, clases y secuencia; notación de pata de gallo en los modelos ER.
- Sin colores de relleno: la distinción se hace con el tipo de borde y con los estereotipos.
  - Borde continuo: microservicio o componente propio · borde punteado: sistema externo.
  - Flecha llena: llamada síncrona REST · flecha punteada: evento asíncrono o retorno.
- Cada hoja lleva su propia leyenda.
