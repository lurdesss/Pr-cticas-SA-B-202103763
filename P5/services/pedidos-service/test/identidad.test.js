import { test } from 'node:test';
import assert from 'node:assert/strict';
import { identidadDe, esAdmin } from '../src/identidad.js';

test('identidadDe() usa valores por defecto si faltan las cabeceras', () => {
  const id = identidadDe({ headers: {} });
  assert.deepEqual(id, { id: 'anonimo', rol: 'cliente', nombre: 'Invitado' });
});

test('identidadDe() normaliza el rol a minusculas', () => {
  const id = identidadDe({ headers: { 'x-usuario-rol': 'ADMIN' } });
  assert.equal(id.rol, 'admin');
});

test('identidadDe() decodifica el nombre codificado en URI', () => {
  const id = identidadDe({ headers: { 'x-usuario-nombre': 'Jos%C3%A9' } });
  assert.equal(id.nombre, 'José');
});

test('identidadDe() no revienta con un nombre mal codificado', () => {
  const id = identidadDe({ headers: { 'x-usuario-nombre': '%' } });
  assert.equal(id.nombre, 'Invitado');
});

test('esAdmin() distingue el rol admin de cualquier otro', () => {
  assert.equal(esAdmin({ rol: 'admin' }), true);
  assert.equal(esAdmin({ rol: 'cliente' }), false);
});
