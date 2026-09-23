# Montar Habitium: la web en el Synology, los datos en Supabase

Dos sitios, cada uno haciendo lo que se le da bien:

- **Supabase** guarda los datos y lleva el login. Ya lo tienes montado;
  aquí van los cuatro ajustes que faltan para que funcione fuera de tu
  ordenador.
- **El Synology** sirve los archivos de la web. Es lo único que hace, y
  para eso vale cualquier NAS.

Tiempo: una hora la primera vez, sobre todo por el certificado.

---

# Parte 1 — Supabase

## 1.1 Aplica el esquema

Supabase → tu proyecto → **SQL Editor** → pega **`supabase/schema.sql`**
entero → **Run**.

Es idempotente: puedes volver a ejecutarlo cuantas veces quieras. Si ya
lo hiciste antes de las rutinas, **hazlo otra vez**, porque hay tablas
nuevas.

## 1.2 Las URL de redirección ⚠️

**Este es el paso que se olvida todo el mundo y rompe el login.**

Cuando alguien crea una cuenta o pide recuperar la contraseña, Supabase
le manda un correo con un enlace. Ese enlace apunta a la dirección que
tengas configurada aquí. Si no la cambias, apunta a `localhost:3000` y
al pulsarlo **no pasa nada**.

Supabase → **Authentication** → **URL Configuration**:

| Campo | Qué poner |
|---|---|
| **Site URL** | `https://TU-DOMINIO.synology.me` |
| **Redirect URLs** | `https://TU-DOMINIO.synology.me/**` |

Los dos asteriscos del final importan: autorizan cualquier ruta dentro
de tu dominio.

Si vas a usar la app también desde la red local, añade una segunda línea
en Redirect URLs con la IP:

```
https://TU-DOMINIO.synology.me/**
http://192.168.1.50/**
```

(Cambia la IP por la de tu NAS. Sale en DSM → Panel de control → Red.)

## 1.3 Copia la URL y la clave

Supabase → **Settings** → **API**. Necesitas dos cosas:

- **Project URL** — algo como `https://abcdefgh.supabase.co`
- **anon / public key** — una cadena larga que empieza por `eyJ...`

⚠️ **Usa la `anon`, nunca la `service_role`.** La anon es pública por
diseño: lo que protege tus datos es Row Level Security, no que esa clave
sea secreta. La `service_role` se salta RLS entera y no debe salir nunca
de Supabase — si acaba en el NAS, cualquiera que mire el código fuente
de la página tiene acceso total a todo.

## 1.4 Cierra el registro

Con la app en internet, cualquiera con la dirección podría crearse una
cuenta. En el **SQL Editor**:

```sql
-- Solo entra quien tú invites
update public.signup_control set mode = 'invitacion';

-- Invítate a ti
insert into public.allowed_signups (email, note)
values ('tu@correo.com', 'yo');
```

Para invitar a alguien más, otra línea igual con su correo. O un código
para varios:

```sql
insert into public.allowed_signups (code, max_uses, expires_at, note)
values ('HABITIUM-2026', 10, now() + interval '7 days', 'Clase');
```

Y si algún día alguien se pone a crear cuentas en masa, el botón de
pánico:

```sql
update public.signup_control set mode = 'cerrado';
```

## 1.5 Comprueba que está todo

SQL Editor → pega **`supabase/comprobar-seguridad.sql`** → Run. No
cambia nada: mira y contesta con ✓ o ✗. Tiene que salir todo ✓.

---

# Parte 2 — El Synology

## 2.0 Antes de empezar: mira qué NAS tienes

**DSM → Panel de control → Información del sistema.** Apunta el modelo,
la RAM y la versión de DSM.

Si es un modelo antiguo con **DSM 6.2**, ten en cuenta que esa versión
ya no recibe parches de seguridad. Servir archivos estáticos es lo menos
arriesgado que puedes hacer con un NAS —no hay base de datos ni PHP de
por medio— pero abrir el puerto 443 a internet con un sistema sin
actualizar es una decisión, no un trámite. Al final de esta guía hay una
alternativa que no abre ningún puerto.

## 2.1 Prepara la carpeta

En tu Mac, desde la raíz del repositorio:

```bash
# 1. La copia local de supabase-js. NO es opcional: sin ella, la primera
#    vez que abras la app sin cobertura se queda en blanco.
mkdir -p web/vendor
curl -o web/vendor/supabase.js \
  "https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.58.0/+esm"

# 2. Comprueba que pesa algo de verdad (unos 100 KB)
ls -lh web/vendor/supabase.js
```

Y crea **`web/config.js`** con lo que copiaste en el paso 1.3:

```js
window.HABITIUM_CONFIG = {
  SUPABASE_URL: "https://abcdefgh.supabase.co",
  SUPABASE_ANON_KEY: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
};
```

Ese archivo está en `.gitignore` a propósito: es tuyo y no va al
repositorio.

## 2.2 Instala Web Station

**Centro de paquetes** → busca **Web Station** → Instalar.

Al instalarlo crea una carpeta compartida llamada `web`.

### Elige Apache como servidor

Web Station → **General Settings** → **HTTP back-end server** →
**Apache HTTP Server 2.4**.

Con Nginx también funciona, pero entonces el archivo `.htaccess` se
ignora y hay que poner las cabeceras a mano (paso 2.6).

## 2.3 Copia los archivos

Desde tu Mac, con **Finder → Ir → Conectarse al servidor**
(`smb://IP-DE-TU-NAS`), abre la carpeta compartida `web` y copia dentro
**todo el contenido de `web/`**, no la carpeta:

