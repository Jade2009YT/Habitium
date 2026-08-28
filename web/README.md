# Habitium web

La misma cuenta y los mismos datos que la app de iPhone, pero desde
cualquier navegador — pensada para el iPad del cole (que solo permite
páginas web) y para cualquier Android sin tener que instalar nada.

Son **archivos estáticos**: HTML, CSS y un JS. No hay servidor propio ni
backend que mantener — la página habla directamente con Supabase desde el
navegador, igual que hace la app de iPhone.

## Puesta en marcha (2 minutos)

1. Copia `config.example.js` a `config.js`.
2. Abre `config.js` y pon tu **Project URL** y tu **anon key** de Supabase
   (supabase.com → tu proyecto → Project Settings → API).
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
2. Copia toda la carpeta `web/` (con tu `config.js` dentro) a la carpeta
   compartida `web` del NAS, o crea un *Virtual Host* apuntando a donde la
   hayas dejado.
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
- Inicio con las cuatro métricas del día (calorías, hábitos, próxima tarea,
  disponible del mes).
- Nutrición: registrar comidas con calorías y macros, ver las de hoy.
- Agenda: crear tareas con fecha, completarlas, borrarlas.
- Finanzas: registrar ingresos y gastos por categoría, ver los del mes.
- Hábitos: crear hábitos de sí/no o numéricos con objetivo, marcarlos y ver
  la racha — con la misma regla de racha que la app de iPhone.

**No, a propósito:**

- **No funciona sin conexión.** A diferencia de la app de iPhone (que
  guarda en local y sincroniza), la web lee y escribe directamente contra
  Postgres. Es mucho más simple, y el caso de uso que la motivó siempre
  tiene red.
- **No hay análisis de comidas con IA.** Eso necesitaría poner una clave
  de OpenAI/Anthropic en el navegador, donde cualquiera que abra la web
  podría leerla y gastarla a tu cuenta. Para hacerlo bien haría falta un
  proxy en tu servidor — pendiente, si algún día hace falta de verdad.
- **No hay medicación, entrenamientos ni widgets.** Están en el backlog;
  las tablas ya existen en Supabase, solo falta la interfaz.
- **No hay Face ID ni bloqueo de app.** La sesión del navegador es la única
  protección; cierra sesión si usas un dispositivo compartido (como el iPad
  del cole).

## Sobre la seguridad de la anon key

La `anon key` acaba siendo visible para cualquiera que abra la web. Es así
por diseño: va embebida en el cliente, igual que en la app de iPhone. Lo
que protege tus datos no es esconderla, sino el **Row Level Security** del
esquema — cada política exige `auth.uid() = user_id`, así que con esa clave
y sin iniciar sesión no se puede leer ni escribir nada.

La que **nunca** debe salir de Supabase es la **service_role key**: esa sí
se salta el RLS. No se usa en ningún sitio de este proyecto, y no debe
aparecer nunca en `config.js` ni en ningún archivo del repo.
