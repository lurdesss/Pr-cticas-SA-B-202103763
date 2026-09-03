// Cronjob 2 (cada 10 minutos).
//
// 1. Consulta en PostgreSQL cuantas veces corrio el Cronjob 1 en la hora
//    actual (agrupado por hora, como pide el enunciado).
// 2. Publica ese resumen en RabbitMQ, en la cola resumenes.ejecucion.
// 3. Termina. Es un Job de un solo disparo: Kubernetes lo vuelve a crear
//    en el siguiente tick del CronJob.
//
// Quien guarda el resumen no es este script: es pedidos-worker, que
// consume la cola de forma independiente. Separar "calcular y publicar"
// de "consumir y guardar" es el mismo flujo productor/consumidor que ya
// usa pedidos-service, aplicado a un cronjob en vez de a un endpoint HTTP.

import pg from 'pg';
import amqplib from 'amqplib';

const URL_BASE_DE_DATOS = process.env.DATABASE_URL;
const URL_BROKER = process.env.BROKER_URL ?? 'amqp://guest:guest@rabbitmq:5672';
const COLA_RESUMENES = process.env.COLA_RESUMENES ?? 'resumenes.ejecucion';

async function calcularResumenDeLaHoraActual() {
  const pool = new pg.Pool({ connectionString: URL_BASE_DE_DATOS });
  try {
    const { rows } = await pool.query(`
      SELECT date_trunc('hour', ejecutado_en) AS hora, COUNT(*)::int AS total
      FROM ejecuciones_cron
      WHERE ejecutado_en >= date_trunc('hour', NOW())
      GROUP BY 1
    `);
    return rows[0] ?? { hora: new Date(), total: 0 };
  } finally {
    await pool.end();
  }
}

async function publicar(resumen) {
  const conexion = await amqplib.connect(URL_BROKER);
  try {
    const canal = await conexion.createChannel();
    await canal.assertQueue(COLA_RESUMENES, { durable: true });

    const mensaje = { hora: resumen.hora, totalEjecuciones: resumen.total };
    canal.sendToQueue(COLA_RESUMENES, Buffer.from(JSON.stringify(mensaje)), { persistent: true });

    console.log(`[cronjob-resumen] publicado: ${JSON.stringify(mensaje)}`);
    await canal.close();
  } finally {
    await conexion.close();
  }
}

async function principal() {
  if (!URL_BASE_DE_DATOS) throw new Error('Falta DATABASE_URL.');

  const resumen = await calcularResumenDeLaHoraActual();
  await publicar(resumen);
}

principal()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error('[cronjob-resumen] fallo:', error.message);
    process.exit(1); // backoffLimit del Job decide cuantas veces reintentar
  });