```
web/
├── index.html          ← tiene que quedar en la raíz
├── app.js
├── styles.css
├── sw.js
├── config.js           ← el que acabas de crear
├── manifest.json
├── icon.png
├── .htaccess           ← empieza por punto: el Finder lo oculta
├── vendor/
│   └── supabase.js
└── … el resto de .js
```

**El `.htaccess` empieza por punto, así que el Finder no lo enseña.** Para
verlo: `Cmd + Shift + .` (punto). Si no lo copias, la app funciona pero
sin las cabeceras de seguridad ni la compresión.

Desde la terminal es más fiable:

```bash
rsync -av --delete web/ /Volumes/web/
```

## 2.4 Dominio y certificado

Sin HTTPS **no hay service worker, no hay modo sin conexión y no hay
instalación en la pantalla de inicio**. No es opcional.

### DDNS (un nombre para tu casa)

**Panel de control** → **Acceso externo** → **DDNS** → **Añadir**:

- Proveedor: **Synology**
- Nombre de host: el que quieras → `loquesea.synology.me`
- Marca **Obtener certificado de Let's Encrypt** si te lo ofrece

### Abre los puertos en el router

En tu router, redirige hacia la IP del NAS:

- **80** → NAS puerto 80 (lo necesita Let's Encrypt para verificar)
- **443** → NAS puerto 443

Cada router lo llama de una forma: *Port Forwarding*, *Redirección de
puertos*, *Servidores virtuales*.

### El certificado

**Panel de control** → **Seguridad** → **Certificado** → **Añadir** →
**Obtener un certificado de Let's Encrypt**:

- Nombre de dominio: `loquesea.synology.me`
- Correo: el tuyo

Si falla, casi siempre es que el puerto 80 no llega. Compruébalo desde
fuera de casa (con los datos del móvil, no con la wifi).

Luego, en **Certificado → Configurar**, asigna ese certificado a **Web
Station**.

## 2.5 Pruébalo

Abre `https://loquesea.synology.me` en el ordenador. Tiene que salir la
pantalla de login de Habitium con el candado cerrado en la barra.

### Tres comprobaciones que vale la pena hacer

Abre las herramientas de desarrollo (F12):

1. **Consola** — no debería haber errores en rojo.
2. **Application → Service Workers** — tiene que poner *activated and is
   running*.
3. **Application → Manifest** — tiene que salir "Habitium" con su icono.
   Si sale vacío o da error, el servidor está sirviendo mal el
   `manifest.json`: revisa que copiaste el `.htaccess`.

Y la prueba de fuego: **pon el móvil en modo avión y abre la app**. Si
carga, está bien montada.

## 2.6 Si usaste Nginx en vez de Apache

El `.htaccess` se ignora. Pon las cabeceras aquí:

**Panel de control** → **Portal de inicio de sesión** → **Avanzado** →
**Cabecera HTTP personalizada** → Crear, una entrada por línea:

| Nombre | Valor |
|---|---|
| `X-Content-Type-Options` | `nosniff` |
| `X-Frame-Options` | `DENY` |
| `Referrer-Policy` | `strict-origin-when-cross-origin` |
| `Content-Security-Policy` | `frame-ancestors 'none'` |

El detalle completo está en `web/seguridad-cabeceras.conf`.

## 2.7 Instálala en el iPhone

1. Abre `https://loquesea.synology.me` **en Safari** (en Chrome no sale
   la opción).
2. Botón de compartir → **Añadir a pantalla de inicio**.
3. Ábrela **desde el icono**, no desde Safari. Solo así tiene pantalla
   completa.

En **Android**: Chrome → menú de tres puntos → *Instalar aplicación*.

---

# Si no quieres abrir puertos

Abrir el 443 de casa a internet expone tu red. Hay una alternativa que
no abre ninguno: **Tailscale**.

1. Centro de paquetes del Synology → **Tailscale** → Instalar.
2. Instala Tailscale también en el iPhone (App Store, gratis).
3. Los dos con la misma cuenta.
4. Entras por la dirección que te dé Tailscale, esté donde estés.

Pegas: hay que tener Tailscale activo en el móvil, y no puedes pasarle
la app a un amigo así como así. Ventaja: nadie de fuera puede ni ver que
tu NAS existe.

---

# Para actualizar la app más adelante

```bash
git pull
rsync -av --delete --exclude=config.js --exclude=vendor web/ /Volumes/web/
```

El `--exclude` protege tu `config.js` y la copia de supabase-js, que no
están en el repositorio.

Todos los que tengan la app instalada reciben la versión nueva al
abrirla: el service worker la detecta solo. Si alguien se queda con la
vieja, que cierre la app del todo y la vuelva a abrir.

---

# Cuando algo no funciona

| Qué ves | Qué suele ser |
|---|---|
| "Cargando…" y no pasa de ahí | Falta `config.js`, o `vendor/supabase.js` no se copió. A los 8 s la app te lo dice. |
| El login no funciona, el correo no llega | Las URL de redirección de Supabase (paso 1.2). |
| Se instala pero se abre dentro de Safari | El `manifest.json` no se sirve bien, o falta el `.htaccess`. |
| No hay modo sin conexión | No hay HTTPS, o el service worker no se registró. |
| "Ese correo no está invitado" | Está en modo invitación y no te has añadido (paso 1.4). |
| Va lento al cargar la primera vez | Normal en un NAS antiguo. La segunda vez va de la caché y es instantáneo. |
