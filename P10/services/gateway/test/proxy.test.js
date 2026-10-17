// Pruebas del gateway. Corren con el ejecutor de pruebas incluido en
// Node.js (node:test), sin dependencias adicionales: node --test test/
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { reescribir } from '../src/proxy.js';

test('reescribir() quita el prefijo publico y antepone la base del destino', () => {
  const f = reescribir('/api/catalogo', '');
  assert.equal(f('/api/catalogo/graphql'), '/graphql');
});

test('reescribir() devuelve "/" cuando la ruta resultante queda vacia', () => {
  const f = reescribir('/api/pedidos', '');
  assert.equal(f('/api/pedidos'), '/');
});

test('reescribir() respeta una base de destino no vacia', () => {
  const f = reescribir('/api/auth', '/auth');
  assert.equal(f('/api/auth/login'), '/auth/login');
});

test('reescribir() no toca una ruta que no empieza con el prefijo', () => {
  const f = reescribir('/api/pedidos', '');
  assert.equal(f('/otra/ruta'), '/otra/ruta');
});
