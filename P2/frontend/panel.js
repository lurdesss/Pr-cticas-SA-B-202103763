/**
 * Página de confirmación posterior al login (requisito 7).
 *
 * Además de mostrar los datos de la sesión, dibuja en vivo el estado del
 * token. El navegador no puede leer el token —es HTTP-only—, así que el
 * momento de emisión se deduce de cuándo el backend confirmó la sesión,
 * y se reinicia cada vez que una respuesta trae la cabecera
 * `X-Token-Renovado`.
 */

const bitacora = document.getElementById("bitacora");
let emitidoEn = null;

/** Añade una línea a la bitácora de peticiones. */
function anotar(texto, tipo = "") {
  if (bitacora.children.length === 1 && !bitacora.firstElementChild.className) {
    bitacora.innerHTML = "";
  }
  const linea = document.createElement("li");
  linea.className = tipo;
  linea.textContent = `${new Date().toLocaleTimeString()}  ${texto}`;
  bitacora.prepend(linea);
}

/** Reinicia el contador del ciclo de vida. */
function reiniciarCiclo() {
  emitidoEn = Date.now();
}

/** Dibuja las proporciones de las zonas válida y renovable una sola vez. */
function dibujarZonas() {
  const total = CONFIG_TOKEN.ttl + CONFIG_TOKEN.gracia;
  const porcentajeValido = (CONFIG_TOKEN.ttl / total) * 100;
  document.getElementById("zona-valido").style.width = `${porcentajeValido}%`;
  document.getElementById("zona-renovable").style.width = `${100 - porcentajeValido}%`;
}

/** Actualiza el estado mostrado. Se ejecuta cada segundo. */
function refrescarCiclo() {
  if (emitidoEn === null) return;

  const transcurrido = (Date.now() - emitidoEn) / 1000;
  const total = CONFIG_TOKEN.ttl + CONFIG_TOKEN.gracia;
  const etiqueta = document.getElementById("estado-token");

  let texto;
  let clase;

  if (transcurrido < CONFIG_TOKEN.ttl) {
    texto = `Válido · ${Math.ceil(CONFIG_TOKEN.ttl - transcurrido)} s restantes`;
    clase = "estado-valido";
  } else if (transcurrido < total) {
    texto = `Expirado · renovable ${Math.ceil(total - transcurrido)} s más`;
    clase = "estado-renovable";
  } else {
    texto = "Expirado · fuera de la ventana de gracia";
    clase = "estado-expirado";
  }

  etiqueta.textContent = texto;
  etiqueta.className = `estado-actual ${clase}`;

  const avance = Math.min(transcurrido / total, 1) * 100;
  document.getElementById("marcador").style.left = `${avance}%`;
}

/** Pinta los datos del usuario en la tarjeta de sesión. */
function pintarUsuario(usuario) {
  document.getElementById("saludo").textContent =
    `Hola, ${usuario.nombre}. Tu sesión está activa.`;
  document.getElementById("dato-nombre").textContent = usuario.nombre;
  document.getElementById("dato-correo").textContent = usuario.correo;
  document.getElementById("dato-rol").textContent = usuario.rol;
  document.getElementById("dato-id").textContent = usuario.id;
}

/** Registra el resultado de una petición y reinicia el ciclo si hubo renovación. */
function procesarRespuesta(nombre, resultado) {
  if (resultado.renovado) {
    reiniciarCiclo();
    anotar(`${nombre} → token renovado automáticamente`, "aviso");
  }

  if (resultado.ok) {
    anotar(`${nombre} → ${resultado.status} permitido`, "ok");
  } else {
    anotar(
      `${nombre} → ${resultado.status} ${describirError(resultado.status, resultado.datos)}`,
      "error"
    );
  }

  if (resultado.status === 401) {
    anotar("Sesión terminada. Redirigiendo al acceso…", "error");
    setTimeout(() => (window.location.href = "index.html"), 1800);
  }
}

async function probarRuta(nombre, llamada) {
  procesarRespuesta(nombre, await llamada());
}

document.getElementById("btn-ruta1").addEventListener("click", () => {
  probarRuta("Ruta 1 (solo Admin)", api.ruta1);
});

document.getElementById("btn-ruta2").addEventListener("click", () => {
  probarRuta("Ruta 2 (compartida)", api.ruta2);
});

document.getElementById("btn-salir").addEventListener("click", async () => {
  await api.logout();
  window.location.href = "index.html";
});

/** Arranque: confirma la sesión antes de mostrar nada. */
(async function iniciar() {
  dibujarZonas();

  const resultado = await api.yo();
  if (!resultado.ok) {
    window.location.href = "index.html";
    return;
  }

  pintarUsuario(resultado.datos);
  reiniciarCiclo();
  anotar("Sesión confirmada por el servidor", "ok");

  setInterval(refrescarCiclo, 1000);
  refrescarCiclo();
})();
