import express from 'express';
import { config } from './config.js';
import { crearProxy } from './proxy.js';
import { rutas } from './rutas.js';
import { estadoDelSistema } from './salud.js';

const app = express();
app.disable('x-powered-by');

app.use((peticion, respuesta, siguiente) => {
  const inicio = Date.now();
  respuesta.on('finish', () => {
    console.log(`[gateway] ${peticion.method} ${peticion.originalUrl} -> ${respuesta.statusCode} (${Date.now() - inicio} ms)`);
  });
  siguiente();
});

// Sonda propia: la usan los probes de Kubernetes (liveness/readiness/startup).
app.get('/salud', (_peticion, respuesta) => respuesta.json({ servicio: 'gateway', estado: 'arriba' }));

// Sonda agregada: el estado de los cuatro microservicios detras del gateway.
// Es lo primero que se revisa al diagnosticar un despliegue de Helm.
app.get('/api/salud', async (_peticion, respuesta) => {
  const estado = await estadoDelSistema(config.servicios);
  respuesta.status(estado.estado === 'arriba' ? 200 : 503).json(estado);
});

for (const ruta of rutas) {
  app.use(
    ruta.prefijo,
    crearProxy({ destino: config.servicios[ruta.destino], prefijo: ruta.prefijo, destinoBase: ruta.destinoBase, timeoutMs: config.proxyTimeoutMs }),
  );
  console.log(`[gateway] ${ruta.prefijo} -> ${config.servicios[ruta.destino]}`);
}

app.use((_peticion, respuesta) => respuesta.status(404).json({ detalle: 'El gateway no conoce esa ruta.', codigo: 'RUTA_DESCONOCIDA' }));

app.listen(config.puerto, () => console.log(`[gateway] escuchando en el puerto ${config.puerto}`));
