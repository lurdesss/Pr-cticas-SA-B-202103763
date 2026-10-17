// Metricas de negocio (P10, criterio 2.1): significan algo para quien no es
// ingeniero (la duenia del cafe), no solo para operaciones.
//
// Se crean con la API de OpenTelemetry; el SDK cargado con --import las
// expone en formato Prometheus (OTEL_METRICS_EXPORTER=prometheus, :9464)
// junto con las metricas HTTP tecnicas. Nombres resultantes en Prometheus:
//   pedidos_creados_total                 pedidos aceptados
//   pedidos_rechazados_total{motivo=...}  pedidos que el cliente no pudo hacer
//   pedidos_monto_quetzales_total         dinero vendido
import { metrics } from '@opentelemetry/api';

const medidor = metrics.getMeter('aroma-pedidos');

const creados = medidor.createCounter('pedidos_creados', {
  description: 'Pedidos aceptados por el sistema',
});
const rechazados = medidor.createCounter('pedidos_rechazados', {
  description: 'Pedidos que el cliente intento hacer y el sistema rechazo, por motivo',
});
const monto = medidor.createCounter('pedidos_monto_quetzales', {
  description: 'Monto total vendido en quetzales',
});

export function pedidoCreado(total) {
  creados.add(1);
  monto.add(Number(total) || 0);
}

// motivo: PEDIDO_VACIO, PRODUCTO_AGOTADO, CATALOGO_NO_DISPONIBLE, ...
export function pedidoRechazado(motivo) {
  rechazados.add(1, { motivo });
}
