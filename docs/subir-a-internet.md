# Subir Habitium a internet y ponerla en la pantalla de inicio

Sí, se puede, y la app está construida para eso desde el principio:
manifest, service worker, iconos y base de datos local. Una vez subida,
la añades a la pantalla de inicio del iPhone y **se comporta como una
app**: icono propio, sin barra de Safari, pantalla completa, y funciona
sin cobertura.

Esta guía tiene los pasos y, al final, **lo que pierdes** respecto a la
app nativa de Xcode. Eso es lo que hay que leer antes de decidir.

---

## Lo que necesitas

- Una carpeta `web/` (ya la tienes).
- **HTTPS obligatorio.** Sin certificado no hay service worker, no hay
  modo sin conexión y no hay notificaciones. Todas las opciones de abajo
  lo dan gratis y automático.
- Cinco minutos.

---

## Paso 1 — Descarga supabase-js al proyecto

**Esto no es opcional.** La app importa la librería de Supabase, y si la
carga de un CDN de fuera, la primera vez que la abras sin cobertura se
queda en blanco. Con la copia local, Habitium no depende de ninguna red
ajena.

En tu Mac, desde la raíz del repositorio:

```bash
mkdir -p web/vendor
curl -o web/vendor/supabase.js \
  "https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.58.0/+esm"
```

No hay que tocar ningún archivo más: `app.js` prueba primero la copia
local y solo va al CDN si no la encuentra.

Comprueba que pesa algo de verdad (unos 100 KB):

```bash
ls -lh web/vendor/supabase.js
```

## Paso 2 — Crea `web/config.js`

**Este archivo está en `.gitignore` a propósito**, así que no está en el
repositorio y hay que crearlo a mano en el servidor:

```js
window.HABITIUM_CONFIG = {
  SUPABASE_URL: "https://TU-PROYECTO.supabase.co",
  SUPABASE_ANON_KEY: "tu-clave-anon-publica",
};
```

Los dos valores salen de Supabase → tu proyecto → Settings → API.

Usa **la clave `anon` / publishable**, nunca la `service_role`. La anon
es pública por diseño: lo que protege tus datos es Row Level Security,
no que esa clave sea secreta. La `service_role` se salta RLS entera y
**no debe salir nunca de Supabase**.

## Paso 3 — Súbelo

### Opción A — Cloudflare Pages (lo más fácil, gratis)

