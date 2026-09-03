import { api, alRegistrar, escapar, quetzales, ErrorApi } from './api.js';

const estado = {
  usuario: null,
  productos: [],
  promedios: {},
  carrito: new Map(),
};

const $ = (selector) => document.querySelector(selector);
const esAdmin = () => estado.usuario?.rol === 'admin';

// ------------------------------------------------ tira de comanda (firma)

const tira = $('#tira');

alRegistrar(({ metodo, ruta, estado: codigo, ms, renovado, nota }) => {
  const clase = codigo === 0 ? 'c-500' : codigo < 300 ? 'c-200' : codigo < 500 ? 'c-400' : 'c-500';
  const hora = new Date().toLocaleTimeString('es-GT', { hour12: false });
  const linea = document.createElement('div');
  linea.className = 'comanda__linea';
  linea.innerHTML =
    `<span class="silencio">${hora}</span> ` +
    `<b>${escapar(metodo)}</b> ${escapar(ruta)}<br>` +
    `<span class="comanda__codigo ${clase}"><b>${codigo || 'ERR'}</b></span> ` +
    `<span class="silencio">${ms} ms${nota ? ` · ${escapar(nota)}` : ''}</span>` +
    (renovado ? ' <span class="c-200">· token renovado</span>' : '');
  tira.prepend(linea);
  while (tira.children.length > 60) tira.lastElementChild.remove();
});

// ---------------------------------------------------------------- vistas

function activarVista(nombre) {
  document.querySelectorAll('[data-vista]').forEach((seccion) => {
    seccion.hidden = seccion.dataset.vista !== nombre;
  });
  document.querySelectorAll('.pestanas button').forEach((boton) => {
    boton.setAttribute('aria-selected', String(boton.dataset.ir === nombre));
  });
  if (nombre === 'pedidos') cargarPedidos();
  if (nombre === 'resenas') cargarResenas();
  if (nombre === 'inventario') cargarInventario();
  if (nombre === 'sistema') cargarSistema();
}

document.querySelectorAll('.pestanas button').forEach((boton) => {
  boton.addEventListener('click', () => activarVista(boton.dataset.ir));
});

function fallo(contenedor, error) {
  const detalle = error instanceof ErrorApi ? `${error.estado} · ${error.detalle}` : String(error.message);
  contenedor.innerHTML = `<p class="aviso">${escapar(detalle)}</p>`;
}

// ------------------------------------------------------------ menu

const CONSULTA_MENU = `
  query {
    categorias { id nombre descripcion }
    productos { id nombre descripcion precio disponible categoria { id nombre } }
  }
`;

async function cargarMenu() {
  const destino = $('#menu');
  destino.innerHTML = '<p class="silencio">Cargando el menu...</p>';

  try {
    const [datos, promedios] = await Promise.all([
      api.catalogo(CONSULTA_MENU),
      api.promediosResenas().catch(() => []),
    ]);

    estado.productos = datos.productos;
    estado.promedios = Object.fromEntries(promedios.map((p) => [String(p.producto_id), p]));

    destino.innerHTML = datos.categorias
      .map((categoria) => {
        const productos = datos.productos.filter((p) => p.categoria?.id === categoria.id);
        if (productos.length === 0) return '';
        return `
          <h3>${escapar(categoria.nombre)}</h3>
          <p class="silencio" style="margin-top:2px">${escapar(categoria.descripcion)}</p>
          <div class="rejilla" style="margin:12px 0 22px">
            ${productos.map(tarjetaProducto).join('')}
          </div>`;
      })
      .join('');

    conectarBotonesDelMenu();
  } catch (error) {
    fallo(destino, error);
  }
}

function tarjetaProducto(producto) {
  const resumen = estado.promedios[String(producto.id)];
  const estrellas = resumen
    ? `<div class="estrellas">${'★'.repeat(Math.round(resumen.promedio))}${'☆'.repeat(5 - Math.round(resumen.promedio))} <span class="silencio">${resumen.promedio} · ${resumen.total}</span></div>`
    : '<div class="estrellas silencio">sin resenas</div>';

  return `
    <article class="producto ${producto.disponible ? '' : 'producto--agotado'}">
      <strong>${escapar(producto.nombre)}</strong>
      <span class="producto__precio">${quetzales(producto.precio)}</span>
      <span class="silencio" style="font-size:.85rem">${escapar(producto.descripcion)}</span>
      ${estrellas}
      <div class="producto__pie">
        ${
          producto.disponible
            ? `<input type="number" min="1" max="20" value="1" aria-label="Cantidad de ${escapar(producto.nombre)}" data-cantidad="${producto.id}">
               <button class="secundario" data-agregar="${producto.id}">Agregar</button>`
            : '<span class="estado estado--cancelado">agotado</span>'
        }
        ${
          esAdmin()
            ? `<button class="secundario" data-disponibilidad="${producto.id}" data-valor="${!producto.disponible}">
                 ${producto.disponible ? 'Agotar' : 'Reponer'}
               </button>`
            : ''
        }
      </div>
    </article>`;
}

