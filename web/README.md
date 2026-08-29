# Habitium web

La misma cuenta y los mismos datos que la app de iPhone, pero desde
cualquier navegador — pensada para el iPad del cole (que solo permite
páginas web) y para cualquier Android sin tener que instalar nada.

Son **archivos estáticos**: HTML, CSS y un JS. No hay servidor propio ni
backend que mantener — la página habla directamente con Supabase desde el
navegador, igual que hace la app de iPhone.

## Puesta en marcha (2 minutos)

1. Copia `config.example.js` a `config.js`.
2. Abre `config.js` y pon tu **Project URL** (la raíz, sin `/rest/v1` al
   final) y tu **clave pública** de Supabase — según cuándo creases el
   proyecto aparece como `anon / public` (empieza por `eyJ...`) o, en el
   formato nuevo, como `publishable` (empieza por `sb_publishable_`).
   Las dos sirven. Están en supabase.com → tu proyecto → Project
   Settings → API.
3. Asegúrate de haber aplicado ya `../supabase/schema.sql` en el SQL Editor
   de Supabase (ver `../supabase/README.md`).

`config.js` está en `.gitignore`, así que tus claves no se suben al repo.

## Probarla en tu Mac antes de publicarla

No basta con abrir `index.html` haciendo doble clic: los módulos de
JavaScript no funcionan desde `file://`. Levanta un servidor local:

```
cd web
python3 -m http.server 8000
```

Y abre <http://localhost:8000> en el navegador.

## Publicarla en tu Synology

1. **Centro de Paquetes** → instala **Web Station** (si no lo tienes).
2. Copia el **contenido** de la carpeta `web/` (con tu `config.js`
   dentro) a la carpeta compartida `web` del NAS — `index.html` tiene que
   quedar directamente ahí, no dentro de otra subcarpeta.
3. **Panel de Control → Seguridad → Certificado**: consigue un certificado
   gratuito de Let's Encrypt para tu dominio de Synology
   (`loquesea.synology.me`). **Esto no es opcional**: sin `https://`, los
   navegadores modernos bloquean parte de lo que la página necesita, y el
   iPad del cole probablemente ni la abra.
4. Entra desde el navegador a tu dominio y comprueba que carga.

**Antes de contar con que funcione desde fuera de casa**, comprueba dos
cosas que no dependen de este código:

- **Que tu NAS sea accesible desde internet.** Si tu router no reenvía los
  puertos hacia el NAS, o tu operador usa CGNAT (bastante común en fibra
  doméstica), el dominio resuelve pero nadie de fuera llega. La alternativa
  de Synology que evita abrir puertos es **QuickConnect**.
- **Que la red del cole no la bloquee.** Muchos centros filtran por listas
  de dominios permitidos, no solo por tipo de contenido. Eso solo se sabe
  probándolo allí.

Y ten en cuenta que **si el NAS se apaga, la web deja de estar disponible**.

## Instalarla como app

En el iPad o el Android, abre la web y usa **Compartir → Añadir a pantalla
de inicio**. Se abre a pantalla completa, sin barra del navegador, con su
propio icono. No es una app nativa, pero se comporta casi igual.

## Qué hace y qué no

**Sí:**

- Registro e inicio de sesión por email (Supabase Auth), con verificación
  de correo y recuperación de contraseña.
- **Inicio**: anillo de calorías con macros, hábitos cumplidos, presupuesto
  disponible, próxima tarea y próxima toma de medicación.
- **Nutrición**: registrar comidas con calorías y macros, ver las de hoy.
- **Agenda**: crear tareas con fecha, completarlas, borrarlas (marca las
  vencidas).
- **Finanzas**: ingresos/gastos por categoría, resumen del mes y desglose
  visual por categoría.
- **Hábitos**: de sí/no o numéricos con objetivo, plantillas rápidas,
  marcado diario y racha — con la misma regla de racha que la app de iPhone.
- **Medicación**: medicamentos con varios horarios al día y marcado de las
  tomas de hoy.
- **Ajustes**: objetivo de calorías y macros, presupuesto mensual, ahorro y
  moneda. Sin esto, Inicio se quedaría con los valores por defecto para
  siempre.

La interfaz se adapta: barra lateral en pantalla grande, pestañas abajo en
el móvil. En el móvil las pestañas son las cinco principales (las mismas
que en iOS); Medicación y Ajustes se alcanzan desde las tarjetas de Inicio
o desde el escritorio.

- **Funciona sin conexión.** Igual que la app de iPhone: los datos se
  guardan en el propio dispositivo (IndexedDB) y la nube es la copia que
  los mantiene iguales en todos lados. Ver "Cómo funcionan los datos".

**No, a propósito:**

- **No hay análisis de comidas con IA.** Eso necesitaría poner una clave
  de OpenAI/Anthropic en el navegador, donde cualquiera que abra la web
  podría leerla y gastarla a tu cuenta. Para hacerlo bien haría falta un
  proxy en tu servidor — pendiente, si algún día hace falta de verdad.
- **No hay medicación, entrenamientos ni widgets.** Están en el backlog;
  las tablas ya existen en Supabase, solo falta la interfaz.
- **No hay Face ID ni bloqueo de app.** La sesión del navegador es la única
  protección; cierra sesión si usas un dispositivo compartido (como el iPad
  del cole).

## Cómo funcionan los datos

Misma arquitectura que la app de iPhone, y por las mismas razones:

- **Lo local manda.** Todo se guarda en el propio dispositivo
  (IndexedDB, vía `store.js`). La interfaz nunca espera a la red: pinta
  al instante y sincroniza por detrás. Por eso la app abre rápido y sigue
  funcionando en el metro, en el cole, o si tu NAS está apagado.
- **La nube es la copia que iguala los dispositivos.** Al recuperar la
  conexión, los cambios pendientes suben en orden y se baja lo que hayas
  hecho en otro sitio.
- **Gana el más reciente.** Si editas lo mismo en dos dispositivos casi a
  la vez, se queda el cambio más nuevo (por `updated_at`, que pone el
  dispositivo que hizo la edición, nunca el servidor). No hay fusión
  campo a campo — igual que en iOS.
- **Los borrados se propagan.** Se encolan como una operación más, así
  que lo que borras no reaparece en la siguiente sincronización.
- **Al cerrar sesión se borra la copia local**, para que en un
  dispositivo compartido (el iPad del cole) tus datos no queden a la
  vista del siguiente que entre. Si tenías cambios sin subir, cierra
  sesión con conexión para no perderlos.

Arriba verás un aviso cuando estés sin conexión o queden cambios por
subir, para que sepas siempre en qué estado estás.

El **service worker** (`sw.js`) guarda los archivos de la app (no los
datos) para que arranque al instante y siga abriendo sin red. Cuando
subas una versión nueva al NAS, incrementa `CACHE_VERSION` dentro de
`sw.js` — así se limpian las cachés antiguas y todos cogen la nueva.

## Sobre la seguridad de la clave pública

La clave pública (`anon` / `publishable`) acaba siendo visible para
cualquiera que abra la web. Es así por diseño: va embebida en el cliente,
igual que en la app de iPhone. Lo que protege tus datos no es esconderla,
sino el **Row Level Security** del esquema — cada política exige
`auth.uid() = user_id`, así que con esa clave y sin iniciar sesión no se
puede leer ni escribir nada.

La que **nunca** debe salir de Supabase es la otra: la marcada como
`service_role` / `secret` (empieza por `sb_secret_` en el formato nuevo).
Esa sí se salta el RLS. No se usa en ningún sitio de este proyecto, y no
debe aparecer nunca en `config.js` ni en ningún archivo del repo.
