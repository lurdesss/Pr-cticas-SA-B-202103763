import express from 'express';
import { config } from './config.js';
import { crearProxy } from './proxy.js';
import { rutas } from './rutas.js';
import { estadoDelSistema } from './salud.js';
import { publicarAuditoria } from './broker.js';

const app = express();
app.disable('x-powered-by');

app.use((peticion, respuesta, siguiente) => {
  const inicio = Date.now();
  respuesta.on('finish', () => {
    console.log(`[gateway] ${peticion.method} ${peticion.originalUrl} -> ${respuesta.statusCode} (${Date.now() - inicio} ms)`);
  });
  siguiente();
});

// Comunicacion asincrona gateway <-> microservicio (Practica 6): se
// publica el evento y se llama a "siguiente()" de inmediato, SIN esperar
// a que la publicacion termine. El proxy hacia el microservicio de
// destino sigue su camino sincrono normal; la auditoria viaja aparte, la
// consume pedidos-worker cuando puede, y nunca retrasa ni puede tumbar
// la peticion original.
app.use('/api', (peticion, _respuesta, siguiente) => {
  publicarAuditoria({
    metodo: peticion.method,
    ruta: peticion.originalUrl,
    ip: peticion.ip,
    marcaDeTiempo: new Date().toISOString(),
  }); // sin "await" a proposito: fire-and-forget
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
