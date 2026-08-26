# Supabase — base de datos en la nube

Esto es la "Fase 2" de Habitium: pasar de guardar todo solo en el iPhone a
que cada cuenta tenga sus datos en la nube, para que te funcione igual en
el iPhone, la futura app de Android y el iPad del cole (navegador).

## Cómo aplicar el esquema

1. Entra en [supabase.com](https://supabase.com) → tu proyecto (el mismo
   que ya usas para el login por email — mismo `SUPABASE_URL_HOST` /
   `SUPABASE_ANON_KEY` de `Configuration/Secrets.xcconfig`).
2. Menú lateral → **SQL Editor** → **New query**.
3. Copia y pega el contenido entero de [`schema.sql`](./schema.sql).
4. **Run**.

Es idempotente: si más adelante añado una tabla nueva o cambio una
política, puedes volver a pegar el archivo entero y ejecutarlo sin miedo a
romper lo que ya había.

## Qué NO sincroniza a propósito

- **Fotos de las comidas** (`FoodEntry.imageData`): se quedan solo en el
  dispositivo que las tomó. Subir fotos necesitaría Supabase Storage
  (bucket aparte, más coste, más complejidad) — de momento solo viaja el
  dato nutricional de la comida (nombre, calorías, macros), no la imagen.
- **Identificadores de notificaciones locales**
  (`notificationIdentifier(s)`): cada dispositivo programa y cancela sus
  propias notificaciones locales — no tiene sentido que un id de
  notificación de tu iPhone signifique algo en tu Android.
- **Claves de IA** (OpenAI/Anthropic): siguen siendo una clave por
  instalación, configurada en `Secrets.xcconfig` (o su equivalente en
  Android) — nunca en una tabla de Postgres en texto plano.

## Cómo se resuelven los conflictos entre dispositivos

Cada tabla tiene `updated_at` — pero, a propósito, **ningún trigger de
servidor lo toca**. Lo pone siempre el dispositivo que hizo el cambio real
(cada repositorio en Swift lo actualiza en el momento exacto de la
edición, no en el momento de sincronizar). La regla de sincronización
(`CloudSyncService`) es "gana el más reciente": al fusionar una fila que
existe tanto en local como en la nube, se queda la que tenga `updated_at`
más nuevo. No hay fusión de campos sueltos dentro de una misma fila — si
se edita el mismo registro casi a la vez desde dos dispositivos, gana el
que escribió último, igual que ya hacía `WatchConnectivityBridge` con
`updateApplicationContext` entre iPhone y Watch.

Por qué importa que sea el cliente y no un trigger: `CloudSyncService`
sube TODAS las filas en cada sincronización, no solo las que cambiaron de
verdad. Si un trigger de servidor pusiera `updated_at = now()` en cada
`UPDATE`, ese re-envío rutinario (sin cambios reales) haría parecer la
fila "más reciente" que una edición genuina hecha en otro dispositivo
hace un minuto, y esa edición real se perdería al fusionar. Confiar solo
en el timestamp que decide el cliente evita ese escenario.

## Seguridad

Row Level Security está activado en todas las tablas: cada política
comprueba `auth.uid() = user_id`, así que aunque la `anon key` es pública
(va embebida en la app, como toca), un usuario autenticado solo puede
leer y escribir sus propias filas — nunca las de otra cuenta.