function conectarBotonesDelMenu() {
  document.querySelectorAll('[data-agregar]').forEach((boton) => {
    boton.addEventListener('click', () => {
      const id = boton.dataset.agregar;
      const cantidad = Number(document.querySelector(`[data-cantidad="${id}"]`).value);
      const producto = estado.productos.find((p) => p.id === id);
      const actual = estado.carrito.get(id)?.cantidad ?? 0;
      estado.carrito.set(id, { producto, cantidad: actual + cantidad });
      pintarCarrito();
    });
  });

  document.querySelectorAll('[data-disponibilidad]').forEach((boton) => {
    boton.addEventListener('click', async () => {
      try {
        await api.catalogo(
          `mutation ($id: ID!, $disponible: Boolean!) {
             cambiarDisponibilidad(id: $id, disponible: $disponible) { id disponible }
           }`,
          { id: boton.dataset.disponibilidad, disponible: boton.dataset.valor === 'true' },
        );
        cargarMenu();
      } catch (error) {
        alert(error.detalle ?? error.message);
      }
    });
  });
}

function pintarCarrito() {
  const destino = $('#carrito');
  if (estado.carrito.size === 0) {
    destino.innerHTML = '<p class="silencio">Todavia no has elegido nada. Agrega algo del menu.</p>';
    $('#enviar-pedido').disabled = true;
    return;
  }

  const lineas = [...estado.carrito.values()];
  const total = lineas.reduce((suma, l) => suma + l.producto.precio * l.cantidad, 0);

  destino.innerHTML = `
    <table>
      <tbody>
        ${lineas
          .map(
            (l) => `<tr>
              <td>${escapar(l.producto.nombre)}</td>
              <td class="numero">x${l.cantidad}</td>
              <td class="numero">${quetzales(l.producto.precio * l.cantidad)}</td>
              <td><button class="secundario" data-quitar="${l.producto.id}">Quitar</button></td>
            </tr>`,
          )
          .join('')}
      </tbody>
    </table>
    <div class="linea-total"><span>Total</span><span>${quetzales(total)}</span></div>`;

  destino.querySelectorAll('[data-quitar]').forEach((boton) =>
    boton.addEventListener('click', () => {
      estado.carrito.delete(boton.dataset.quitar);
      pintarCarrito();
    }),
  );

  $('#enviar-pedido').disabled = false;
}

$('#enviar-pedido').addEventListener('click', async () => {
  const items = [...estado.carrito.values()].map((l) => ({ productoId: l.producto.id, cantidad: l.cantidad }));
  try {
    await api.crearPedido(items, $('#notas').value);
    estado.carrito.clear();
    $('#notas').value = '';
    pintarCarrito();
    activarVista('pedidos');
  } catch (error) {
    alert(error.detalle ?? error.message);
  }
});

// --------------------------------------------------------------- pedidos

async function cargarPedidos() {
  const destino = $('#pedidos');
  destino.innerHTML = '<p class="silencio">Cargando pedidos...</p>';

  try {
    const { pedidos } = await api.listarPedidos();
    if (pedidos.length === 0) {
      destino.innerHTML = '<p class="silencio">Aun no hay pedidos. Arma uno desde el menu.</p>';
      return;
    }

    destino.innerHTML = pedidos.map(tarjetaPedido).join('');

    destino.querySelectorAll('[data-estado]').forEach((selector) =>
      selector.addEventListener('change', async () => {
        try {
          await api.cambiarEstadoPedido(selector.dataset.estado, selector.value);
          cargarPedidos();
        } catch (error) {
          alert(error.detalle ?? error.message);
        }
      }),
    );
  } catch (error) {
    fallo(destino, error);
  }
}

const ESTADOS = ['recibido', 'preparando', 'listo', 'entregado', 'cancelado'];

