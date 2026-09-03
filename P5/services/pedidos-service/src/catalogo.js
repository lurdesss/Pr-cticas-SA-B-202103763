// Comunicacion directa entre microservicios: pedidos no guarda una copia
// del menu, se lo pregunta al catalogo por su API GraphQL. Asi el precio
// que se cobra es siempre el vigente y no una copia desincronizada.

const CATALOGO_URL = process.env.CATALOGO_URL ?? 'http://catalogo-service:4001';
const TIMEOUT_MS = Number(process.env.CATALOGO_TIMEOUT_MS ?? 3000);

const CONSULTA = `
  query ($id: ID!) {
    producto(id: $id) { id nombre precio disponible }
  }
`;

export class ErrorCatalogoNoDisponible extends Error {}

export async function obtenerProducto(id) {
  let respuesta;
  try {
    respuesta = await fetch(`${CATALOGO_URL}/graphql`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ query: CONSULTA, variables: { id: String(id) } }),
      signal: AbortSignal.timeout(TIMEOUT_MS),
    });
  } catch (error) {
    throw new ErrorCatalogoNoDisponible(error.message);
  }

  if (!respuesta.ok) throw new ErrorCatalogoNoDisponible(`catalogo respondio ${respuesta.status}`);

  const cuerpo = await respuesta.json();
  if (cuerpo.errors?.length) throw new ErrorCatalogoNoDisponible(cuerpo.errors[0].message);

  return cuerpo.data?.producto ?? null;
}
