// Registros estructurados en JSON (P10, criterio 2.5).
//
// pino escribe una linea JSON por evento en stdout; Promtail la recoge y la
// guarda en Loki. Cada linea lleva trace_id y span_id de la traza activa,
// leidos con la API de OpenTelemetry en el "mixin": desde una traza en Tempo
// se llega a sus registros (busqueda por trace_id en Loki) y desde un
// registro a su traza (campo derivado en Grafana).
//
// Por que un mixin y no la instrumentacion automatica de pino: con modulos
// ESM esa instrumentacion no se aplico (prueba local: lineas sin trace_id).
// El mixin no depende del cargador de modulos.
import pino from 'pino';
import { trace, isSpanContextValid } from '@opentelemetry/api';

export const registro = pino({
  base: { servicio: process.env.OTEL_SERVICE_NAME ?? 'desconocido' },
  messageKey: 'mensaje',
  timestamp: pino.stdTimeFunctions.isoTime,
  formatters: { level: (etiqueta) => ({ nivel: etiqueta }) },
  mixin() {
    const contexto = trace.getActiveSpan()?.spanContext();
    if (!contexto || !isSpanContextValid(contexto)) return {};
    return { trace_id: contexto.traceId, span_id: contexto.spanId };
  },
});