function tarjetaPedido(pedido) {
  return `
    <div style="border:1px solid var(--linea);border-radius:3px;padding:14px;margin-bottom:12px">
      <div style="display:flex;gap:10px;align-items:center;flex-wrap:wrap">
        <span class="mono">#${pedido.id}</span>
        <span class="estado estado--${escapar(pedido.estado)}">${escapar(pedido.estado)}</span>
        ${esAdmin() ? `<span class="silencio">${escapar(pedido.usuarioNombre || pedido.usuarioId)}</span>` : ''}
        <span class="silencio mono" style="margin-left:auto">${new Date(pedido.creadoEn).toLocaleString('es-GT')}</span>
      </div>
      <table style="margin-top:10px">
        <tbody>
          ${pedido.items
            .map(
              (item) => `<tr>
                <td>${escapar(item.nombreProducto)}</td>
                <td class="numero">x${item.cantidad}</td>
                <td class="numero">${quetzales(item.subtotal)}</td>
              </tr>`,
            )
            .join('')}
        </tbody>
      </table>
      ${pedido.notas ? `<p class="silencio" style="font-size:.85rem">Nota: ${escapar(pedido.notas)}</p>` : ''}
      <div class="linea-total"><span>Total</span><span>${quetzales(pedido.total)}</span></div>
      ${
        esAdmin()
          ? `<label>Cambiar estado
               <select data-estado="${pedido.id}">
                 ${ESTADOS.map((e) => `<option value="${e}" ${e === pedido.estado ? 'selected' : ''}>${e}</option>`).join('')}
               </select>
             </label>`
          : ''
      }
    </div>`;
}

// --------------------------------------------------------------- resenas

async function cargarResenas() {
  const selector = $('#resena-producto');
  if (estado.productos.length === 0) await cargarMenu();

  selector.innerHTML = estado.productos
    .map((p) => `<option value="${p.id}">${escapar(p.nombre)}</option>`)
    .join('');

  const destino = $('#lista-resenas');
  destino.innerHTML = '<p class="silencio">Cargando resenas...</p>';

  try {
    const resenas = await api.listarResenas();
    if (resenas.length === 0) {
      destino.innerHTML = '<p class="silencio">Nadie ha opinado todavia. Se el primero.</p>';
      return;
    }

    const nombrePorId = Object.fromEntries(estado.productos.map((p) => [p.id, p.nombre]));

    destino.innerHTML = `
      <table>
        <thead>
          <tr><th>Producto</th><th>Persona</th><th>Nota</th><th>Comentario</th>${esAdmin() ? '<th></th>' : ''}</tr>
        </thead>
        <tbody>
          ${resenas
            .map(
              (r) => `<tr>
                <td>${escapar(nombrePorId[r.producto_id] ?? `#${r.producto_id}`)}</td>
                <td>${escapar(r.usuario_nombre || r.usuario_id)}</td>
                <td class="estrellas">${'★'.repeat(r.calificacion)}${'☆'.repeat(5 - r.calificacion)}</td>
                <td>${escapar(r.comentario)}</td>
                ${esAdmin() ? `<td><button class="secundario" data-borrar="${r.id}">Borrar</button></td>` : ''}
              </tr>`,
            )
            .join('')}
        </tbody>
      </table>`;

    destino.querySelectorAll('[data-borrar]').forEach((boton) =>
      boton.addEventListener('click', async () => {
        try {
          await api.eliminarResena(boton.dataset.borrar);
          cargarResenas();
        } catch (error) {
          alert(error.detalle ?? error.message);
        }
      }),
    );
  } catch (error) {
    fallo(destino, error);
  }
}

$('#form-resena').addEventListener('submit', async (evento) => {
  evento.preventDefault();
  const datos = new FormData(evento.target);
  try {
    await api.crearResena({
      producto_id: datos.get('producto_id'),
      calificacion: Number(datos.get('calificacion')),
      comentario: datos.get('comentario'),
    });
    evento.target.reset();
    cargarResenas();
  } catch (error) {
    alert(error.detalle ?? error.message);
  }
});

// ------------------------------------------------------------ inventario

const CONSULTA_INVENTARIO = `
  query { insumos { id nombre unidad existencia minimo bajoMinimo } }
`;

