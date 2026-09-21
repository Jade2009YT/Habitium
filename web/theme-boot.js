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
