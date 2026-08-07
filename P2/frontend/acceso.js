/** Lógica de la pantalla de acceso: alternar pestañas, registrar e iniciar sesión. */

const mensaje = document.getElementById("mensaje");

function mostrar(texto, tipo = "error") {
  mensaje.innerHTML = `<div class="alerta ${tipo}">${texto}</div>`;
}

/** Alterna entre los paneles de login y registro. */
document.querySelectorAll('[role="tab"]').forEach((pestana) => {
  pestana.addEventListener("click", () => {
    document.querySelectorAll('[role="tab"]').forEach((otra) => {
      const activa = otra === pestana;
      otra.setAttribute("aria-selected", String(activa));
      document.getElementById(otra.dataset.panel).classList.toggle("oculto", !activa);
    });
    mensaje.innerHTML = "";
  });
});

function valor(id) {
  return document.getElementById(id).value.trim();
}

async function entrar(promesa) {
  const { ok, status, datos } = await promesa;
  if (!ok) {
    mostrar(describirError(status, datos));
    return;
  }
  // El backend ya dejó la cookie puesta; solo queda ir a la confirmación.
  window.location.href = "panel.html";
}

document.getElementById("btn-login").addEventListener("click", () => {
  entrar(api.login({ correo: valor("login-correo"), password: valor("login-password") }));
});

document.getElementById("btn-registro").addEventListener("click", () => {
  entrar(
    api.registro({
      nombre: valor("reg-nombre"),
      correo: valor("reg-correo"),
      password: valor("reg-password"),
      rol: document.getElementById("reg-rol").value,
    })
  );
});

/** Enter envía el formulario visible. */
document.addEventListener("keydown", (evento) => {
  if (evento.key !== "Enter") return;
  const panelLoginVisible = !document
    .getElementById("panel-login")
    .classList.contains("oculto");
  document.getElementById(panelLoginVisible ? "btn-login" : "btn-registro").click();
});