async function cargarInventario() {
  const destino = $('#inventario');
  destino.innerHTML = '<p class="silencio">Consultando bodega...</p>';

  try {
    const { insumos } = await api.inventario(CONSULTA_INVENTARIO);

    $('#movimiento-insumo').innerHTML = insumos
      .map((i) => `<option value="${i.id}">${escapar(i.nombre)}</option>`)
      .join('');

    destino.innerHTML = `
      <table>
        <thead><tr><th>Insumo</th><th>Existencia</th><th>Minimo</th><th>Estado</th></tr></thead>
        <tbody>
          ${insumos
            .map(
              (i) => `<tr>
                <td>${escapar(i.nombre)}</td>
                <td class="numero">${i.existencia} ${escapar(i.unidad)}</td>
                <td class="numero">${i.minimo}</td>
                <td>${i.bajoMinimo ? '<span class="estado estado--preparando">reponer</span>' : '<span class="estado">suficiente</span>'}</td>
              </tr>`,
            )
            .join('')}
        </tbody>
      </table>`;
  } catch (error) {
    fallo(destino, error);
  }
}

$('#form-movimiento').addEventListener('submit', async (evento) => {
  evento.preventDefault();
  const datos = new FormData(evento.target);
  try {
    await api.inventario(
      `mutation ($insumoId: ID!, $tipo: String!, $cantidad: Float!, $motivo: String!) {
         registrarMovimiento(insumoId: $insumoId, tipo: $tipo, cantidad: $cantidad, motivo: $motivo) {
           id nombre existencia bajoMinimo
         }
       }`,
      {
        insumoId: datos.get('insumo_id'),
        tipo: datos.get('tipo'),
        cantidad: Number(datos.get('cantidad')),
        motivo: datos.get('motivo') || '',
      },
    );
    evento.target.reset();
    cargarInventario();
  } catch (error) {
    alert(error.detalle ?? error.message);
  }
});

// --------------------------------------------------------------- sistema

async function cargarSistema() {
  const destino = $('#sistema');
  destino.innerHTML = '<p class="silencio">Sondeando servicios...</p>';

  const [salud, diagnostico] = await Promise.all([
    api.salud().catch((error) => ({ error })),
    api.diagnostico().catch((error) => ({ error })),
  ]);

  const filas = (salud.dependencias ?? []).map(
    (d) => `<tr>
      <td>${escapar(d.servicio)}</td>
      <td><span class="estado ${d.estado === 'arriba' ? '' : 'estado--cancelado'}">${escapar(d.estado)}</span></td>
      <td class="numero">${d.codigo ?? '—'}</td>
      <td class="numero">${d.ms} ms</td>
    </tr>`,
  );

  const permisos = diagnostico.permisos
    ? Object.entries(diagnostico.permisos)
        .map(
          ([permiso, permitido]) =>
            `<tr><td class="mono">${escapar(permiso)}</td>
             <td>${permitido ? '<span class="estado">permitido</span>' : '<span class="estado estado--cancelado">denegado</span>'}</td></tr>`,
        )
        .join('')
    : `<tr><td colspan="2" class="error">${escapar(diagnostico.error?.detalle ?? 'sin datos')}</td></tr>`;

  destino.innerHTML = `
    <h3>Servicios</h3>
    <table><thead><tr><th>Servicio</th><th>Estado</th><th>Codigo</th><th>Latencia</th></tr></thead>
    <tbody>${filas.join('') || `<tr><td colspan="4" class="error">${escapar(salud.error?.detalle ?? 'sin datos')}</td></tr>`}</tbody></table>
    <h3 style="margin-top:22px">Permisos de tu rol</h3>
    <p class="silencio" style="font-size:.85rem">Cada linea es una pregunta real al microservicio de autorizacion.</p>
    <table><tbody>${permisos}</tbody></table>`;
}

// --------------------------------------------------------------- arranque

$('#salir').addEventListener('click', async () => {
  await api.logout().catch(() => {});
  window.location.href = 'index.html';
});

(async function iniciar() {
  try {
    const yo = await api.yo();
    estado.usuario = {
      nombre: yo.nombre ?? yo.usuario?.nombre ?? yo.correo ?? 'Invitada',
      rol: String(yo.rol ?? yo.usuario?.rol ?? '').toLowerCase(),
    };
  } catch {
    window.location.href = 'index.html';
    return;
  }

  $('#nombre').textContent = estado.usuario.nombre;
  const insignia = $('#rol');
  insignia.textContent = estado.usuario.rol;
  insignia.className = `insignia insignia--${esAdmin() ? 'admin' : 'cliente'}`;

  if (!esAdmin()) {
    document.querySelector('[data-ir="inventario"]').title = 'Solo Admin: aqui veras un 403';
  }

  await cargarMenu();
  pintarCarrito();
  activarVista('menu');
})();
