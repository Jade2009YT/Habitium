// Aplica el fondo guardado antes del primer pintado.
//
// Va en un archivo aparte, y no en línea dentro del HTML, por seguridad:
// así la Content-Security-Policy puede prohibir los scripts en línea por
// completo (`script-src` sin 'unsafe-inline'), que es lo que impide que
// un <script> inyectado se ejecute aunque consiga llegar al documento.
//
// Sin `defer` ni `async` a propósito: tiene que correr antes de que se
// pinte el primer píxel, o quien tenga "Noche" ve un fogonazo blanco.
(function () {
  try {
    document.documentElement.setAttribute(
      "data-bg",
      localStorage.getItem("habitium.bg") || "night"
    );
  } catch (e) {
    // Navegador con el almacenamiento bloqueado.
    document.documentElement.setAttribute("data-bg", "night");
  }
})();

/* ── El seguro contra la pantalla de carga eterna ──────────────────
 *
 * app.js es un módulo con imports estáticos, y uno de ellos viene de un
 * CDN de fuera. Si ese import no se resuelve —sin cobertura la primera
 * vez, el CDN caído, un bloqueador de anuncios agresivo— el módulo
 * ENTERO no se evalúa: no salta ningún error visible, no se ejecuta una
 * sola línea de la app, y la pantalla se queda en "Cargando…" para
 * siempre. Es el peor fallo posible porque parece que la app está rota
 * sin decir por qué.
 *
 * Esto vigila: si a los ocho segundos el arranque sigue puesto, es que
 * app.js nunca llegó a correr. Entonces lo dice y ofrece reintentar.
 *
 * Va aquí y no en app.js a propósito: tiene que ejecutarse aunque app.js
 * no llegue a existir. Y va en un archivo y no en línea porque la
 * Content-Security-Policy prohíbe los scripts en línea, que es lo que
 * impide que un <script> inyectado se ejecute. */
(function vigilarArranque() {
  var LIMITE_MS = 8000;

  setTimeout(function () {
    var boot = document.getElementById("boot");
    if (!boot || boot.hidden) return;   // la app arrancó, todo bien

    boot.innerHTML =
      '<div class="leaf" aria-hidden="true"></div>' +
      "<p><b>No se ha podido cargar del todo.</b></p>" +
      '<p class="boot-hint">Suele ser la conexión. La primera vez Habitium ' +
      "necesita internet para descargarse; después funciona sin él.</p>" +
      '<button id="boot-retry" class="btn btn-primary">Reintentar</button>';

    var boton = document.getElementById("boot-retry");
    if (boton) {
      boton.addEventListener("click", function () {
        location.reload();
      });
    }
  }, LIMITE_MS);
})();
