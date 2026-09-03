// Prueba de carga contra el API Gateway (requisito I de la Practica 5).
// Ejecutar con:
//   k6 run scripts/carga-k6.js
// o, para apuntar a otro host/puerto:
//   k6 run -e BASE_URL=http://aroma.local scripts/carga-k6.js
//
// La meta no es "romper" el sistema: es sostener suficiente concurrencia
// el tiempo suficiente para que el HPA del gateway y de catalogo crucen
// el 70% de CPU y kubectl "get hpa -w" muestre el escalado en vivo.

import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate, Trend } from 'k6/metrics';

const BASE_URL = __ENV.BASE_URL || 'http://aroma.local';

const tasaDeError = new Rate('tasa_de_error_propia');
const duracionCatalogo = new Trend('duracion_catalogo_ms');
const duracionPedido = new Trend('duracion_pedido_ms');

// Rampa: sube poco a poco, sostiene una carga que deberia mantener al
// gateway y al catalogo por encima del 70% de CPU un rato, y luego baja
// a cero para poder observar el DESCENSO de replicas del HPA
// (kubectl get hpa -w sigue mostrando numeros varios minutos despues,
// porque el HPA por defecto espera ~5 minutos de calma antes de reducir).
export const options = {
  scenarios: {
    carga_creciente: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '30s', target: 10 },
        { duration: '30s', target: 30 },
        { duration: '2m', target: 60 },   // sostenido: aqui deberia dispararse el HPA
        { duration: '30s', target: 0 },   // enfriamiento: aqui se observa el descenso
      ],
    },
  },
  thresholds: {
    http_req_duration: ['p(95)<1500'],   // latencia p95 objetivo del reporte
    tasa_de_error_propia: ['rate<0.05'], // menos de 5% de error autoevaluado
  },
};

const CONSULTA_MENU = JSON.stringify({
  query: '{ productos(soloDisponibles: true) { id nombre precio } }',
});

export default function () {
  // 1) Lectura: el menu via el gateway -> catalogo-service (GraphQL).
  const respuestaMenu = http.post(`${BASE_URL}/api/catalogo/graphql`, CONSULTA_MENU, {
    headers: { 'Content-Type': 'application/json' },
    tags: { endpoint: 'catalogo' },
  });
  duracionCatalogo.add(respuestaMenu.timings.duration);

  const menuOk = check(respuestaMenu, {
    'catalogo responde 200': (r) => r.status === 200,
    'catalogo no trae errors': (r) => {
      try {
        return !JSON.parse(r.body).errors;
      } catch {
        return false;
      }
    },
  });
  tasaDeError.add(!menuOk);

  // 2) Escritura ocasional: crear un pedido via el gateway -> pedidos-service
  // (REST), que a su vez llama al catalogo y publica un evento asincrono en
  // RabbitMQ. Se manda 1 de cada 5 iteraciones para no saturar solo con
  // pedidos y poder aislar el efecto de cada endpoint en el reporte.
  if (Math.random() < 0.2) {
    const cuerpoPedido = JSON.stringify({
      items: [{ productoId: '1', cantidad: 1 }],
      notas: 'pedido generado por la prueba de carga k6',
    });

    const respuestaPedido = http.post(`${BASE_URL}/api/pedidos`, cuerpoPedido, {
      headers: { 'Content-Type': 'application/json', 'X-Usuario-Id': `k6-${__VU}`, 'X-Usuario-Rol': 'cliente' },
      tags: { endpoint: 'pedidos' },
    });
    duracionPedido.add(respuestaPedido.timings.duration);

    tasaDeError.add(
      !check(respuestaPedido, {
        'pedido responde 201': (r) => r.status === 201,
      }),
    );
  }

  sleep(Math.random() * 0.5 + 0.2); // pausa corta y variable entre iteraciones de un mismo VU
}

// Al terminar, k6 imprime el resumen estandar (incluye RPS y p95 en
// "http_req_duration"); este resumen personalizado agrega el % de error
// tal como lo pide el entregable de la practica.
export function handleSummary(data) {
  const total = data.metrics.http_reqs ? data.metrics.http_reqs.values.count : 0;
  const fallidas = data.metrics.http_req_failed ? data.metrics.http_req_failed.values.rate * total : 0;
  const p95 = data.metrics.http_req_duration ? data.metrics.http_req_duration.values['p(95)'] : null;
  const rps = data.metrics.http_reqs ? data.metrics.http_reqs.values.rate : null;

  console.log('\n=== Resumen para el entregable de la Practica 5 ===');
  console.log(`Peticiones totales: ${total}`);
  console.log(`Peticiones por segundo (RPS): ${rps ? rps.toFixed(2) : 'n/d'}`);
  console.log(`Latencia p95: ${p95 ? p95.toFixed(0) : 'n/d'} ms`);
  console.log(`Porcentaje de error: ${total ? ((fallidas / total) * 100).toFixed(2) : '0.00'}%`);

  return {
    stdout: '', // deja que k6 imprima su resumen normal ademas del nuestro
  };
}
