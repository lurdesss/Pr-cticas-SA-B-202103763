import amqplib from 'amqplib';

// Cliente del broker compartido entre el productor (pedidos-service) y el
// consumidor (pedidos-worker, mismo codigo fuente, distinto entrypoint).
//
// Diseno deliberado:
//   - la cola es durable: sobrevive a un reinicio de RabbitMQ.
//   - los mensajes se publican como persistentes (persistent: true).
//   - el productor NUNCA espera al consumidor: publica y responde.
// Esto es lo que convierte "crear un pedido" en un flujo asincrono: el
// cliente HTTP recibe su 201 sin importar si el consumidor esta arriba,
// caido o tardo.

const URL_BROKER = process.env.BROKER_URL ?? 'amqp://guest:guest@rabbitmq:5672';
const COLA_PEDIDOS = process.env.COLA_PEDIDOS ?? 'pedidos.eventos';
const COLA_RESUMENES = process.env.COLA_RESUMENES ?? 'resumenes.ejecucion';

let canalPromesa = null;

async function obtenerCanal() {
  if (canalPromesa) return canalPromesa;

  canalPromesa = (async () => {
    const conexion = await amqplib.connect(URL_BROKER);
    conexion.on('error', (error) => {
      console.error('[broker] conexion perdida:', error.message);
      canalPromesa = null; // fuerza reconexion en el siguiente intento
    });
    conexion.on('close', () => {
      canalPromesa = null;
    });

    const canal = await conexion.createChannel();
    await canal.assertQueue(COLA_PEDIDOS, { durable: true });
    await canal.assertQueue(COLA_RESUMENES, { durable: true });
    return canal;
  })();

  return canalPromesa;
}

// Publicar nunca debe tumbar la peticion HTTP que crea el pedido: si el
// broker esta caido, se registra el fallo y se continua. El pedido ya
// quedo guardado en pedidos_db; el evento es una notificacion adicional,
// no la fuente de verdad.
export async function publicarEventoPedido(evento) {
  try {
    const canal = await obtenerCanal();
    canal.sendToQueue(COLA_PEDIDOS, Buffer.from(JSON.stringify(evento)), {
      persistent: true,
      contentType: 'application/json',
    });
    console.log(`[broker] evento publicado en ${COLA_PEDIDOS}: pedido #${evento.pedidoId}`);
  } catch (error) {
    console.error(`[broker] no se pudo publicar el evento del pedido #${evento.pedidoId}: ${error.message}`);
  }
}

export { COLA_PEDIDOS, COLA_RESUMENES, obtenerCanal };