1. Entra en [dash.cloudflare.com](https://dash.cloudflare.com) →
   **Workers & Pages** → **Create** → **Pages** → **Upload assets**.
2. Arrastra la carpeta `web/` entera.
3. Te da una dirección tipo `habitium.pages.dev`, ya con HTTPS.

Para actualizar: vuelves a subir la carpeta. Todos los que la tengan
instalada reciben la versión nueva al abrirla.

### Opción B — Netlify (igual de fácil)

[app.netlify.com/drop](https://app.netlify.com/drop) y arrastras la
carpeta `web/`. Te da una dirección con HTTPS al momento.

### Opción C — Tu Synology

Ya tienes las cabeceras preparadas en `web/seguridad-cabeceras.conf`,
con las instrucciones para DSM. Necesitas además:

- Un certificado (Let's Encrypt, gratis desde DSM).
- Acceso desde fuera de casa: DDNS + abrir el puerto 443, o Tailscale.

Es la opción con más control y la que más trabajo da.

## Paso 4 — Las cabeceras de seguridad

Tres protecciones solo funcionan como cabecera HTTP, no dentro del HTML:
antiframe, HSTS y `nosniff`.

En **Cloudflare Pages o Netlify**, crea un archivo llamado `_headers`
(sin extensión) dentro de `web/`:

```
/*
  X-Content-Type-Options: nosniff
  X-Frame-Options: DENY
  Referrer-Policy: strict-origin-when-cross-origin
  Permissions-Policy: camera=(self), microphone=(), geolocation=()
  Content-Security-Policy: frame-ancestors 'none'
  Strict-Transport-Security: max-age=31536000; includeSubDomains
```

En **Synology**, usa `web/seguridad-cabeceras.conf`, que ya lo explica.

## Paso 5 — Instálala en el iPhone

1. Abre la dirección **en Safari** (en Chrome no sale la opción).
2. Botón de compartir (el cuadrado con la flecha).
3. **Añadir a pantalla de inicio**.
4. Ábrela desde el icono, **no desde Safari**. Es importante: solo así
   tiene pantalla completa y notificaciones.

En **Android** es igual: Chrome → menú de tres puntos → *Añadir a
pantalla de inicio* (o *Instalar aplicación*).

## Paso 6 — Cierra el registro

Con la app en internet, cualquiera con la dirección podría crearse una
cuenta. En el SQL Editor de Supabase:

```sql
-- Solo entra quien tú invites
update public.signup_control set mode = 'invitacion';

-- Invítate a ti
insert into public.allowed_signups (email, note)
values ('tu@correo.com', 'yo');
```

Más detalles en el README, sección *Segunda ronda de seguridad*.

---

## Lo que pierdes respecto a la app de Xcode

Esto es lo importante. Sé honesto contigo mismo sobre cuánto te importa
cada punto:

| | PWA (subida a web) | App nativa (Xcode) |
|---|---|---|
| Caduca a los 7 días | **No** | Sí, con cuenta gratuita |
| Necesita Mac y Xcode | **No** | Sí |
| Actualizar a todos | **Subes y ya** | Reinstalar en cada móvil |
| Funciona en Android | **Sí** | No |
| Pasarlo a un amigo | **Un enlace** | Muy complicado |
| Sin conexión | Sí | Sí |
| Cámara para fotos de comida | Sí | Sí |
| **Avisos con la app cerrada** | **No** ⚠️ | Sí |
| Apple Watch | No | Sí (con cuenta de pago) |
| Atajos, Siri, botón de Acción | No | Sí |
| Widgets | No | Sí |

### El punto que de verdad duele: los avisos de las rutinas

En la app nativa, los avisos de "levántate / dúchate / dientes" los
entrega iOS aunque la app esté cerrada y el móvil bloqueado. Eso es lo
que hace que una rutina de mañana funcione.

En la PWA **no**, y no es un fallo de Habitium: la API que programaba
notificaciones diferidas en el navegador se probó en Chrome y se retiró.
No existe en ninguno.

Lo que sí hace la PWA (ver `web/avisos.js`):

- Los avisos saltan **mientras Habitium esté abierta**, aunque sea de
  fondo. Para una rutina de mañana con el móvil en la mesilla, funciona
  más veces de lo que parece.
- Al volver a abrirla, te recuerda **una sola vez** el aviso que se te
  acaba de pasar, si fue hace menos de diez minutos.
- Y la pantalla lo dice tal cual, en vez de disimularlo.

**Se puede arreglar del todo**, pero hace falta un servidor que empuje
las notificaciones (Web Push con claves VAPID). Con Supabase Edge
Functions + `pg_cron` es factible y entra en el plan gratuito. Es la
siguiente pieza si decides quedarte con la web.

### Y lo del gasto de Apple Pay

El atajo de Atajos que pregunta el importe al cerrar Wallet
(`docs/apple-pay-atajo.md`) **solo funciona con la app nativa**: los
App Intents son de la app, no de la web.

En la PWA queda el campo rápido de Finanzas: escribes `4,20 bocadillo` y
listo. Con la app en la pantalla de inicio son dos toques.

---

## Mi recomendación

**Sube la web.** Te quita de encima el problema del certificado que
caduca cada 7 días, funciona en Android, se lo puedes pasar a quien
quieras, y se actualiza sola. Para el 90% de lo que hace Habitium es
igual de buena.

Y si luego echas de menos los avisos con la app cerrada, hay dos
caminos, en este orden:

1. **Web Push con Supabase.** Arregla los avisos sin renunciar a nada de
   lo demás.
2. **Las dos cosas a la vez.** La misma cuenta, los mismos datos: usas
   la app nativa en tu iPhone (avisos, Watch, atajos) y la web en el
   iPad del instituto o en el ordenador. Ya sincronizan.
