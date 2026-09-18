import amqplib from 'amqplib';
import { config } from './config.js';

// Productor de eventos de auditoria. Es la mitad "gateway -> broker" del
// flujo asincrono gateway <-> microservicio que pide la Practica 6: el
// gateway publica y sigue con su trabajo sin esperar respuesta de nadie;
// pedidos-worker consume esta cola de forma completamente independiente
// (ver services/pedidos-service/src/worker.js).
//
// Deliberadamente NO bloquea ni retrasa el proxy: si RabbitMQ esta lento
// o caido, la peticion HTTP que el gateway esta atendiendo se reenvia
// igual. Publicar la auditoria es una tarea secundaria, no la razon de
// ser del gateway.

let canalPromesa = null;

async function obtenerCanal() {
  if (canalPromesa) return canalPromesa;

  canalPromesa = (async () => {
    const conexion = await amqplib.connect(config.broker.url);
    conexion.on('error', (error) => {
      console.error('[broker-gateway] conexion perdida:', error.message);
      canalPromesa = null;
    });
    conexion.on('close', () => {
      canalPromesa = null;
    });

    const canal = await conexion.createChannel();
    await canal.assertQueue(config.broker.colaAuditoria, { durable: true });
    return canal;
  })();

  return canalPromesa;
}

export async function publicarAuditoria(evento) {
  try {
    const canal = await obtenerCanal();
    canal.sendToQueue(config.broker.colaAuditoria, Buffer.from(JSON.stringify(evento)), {
      persistent: true,
      contentType: 'application/json',
    });
  } catch (error) {
    // Un fallo aqui nunca debe verse reflejado en la respuesta HTTP: se
    // registra y se sigue. La auditoria es complementaria, no critica.
    console.error(`[broker-gateway] no se pudo publicar la auditoria de ${evento.ruta}: ${error.message}`);
  }
}
