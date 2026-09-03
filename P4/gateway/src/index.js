import express from 'express';

import { config } from './config.js';
import { manejadorDeErrores } from './errores.js';
import { crearVerificadorDeSesion } from './sesion.js';
import { crearClienteAutorizacion, exigirPermiso } from './autorizacion.js';
import { crearProxy } from './proxy.js';
import { rutas, resolverPermiso, permisosDeclarados } from './rutas.js';
import { estadoDelSistema } from './salud.js';

const app = express();
app.disable('x-powered-by');

// Bitacora de una linea por peticion. Es lo que se proyecta durante la
// demostracion para ver 200 / 403 / 503 en vivo.
app.use((peticion, respuesta, siguiente) => {
  const inicio = Date.now();
  respuesta.on('finish', () => {
    console.log(
      `[gateway] ${peticion.method} ${peticion.originalUrl} -> ${respuesta.statusCode} (${Date.now() - inicio} ms)`,
    );
  });
  siguiente();
});

const verificarSesion = crearVerificadorDeSesion({
  authUrl: config.servicios.auth,
  timeoutMs: config.sesionTimeoutMs,
});

const verificarPermiso = crearClienteAutorizacion({
  url: config.servicios.authz,
  ...config.autorizacion,
});

// --------------------------------------------------------------- sondas
app.get('/salud', async (_peticion, respuesta) => {
  const estado = await estadoDelSistema(config.servicios);
  respuesta.status(estado.estado === 'arriba' ? 200 : 503).json(estado);
});

app.get('/api/salud', async (_peticion, respuesta) => {
  const estado = await estadoDelSistema(config.servicios);
  respuesta.status(estado.estado === 'arriba' ? 200 : 503).json(estado);
});

// Diagnostico: que permisos tiene realmente el rol de la sesion actual.
// Util cuando la matriz del microservicio de autorizacion todavia no
// incluye los permisos de la Practica 4.
app.get('/api/diagnostico', verificarSesion, async (peticion, respuesta, siguiente) => {
  try {
    const permisos = permisosDeclarados();
    const veredictos = {};
    for (const permiso of permisos) {
      veredictos[permiso] = await verificarPermiso(peticion.usuario.rol, permiso);
    }
    respuesta.json({ usuario: peticion.usuario, permisos: veredictos });
  } catch (error) {
    siguiente(error);
  }
});

// ------------------------------------------------------- rutas del mapa
for (const ruta of rutas) {
  const cadena = [];

  if (!ruta.publico) {
    cadena.push(verificarSesion);
    cadena.push(exigirPermiso(verificarPermiso, resolverPermiso(ruta)));
  }

  cadena.push(
    crearProxy({
      destino: config.servicios[ruta.destino],
      prefijo: ruta.prefijo,
      destinoBase: ruta.destinoBase,
      timeoutMs: config.proxyTimeoutMs,
    }),
  );

  app.use(ruta.prefijo, ...cadena);
  console.log(`[gateway] ${ruta.prefijo} -> ${config.servicios[ruta.destino]}${ruta.destinoBase || ''}`);
}

app.use((_peticion, respuesta) =>
  respuesta.status(404).json({ detalle: 'El gateway no conoce esa ruta.', codigo: 'RUTA_DESCONOCIDA' }),
);

app.use(manejadorDeErrores);

app.listen(config.puerto, () => {
  console.log(`[gateway] escuchando en el puerto ${config.puerto}`);
});
