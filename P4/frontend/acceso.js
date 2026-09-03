import { api, CAMPOS, ErrorApi } from './api.js';

const formularios = {
  login: document.querySelector('#form-login'),
  registro: document.querySelector('#form-registro'),
};
const aviso = document.querySelector('#aviso');

function mostrar(mensaje, tono = 'error') {
  aviso.textContent = mensaje;
  aviso.className = tono === 'ok' ? 'aviso aviso--ok' : 'aviso';
  aviso.hidden = false;
}

function limpiar() {
  aviso.hidden = true;
}

document.querySelectorAll('.pestanas button').forEach((boton) => {
  boton.addEventListener('click', () => {
    limpiar();
    document.querySelectorAll('.pestanas button').forEach((otro) => {
      otro.setAttribute('aria-selected', String(otro === boton));
    });
    formularios.login.hidden = boton.dataset.vista !== 'login';
    formularios.registro.hidden = boton.dataset.vista !== 'registro';
  });
});

formularios.login.addEventListener('submit', async (evento) => {
  evento.preventDefault();
  limpiar();
  const datos = new FormData(formularios.login);

  try {
    await api.login({
      [CAMPOS.login.correo]: datos.get('correo').trim(),
      [CAMPOS.login.password]: datos.get('password'),
    });
    window.location.href = 'panel.html';
  } catch (error) {
    mostrar(error instanceof ErrorApi ? error.detalle : 'No se pudo iniciar sesion.');
  }
});

formularios.registro.addEventListener('submit', async (evento) => {
  evento.preventDefault();
  limpiar();
  const datos = new FormData(formularios.registro);

  try {
    await api.registro({
      [CAMPOS.registro.nombre]: datos.get('nombre').trim(),
      [CAMPOS.registro.correo]: datos.get('correo').trim(),
      [CAMPOS.registro.password]: datos.get('password'),
      [CAMPOS.registro.rol]: datos.get('rol'),
    });
    window.location.href = 'panel.html';
  } catch (error) {
    mostrar(error instanceof ErrorApi ? error.detalle : 'No se pudo crear la cuenta.');
  }
});
