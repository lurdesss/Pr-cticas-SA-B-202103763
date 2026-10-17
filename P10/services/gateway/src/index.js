// Gateway de Aroma, instrumentado para P10.
//
// La instrumentacion (trazas, metricas HTTP y propagacion W3C traceparent
// hacia los microservicios) la carga el SDK de OpenTelemetry ANTES de este
// archivo: node --import @opentelemetry/auto-instrumentations-node/register
// (ver Dockerfile). Aqui solo se agregan los registros JSON y el fallo
// inducible de la version candidata.
import express from 'express';
import { trace, SpanStatusCode } from '@opentelemetry/api';
import { config } from './config.js';
import { crearProxy } from './proxy.js';
import { rutas } from './rutas.js';
import { estadoDelSistema } from './salud.js';
import { publicarAuditoria } from './broker.js';
import { registro } from './registro.js';

const app = express();
app.disable('x-powered-by');

// Un registro JSON por peticion, con trace_id (lo agrega la instrumentacion
// de pino porque el evento "finish" corre dentro del contexto de la peticion).
app.use((peticion, respuesta, siguiente) => {
  const inicio = Date.now();
  respuesta.on('finish', () => {
    const datos = {
      metodo: peticion.method,
      ruta: peticion.originalUrl,
      codigo: respuesta.statusCode,
      duracion_ms: Date.now() - inicio,
      version: config.version,
    };
    if (respuesta.statusCode >= 500) registro.error(datos, 'peticion fallida');
    else registro.info(datos, 'peticion atendida');
  });
  siguiente();
});

// Auditoria asincrona por RabbitMQ (P6): solo si hay broker configurado. En
// P9/P10 no se despliega RabbitMQ; sin esta condicion cada peticion dejaba un
// error de conexion en los registros, ruido que entorpece buscar la causa.
if (config.broker.habilitado) {
  app.use('/api', (peticion, _respuesta, siguiente) => {
    publicarAuditoria({ metodo: peticion.method, ruta: peticion.originalUrl, ip: peticion.ip, marcaDeTiempo: new Date().toISOString() });
    siguiente();
  });
}

// Fallo inducido (P10): solo existe si la version candidata del Rollout lo
// declara por variables de entorno (FALLA_PORCENTAJE, FALLA_LATENCIA_MS).
// Afecta a las rutas /api reales, nunca a /salud, para que los pods queden
// listos, reciban trafico real y el canary lo detecte POR METRICAS.
if (config.falla.porcentaje > 0 || config.falla.latenciaMs > 0) {
  registro.warn({ falla: config.falla }, 'fallo inducido ACTIVO en esta version');
  app.use('/api', async (peticion, respuesta, siguiente) => {
    if (config.falla.latenciaMs > 0) await new Promise((r) => setTimeout(r, config.falla.latenciaMs));
    if (Math.random() * 100 < config.falla.porcentaje) {
      const span = trace.getActiveSpan();
      span?.setAttribute('aroma.falla_inducida', true);
      span?.setStatus({ code: SpanStatusCode.ERROR, message: 'fallo inducido de la version candidata' });
      registro.error({ ruta: peticion.originalUrl, version: config.version, causa: 'FALLA_PORCENTAJE' },
        'fallo inducido: la version candidata rechaza la peticion');
      return respuesta.status(500).json({ detalle: 'Error interno del gateway.', codigo: 'FALLA_INDUCIDA' });
    }
    siguiente();
  });
}

// Sonda propia: la usan los probes de Kubernetes (liveness/readiness/startup).
app.get('/salud', (_peticion, respuesta) => respuesta.json({ servicio: 'gateway', estado: 'arriba' }));

// Sonda agregada: el estado de los cuatro microservicios detras del gateway.
app.get('/api/salud', async (_peticion, respuesta) => {
  const estado = await estadoDelSistema(config.servicios);
  respuesta.status(estado.estado === 'arriba' ? 200 : 503).json(estado);
});

for (const ruta of rutas) {
  app.use(
    ruta.prefijo,
    crearProxy({ destino: config.servicios[ruta.destino], prefijo: ruta.prefijo, destinoBase: ruta.destinoBase, timeoutMs: config.proxyTimeoutMs }),
  );
  registro.info({ prefijo: ruta.prefijo, destino: config.servicios[ruta.destino] }, 'ruta registrada');
}

app.use((_peticion, respuesta) => respuesta.status(404).json({ detalle: 'El gateway no conoce esa ruta.', codigo: 'RUTA_DESCONOCIDA' }));

app.listen(config.puerto, () => registro.info({ puerto: config.puerto, version: config.version }, 'gateway escuchando'));
