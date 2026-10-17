import express from 'express';
import { ApolloServer } from '@apollo/server';
import { expressMiddleware } from '@apollo/server/express4';
import { ApolloServerPluginLandingPageLocalDefault } from '@apollo/server/plugin/landingPage/default';

import { typeDefs } from './esquema.js';
import { resolvers } from './resolvers.js';
import { contextoDesdePeticion } from './contexto.js';
import { esperarBaseDeDatos, inicializarEsquema } from './db.js';
import { registro } from './registro.js';

const puerto = Number(process.env.PUERTO ?? 4001);

const app = express();
app.disable('x-powered-by');

app.get('/salud', (_peticion, respuesta) =>
  respuesta.json({ servicio: 'catalogo-service', estado: 'arriba', api: 'GraphQL', lenguaje: 'Node.js' }),
);

await esperarBaseDeDatos();
await inicializarEsquema();

const servidor = new ApolloServer({
  typeDefs,
  resolvers,
  introspection: true,
  plugins: [ApolloServerPluginLandingPageLocalDefault({ embed: true })],
});

await servidor.start();

app.use(
  '/graphql',
  express.json({ limit: '256kb' }),
  expressMiddleware(servidor, {
    context: async ({ req }) => contextoDesdePeticion(req),
  }),
);

app.listen(puerto, () => registro.info({ puerto }, 'catalogo GraphQL escuchando'));
