// Consumidor del broker. Es la otra mitad del flujo asincrono: pedidos-service
// publica y responde de inmediato; este proceso, en un Deployment aparte,
// consume cuando puede.
//
// Dos colas, un solo worker:
//   pedidos.eventos    -> lo publica pedidos-service en cada pedido nuevo
//   resumenes.ejecucion -> lo publica el Cronjob 2 cada 10 minutos
//
// Regla de entrega: prefetch(1) + ack manual solo tras escribir en
// PostgreSQL. Si el proceso muere a mitad de un mensaje, RabbitMQ lo
// reencola porque nunca llego el ack. Es lo que permite demostrar que,
// con el consumidor caido, los mensajes se acumulan en la cola durable y
// se procesan sin perdida al restaurarlo.

import amqplib from 'amqplib';
import { pool, esperarBaseDeDatos, inicializarEsquema } from './db.js';

const URL_BROKER = process.env.BROKER_URL ?? 'amqp://guest:guest@rabbitmq:5672';
const COLA_PEDIDOS = process.env.COLA_PEDIDOS ?? 'pedidos.eventos';
const COLA_RESUMENES = process.env.COLA_RESUMENES ?? 'resumenes.ejecucion';

const dormir = (ms) => new Promise((r) => setTimeout(r, ms));

async function procesarEventoPedido(evento) {
  await pool.query(
    `INSERT INTO notificaciones_pedidos (pedido_id, mensaje) VALUES ($1, $2)`,
    [evento.pedidoId, `Pedido #${evento.pedidoId} recibido por Q${evento.total}. Notificacion procesada de forma asincrona.`],
  );
  console.log(`[worker] pedido #${evento.pedidoId} notificado (cola: ${COLA_PEDIDOS}).`);
}

async function procesarResumen(resumen) {
  await pool.query(
    `INSERT INTO resumenes_cron (hora, total_ejecuciones) VALUES ($1, $2)`,
    [resumen.hora, resumen.totalEjecuciones],
  );
  console.log(`[worker] resumen de ${resumen.hora} guardado: ${resumen.totalEjecuciones} ejecuciones (cola: ${COLA_RESUMENES}).`);
}

async function conectarConReintentos(intentos = 20, esperaMs = 3000) {
  for (let intento = 1; intento <= intentos; intento += 1) {
    try {
      return await amqplib.connect(URL_BROKER);
    } catch (error) {
      console.warn(`[worker] RabbitMQ no responde (intento ${intento}/${intentos}): ${error.message}`);
      await dormir(esperaMs);
    }
  }
  throw new Error('RabbitMQ no respondio.');
}

async function consumir(canal, cola, manejador) {
  await canal.assertQueue(cola, { durable: true });
  await canal.prefetch(1); // un mensaje a la vez: sin esto, un pico de pedidos podria saturar la escritura a PostgreSQL

  canal.consume(cola, async (mensaje) => {
    if (!mensaje) return;
    try {
      const contenido = JSON.parse(mensaje.content.toString());
      await manejador(contenido);
      canal.ack(mensaje); // solo se confirma tras escribir en la base de datos
    } catch (error) {
      console.error(`[worker] error procesando mensaje de ${cola}: ${error.message}. Se reencola.`);
      canal.nack(mensaje, false, true); // vuelve a la cola para reintentar
      await dormir(2000);
    }
  });

  console.log(`[worker] escuchando ${cola}...`);
}

async function iniciar() {
  await esperarBaseDeDatos();
  await inicializarEsquema();

  const conexion = await conectarConReintentos();
  conexion.on('close', () => {
    console.error('[worker] conexion con RabbitMQ cerrada. El proceso termina para que Kubernetes lo reinicie.');
    process.exit(1);
  });

  const canal = await conexion.createChannel();
  await consumir(canal, COLA_PEDIDOS, procesarEventoPedido);
  await consumir(canal, COLA_RESUMENES, procesarResumen);
}

iniciar().catch((error) => {
  console.error('[worker] fallo irrecuperable al iniciar:', error);
  process.exit(1);
});
