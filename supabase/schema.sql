-- Habitium — esquema de la nube (Supabase Postgres)
--
-- Hasta ahora Habitium guardaba todo SOLO en el dispositivo (SwiftData +
-- cifrado local). Este esquema es el punto de partida de la "Fase 2":
-- cada cuenta (Supabase Auth) tiene sus datos aquí, para que el mismo
-- usuario vea lo mismo desde el iPhone, la futura app de Android y el
-- iPad del cole (navegador). El iPhone seguirá teniendo una copia local
-- cifrada como caché rápido/offline — ver CloudSyncService (próxima
-- ronda) — pero el origen de verdad pasa a ser esta base de datos.
--
-- Cómo aplicar esto: Supabase Dashboard → tu proyecto → SQL Editor →
-- pega este archivo entero → Run. Es idempotente (CREATE TABLE IF NOT
-- EXISTS + políticas con DROP POLICY IF EXISTS antes de crearlas), así
-- que se puede volver a ejecutar sin miedo si se añade algo más adelante.
--
-- Reglas de diseño, para que cuadre con lo que ya hay en Swift:
--   1. Cada tabla tiene `user_id uuid` que apunta a auth.users(id) y
--      arranca en auth.uid() por defecto — así un INSERT normal sin
--      especificar user_id ya queda bien asignado al usuario logueado.
--   2. Row Level Security SIEMPRE activado: cada política solo deja
--      leer/escribir las filas cuyo user_id sea el tuyo. Nadie ve datos
--      de otra cuenta, ni con la anon key filtrada.
--   3. `id uuid primary key default gen_random_uuid()`: si el cliente
--      (iOS/Android) ya genera el UUID (como hace SwiftData hoy), se
--      respeta ese id; si no se manda, Postgres genera uno.
--   4. `updated_at` en todas las tablas — es la base para la
--      sincronización "gana el más reciente" entre dispositivos.
--      A PROPÓSITO no hay ningún trigger de servidor que lo pise en cada
--      UPDATE: el valor lo decide siempre el dispositivo que hizo el
--      cambio real (ver CloudSyncService), nunca "cuándo se sincronizó
--      por última vez". Si un trigger lo reescribiera a now() en cada
--      UPDATE, un dispositivo sin cambios reales que simplemente vuelve
--      a subir sus filas (como hace este sync, que sube todo cada vez)
--      haría que esa fila pareciera "más reciente" que la de otro
--      dispositivo con una edición real pero más antigua en el reloj de
--      pared — y esa edición real se perdería. Confiar solo en el
--      cliente evita justo ese escenario.
--   5. Los identificadores de notificaciones locales
--      (notification_identifier, notificationIdentifiers en Swift) NO
--      están aquí a propósito: cada dispositivo programa sus propias
--      notificaciones locales y no tiene sentido sincronizarlas.
--   6. Las fotos de comida (FoodEntry.imageData) tampoco están aquí:
--      subir fotos necesitaría Supabase Storage aparte (más coste, más
--      complejidad) — de momento solo sincronizan los datos nutricionales
--      de la comida, no la imagen. Se puede añadir más adelante si hace
--      falta de verdad.
--   7. Las claves de IA (OpenAI/Anthropic) NUNCA van en esta base de
--      datos ni en ninguna tabla — siguen siendo una clave por
--      instalación, configurada en Secrets.xcconfig (iOS) o su
--      equivalente en Android. Sincronizarlas en texto plano por Postgres
--      sería un riesgo de seguridad injustificado.

create extension if not exists pgcrypto;

-- =========================================================================
-- Nutrición
-- =========================================================================

create table if not exists public.food_entries (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  name text not null,
  date timestamptz not null,
  meal_type text not null default 'breakfast',
  source text not null default 'manual',
  calories double precision not null default 0,
  protein_grams double precision not null default 0,
  carbs_grams double precision not null default 0,
  fat_grams double precision not null default 0,
  notes text,
  analyzed_by text,
  updated_at timestamptz not null default now()
);

create table if not exists public.nutrition_goals (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null unique default auth.uid() references auth.users(id) on delete cascade,
  daily_calorie_goal double precision not null default 2000,
  protein_goal_grams double precision not null default 120,
  carbs_goal_grams double precision not null default 225,
  fat_goal_grams double precision not null default 65,
  target_weight_kg double precision,
  weekly_rate_kg double precision,
  updated_at timestamptz not null default now()
);

create table if not exists public.weight_entries (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  date timestamptz not null default now(),
  weight_kg double precision not null,
  updated_at timestamptz not null default now()
);

-- =========================================================================
-- Planner (tareas, eventos, notas)
-- =========================================================================

create table if not exists public.planner_tasks (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  title text not null,
  notes text,
  due_date timestamptz,
  reminder_date timestamptz,
  is_completed boolean not null default false,
  priority text not null default 'medium',
  is_focus boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.planner_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  title text not null,
  location text,
  notes text,
  start_date timestamptz not null,
  end_date timestamptz not null,
  is_all_day boolean not null default false,
  has_reminder boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.planner_notes (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  date timestamptz not null,
  text text not null default '',
  updated_at timestamptz not null default now()
);

-- =========================================================================
-- Finanzas
-- =========================================================================

create table if not exists public.transactions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  amount double precision not null,
  type text not null,
  category text not null,
  note text,
  date timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.budget_settings (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null unique default auth.uid() references auth.users(id) on delete cascade,
  monthly_budget double precision not null default 1000,
  total_savings double precision not null default 0,
  currency_code text not null default 'USD',
  savings_goal_amount double precision,
  savings_goal_date timestamptz,
  updated_at timestamptz not null default now()
);

create table if not exists public.category_budgets (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  category text not null,
  monthly_limit double precision not null,
  updated_at timestamptz not null default now()
);

create table if not exists public.recurring_transactions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  name text not null,
  amount double precision not null,
  type text not null,
  category text not null,
  day_of_month integer not null default 1,
  is_active boolean not null default true,
  last_applied_month timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- =========================================================================
-- Medicación
-- =========================================================================

create table if not exists public.medications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  name text not null,
  dosage text,
  notes text,
  reminder_minutes_since_midnight integer[] not null default '{}',
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.medication_dose_logs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  medication_id uuid not null references public.medications(id) on delete cascade,
  date timestamptz not null,
  minute_of_day integer not null,
  taken_at timestamptz,
  skipped boolean not null default false,
  updated_at timestamptz not null default now()
);

-- =========================================================================
-- Hábitos
-- =========================================================================

create table if not exists public.habits (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  name text not null,
  symbol_name text not null default 'checkmark.circle.fill',
  kind text not null default 'checkbox',
  target_value double precision,
  goal_direction text not null default 'atLeast',
  unit text,
  is_active boolean not null default true,
  sort_order integer not null default 0,
  linked_to_workouts boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.habit_logs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  habit_id uuid not null references public.habits(id) on delete cascade,
  date timestamptz not null,
  is_completed boolean not null default false,
  value double precision,
  updated_at timestamptz not null default now()
);

-- =========================================================================
-- Entrenamientos (contador de repeticiones del Apple Watch)
-- =========================================================================

create table if not exists public.workout_sets (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  exercise_name text not null,
  reps integer not null,
  date timestamptz not null,
  updated_at timestamptz not null default now()
);

-- =========================================================================
-- Progresión (nivel, racha, pase de temporada)
-- =========================================================================

-- Singleton por cuenta: tu nivel es tuyo, no de un dispositivo.
create table if not exists public.player_profiles (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null unique default auth.uid() references auth.users(id) on delete cascade,
  total_xp integer not null default 0,
  login_streak integer not null default 0,
  longest_login_streak integer not null default 0,
  last_login_date timestamptz,
  season_id text not null default '',
  season_xp integer not null default 0,
  unlocked_reward_ids text[] not null default '{}',
  updated_at timestamptz not null default now()
);

-- Cada concesión de experiencia. dedupe_key es lo que impide premiar dos
-- veces lo mismo, así que es única por usuario: sin esa restricción, dos
-- dispositivos sin conexión podrían premiar el mismo hábito del mismo día
-- y al sincronizar acabarían sumando XP duplicado.
create table if not exists public.xp_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  source text not null,
  amount integer not null,
  date timestamptz not null,
  dedupe_key text not null,
  updated_at timestamptz not null default now(),
  unique (user_id, dedupe_key)
);

-- =========================================================================
-- Preferencias del usuario (singleton por cuenta)
-- =========================================================================

create table if not exists public.user_settings (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null unique default auth.uid() references auth.users(id) on delete cascade,
  preferred_ai_provider text not null default 'openAI',
  meal_reminder_notifications_enabled boolean not null default true,
  event_notifications_enabled boolean not null default true,
  apple_watch_enabled boolean not null default false,
  display_name text,
  email text,
  updated_at timestamptz not null default now()
);


-- =========================================================================
-- Estudios: asignaturas, notas y eventos del curso
-- =========================================================================
--
-- El módulo que faltaba desde el principio: "cada día que inicies sesión,
-- luego que saques buenas notas, etc., vas a subir de nivel". Sin esto,
-- la parte de "buenas notas" del sistema de progresión no existía.
--
-- La media se calcula SIEMPRE a partir de las notas, nunca se guarda:
-- un campo `average` en la asignatura sería una segunda fuente de verdad
-- que se quedaría vieja en cuanto se edite o borre una nota.

create table if not exists public.subjects (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  name text not null,
  icon text not null default '📘',
  color text not null default '#2563eb',
  teacher text,
  -- Asistencia, con los mismos tres números que se llevan a mano en una
  -- hoja: cuántas clases tiene la asignatura, cuántas has faltado, y
  -- cuántas te puedes permitir antes de que cuente.
  total_classes integer not null default 0,
  hours_missed integer not null default 0,
  max_absences integer not null default 0,
  sort_order integer not null default 0,
  updated_at timestamptz not null default now()
);

-- Una prueba evaluada: su nota, cuánto pesa, y si cuenta para la media.
-- `counts_for_average` existe porque en la vida real hay notas que aún no
-- cuentan (un parcial que se recupera, un trabajo sin corregir) y que
-- estropearían la media si entraran a la fuerza.
create table if not exists public.grades (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  subject_id uuid not null references public.subjects(id) on delete cascade,
  name text not null,
  score numeric not null default 0,
  weight numeric not null default 0,
  counts_for_average boolean not null default true,
  date timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Exámenes, entregas, presentaciones… lo que hay por delante en el curso.
create table if not exists public.study_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  subject_id uuid references public.subjects(id) on delete cascade,
  title text not null,
  kind text not null default 'exam',
  date timestamptz not null,
  notes text,
  updated_at timestamptz not null default now()
);


-- =========================================================================
-- Rutinas encadenadas
--
-- El caso que las pide: "a las 7:15 me levanto, luego me ducho, luego me
-- lavo los dientes, luego desayuno". Eso no es una lista de tareas ni
-- cinco alarmas sueltas — es UNA cosa con orden y con ritmo.
--
-- Por qué se guardan una hora de inicio Y una duración por paso, en vez
-- de una hora por paso:
--
--   · Con una hora fija en cada paso, el día que te levantas diez minutos
--     tarde todos los avisos van desfasados y acabas ignorándolos. Y el
--     día que te duchas rápido, esperas mirando el móvil.
--   · Con encadenado puro (cada paso empieza al marcar el anterior), el
--     PRIMER aviso no sonaría nunca: no hay nada que marcar antes.
--
-- Guardando inicio + duraciones se pueden hacer las dos cosas: los avisos
-- salen a la hora calculada, y al marcar un paso se recalculan los que
-- quedan desde ese momento real. Ver web/routines.js.
-- =========================================================================

create table if not exists public.routines (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  name text not null,
  icon text not null default '☀️',
  -- Minutos desde medianoche, igual que medications: 7:15 son 435. Así no
  -- hay líos de zona horaria — una rutina de mañana es a las 7:15 estés
  -- donde estés, no "a las 5:15 UTC".
  start_minutes integer not null default 435 check (start_minutes between 0 and 1439),
  -- 1 = lunes … 7 = domingo (ISO). Vacío significa todos los días.
  days_of_week integer[] not null default '{1,2,3,4,5}',
  is_active boolean not null default true,
  notifications_enabled boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.routine_steps (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  routine_id uuid not null references public.routines(id) on delete cascade,
  title text not null,
  icon text not null default '✅',
  -- Cuánto dura ESTE paso. El siguiente empieza cuando este acaba.
  duration_minutes integer not null default 10 check (duration_minutes between 1 and 720),
  sort_order integer not null default 0,
  updated_at timestamptz not null default now()
);

-- Un paso marcado un día concreto. Es lo que da la racha de la rutina y
-- lo que permite recalcular los avisos que quedan: `date` no es el día,
-- es el INSTANTE real en que se marcó.
create table if not exists public.routine_logs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  routine_id uuid not null references public.routines(id) on delete cascade,
  step_id uuid not null references public.routine_steps(id) on delete cascade,
  date timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- =========================================================================
-- RLS: activar + una política "todo" por tabla (auth.uid() = user_id)
-- =========================================================================

do $$
declare
  table_name text;
begin
  foreach table_name in array array[
    'food_entries', 'nutrition_goals', 'weight_entries',
    'planner_tasks', 'planner_events', 'planner_notes',
    'transactions', 'budget_settings', 'category_budgets', 'recurring_transactions',
    'medications', 'medication_dose_logs',
    'habits', 'habit_logs',
    'workout_sets',
    'player_profiles', 'xp_events',
    'subjects', 'grades', 'study_events',
    'routines', 'routine_steps', 'routine_logs',
    'user_settings'
  ]
  loop
    execute format('alter table public.%I enable row level security', table_name);

    execute format('drop policy if exists %I on public.%I', table_name || '_owner_access', table_name);
    execute format(
      'create policy %I on public.%I for all using (auth.uid() = user_id) with check (auth.uid() = user_id)',
      table_name || '_owner_access', table_name
    );
  end loop;
end $$;

-- Índices por (user_id, fecha) para las tablas que más se listan por
-- rango de fechas — evita full table scans según crecen los datos.
create index if not exists food_entries_user_date_idx on public.food_entries (user_id, date);
create index if not exists transactions_user_date_idx on public.transactions (user_id, date);
create index if not exists planner_tasks_user_due_idx on public.planner_tasks (user_id, due_date);
create index if not exists planner_events_user_start_idx on public.planner_events (user_id, start_date);
create index if not exists habit_logs_user_date_idx on public.habit_logs (user_id, date);
create index if not exists medication_dose_logs_user_date_idx on public.medication_dose_logs (user_id, date);
create index if not exists weight_entries_user_date_idx on public.weight_entries (user_id, date);
create index if not exists xp_events_user_date_idx on public.xp_events (user_id, date);
create index if not exists grades_user_subject_idx on public.grades (user_id, subject_id);
create index if not exists study_events_user_date_idx on public.study_events (user_id, date);
create index if not exists routine_steps_routine_idx on public.routine_steps (user_id, routine_id);
create index if not exists routine_logs_user_date_idx on public.routine_logs (user_id, date);

-- =========================================================================
-- SEGURIDAD (segunda ronda)
--
-- Lo de arriba ya impide que una cuenta vea los datos de otra: eso lo hace
-- RLS, y es la parte más importante. Lo que viene ahora cubre las otras
-- tres cosas que se pueden atacar en una app que vive en una página web:
--
--   A. Quién puede registrarse            → signup_control + allowed_signups
--   B. Que nadie te reviente la cuenta    → MFA (se activa en Ajustes) y,
--                                           aquí abajo, el candado del
--                                           registro y los límites
--   C. Que nadie te reviente la base      → límites de tamaño y de filas
--
-- IMPORTANTE: esto se aplica igual en iPhone, en Android y en el navegador,
-- porque no está en la app — está en el servidor. Una app se puede
-- modificar (basta con abrir las herramientas del navegador); esto no.
-- =========================================================================

-- ── A. Control de registro ──────────────────────────────────────────────
--
-- Tres modos. Se cambia con una línea de SQL y tiene efecto inmediato en
-- todas las plataformas a la vez:
--
--   update public.signup_control set mode = 'cerrado';      -- nadie más
--   update public.signup_control set mode = 'invitacion';   -- solo lista
--   update public.signup_control set mode = 'abierto';      -- cualquiera
--
-- 'cerrado' es el botón de pánico: si un día alguien se pone a crear
-- cuentas en masa para llenarte la base, lo paras en cinco segundos.

create table if not exists public.signup_control (
  id boolean primary key default true check (id),   -- fuerza UNA sola fila
  mode text not null default 'invitacion'
    check (mode in ('abierto', 'invitacion', 'cerrado')),
  updated_at timestamptz not null default now()
);

insert into public.signup_control (id, mode)
values (true, 'invitacion')
on conflict (id) do nothing;

-- La lista de quién puede entrar. Una fila vale por correo, por código, o
-- por los dos a la vez:
--
--   -- invitar a una persona concreta
--   insert into public.allowed_signups (email, note)
--   values ('amigo@correo.com', 'Clase de 1º');
--
--   -- un código que sirva para 30 personas y caduque en una semana
--   insert into public.allowed_signups (code, max_uses, expires_at, note)
--   values ('HABITIUM-2026', 30, now() + interval '7 days', 'Clase entera');
--
-- El código va en texto plano a propósito: no es una contraseña, es un
-- cupón. Nadie que no seas tú puede leer esta tabla (ver los REVOKE del
-- final), así que verlo desde el panel de Supabase compensa.
create table if not exists public.allowed_signups (
  id uuid primary key default gen_random_uuid(),
  email text,
  code text,
  max_uses integer not null default 1 check (max_uses > 0),
  uses integer not null default 0 check (uses >= 0),
  expires_at timestamptz,
  note text,
  created_at timestamptz not null default now(),
  check (email is not null or code is not null)
);

-- Comparar correos sin distinguir mayúsculas, y sin que se pueda invitar
-- dos veces al mismo.
create unique index if not exists allowed_signups_email_idx
  on public.allowed_signups (lower(email)) where email is not null;
create unique index if not exists allowed_signups_code_idx
  on public.allowed_signups (upper(code)) where code is not null;

-- El portero. Se ejecuta DENTRO de la transacción que crea el usuario, así
-- que si levanta la mano el usuario no llega a existir.
--
-- `security definer` = corre con los permisos del dueño de la función (tú),
-- no con los de quien se registra. Por eso puede leer allowed_signups
-- aunque el que se registra no tenga ningún permiso sobre ella.
-- `search_path` fijo: sin eso, alguien que pudiera crear un esquema propio
-- podría colar su propia tabla `allowed_signups` delante de la tuya.
create or replace function public.check_signup_allowed()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  modo text;
  codigo text;
  invitacion public.allowed_signups%rowtype;
begin
  select mode into modo from public.signup_control where id;
  modo := coalesce(modo, 'abierto');

  if modo = 'abierto' then
    return new;
  end if;

  if modo = 'cerrado' then
    raise exception 'HABITIUM_REGISTRO_CERRADO'
      using hint = 'El registro está cerrado ahora mismo.';
  end if;

  -- modo = 'invitacion'
  codigo := nullif(trim(coalesce(new.raw_user_meta_data ->> 'invite_code', '')), '');

  select * into invitacion
  from public.allowed_signups a
  where (a.email is not null and lower(a.email) = lower(new.email))
     or (codigo is not null and a.code is not null and upper(a.code) = upper(codigo))
  order by (a.email is not null) desc          -- una invitación nominal manda
  limit 1
  for update;

  if not found then
    raise exception 'HABITIUM_SIN_INVITACION'
      using hint = 'Ese correo no está invitado y el código no vale.';
  end if;

  if invitacion.expires_at is not null and invitacion.expires_at < now() then
    raise exception 'HABITIUM_INVITACION_CADUCADA'
      using hint = 'Esa invitación ya ha caducado.';
  end if;

  if invitacion.uses >= invitacion.max_uses then
    raise exception 'HABITIUM_INVITACION_AGOTADA'
      using hint = 'Esa invitación ya se ha usado.';
  end if;

  update public.allowed_signups
     set uses = uses + 1
   where id = invitacion.id;

  return new;
end;
$$;

drop trigger if exists habitium_check_signup on auth.users;
create trigger habitium_check_signup
  before insert on auth.users
  for each row execute function public.check_signup_allowed();

-- Para que la app pueda enseñar un mensaje decente ANTES de intentarlo (y
-- pedir el código solo cuando hace falta), sin convertirse en un chivato:
-- esta función dice el modo, nada más. No confirma si un correo concreto
-- está invitado ni si ya existe una cuenta con él — eso sería regalarle a
-- cualquiera una lista de correos válidos.
create or replace function public.signup_mode()
returns text
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce((select mode from public.signup_control where id), 'abierto');
$$;

-- ── B. Nadie, absolutamente nadie, toca las tablas de control ───────────
--
-- Supabase da permisos a `anon` y `authenticated` sobre lo que hay en
-- `public` por defecto. En las tablas de datos eso da igual porque RLS
-- filtra por auth.uid(). Aquí no hay user_id que filtrar, así que el
-- permiso se quita a mano. Con RLS activado y CERO políticas, el resultado
-- es el mismo desde los dos lados: invisible.
alter table public.signup_control  enable row level security;
alter table public.allowed_signups enable row level security;

revoke all on public.signup_control  from anon, authenticated;
revoke all on public.allowed_signups from anon, authenticated;

-- signup_mode() sí es pública (la app la llama antes de registrarte).
-- check_signup_allowed() NO: solo la llama el trigger.
revoke all on function public.check_signup_allowed() from public, anon, authenticated;
grant execute on function public.signup_mode() to anon, authenticated;

-- ── C. Que una cuenta no pueda reventar la base de datos ────────────────
--
-- Esto es lo que quedaba abierto de verdad. RLS impide que leas datos
-- ajenos, pero no impide que metas basura en los TUYOS: con la clave
-- pública (que es pública a propósito) y una cuenta creada, un script
-- puede subir un campo "nombre" de 50 MB, o diez millones de filas, y
-- dejar el proyecto sin cuota para todos.
--
-- Dos cerrojos: tamaño por campo y número de filas por tabla.

-- C.1 — Tamaño máximo de cada campo de texto.
--
-- Los límites se ponen por NOMBRE de columna, no tabla por tabla: así una
-- tabla nueva que tenga un `name` hereda el límite sin tener que acordarse.
do $$
declare
  t text;
  c record;
  limite integer;
  nombre text;
  tablas text[] := array[
    'food_entries', 'nutrition_goals', 'weight_entries',
    'planner_tasks', 'planner_events', 'planner_notes',
    'transactions', 'budget_settings', 'category_budgets', 'recurring_transactions',
    'medications', 'medication_dose_logs',
    'habits', 'habit_logs', 'workout_sets',
    'player_profiles', 'xp_events',
    'subjects', 'grades', 'study_events',
    'routines', 'routine_steps', 'routine_logs',
    'user_settings'
  ];
begin
  foreach t in array tablas loop
    for c in
      select column_name
      from information_schema.columns
      where table_schema = 'public' and table_name = t and data_type = 'text'
    loop
      limite := case c.column_name
        when 'notes'        then 4000
        when 'note'         then 2000
        when 'text'         then 8000   -- planner_notes: la nota del día
        when 'name'         then 120
        when 'title'        then 200
        when 'exercise_name' then 120
        when 'display_name' then 80
        when 'email'        then 320    -- el máximo real de un correo
        when 'teacher'      then 120
        when 'location'     then 200
        when 'dosage'       then 120
        when 'unit'         then 32
        when 'icon'         then 16     -- un emoji, no un archivo
        when 'color'        then 32
        when 'currency_code' then 8
        when 'symbol_name'  then 80
        when 'dedupe_key'   then 160
        when 'season_id'    then 32
        else 64                         -- kind, type, source, category, priority…
      end;

      nombre := format('%s_%s_len', t, c.column_name);
      begin
        execute format(
          'alter table public.%I add constraint %I check (char_length(%I) <= %s)',
          t, nombre, c.column_name, limite
        );
      exception
        when duplicate_object then null;   -- ya estaba puesto
        when check_violation then
          raise notice 'Hay datos que pasan del límite en %.% — revísalos antes', t, c.column_name;
      end;
    end loop;
  end loop;
end $$;

-- El único array de texto que hay. Sin esto, `unlocked_reward_ids` acepta
-- un array de un millón de cadenas y es el camino más corto para llenar
-- la base desde una sola fila.
--
-- Ojo con cómo está escrito: lo natural sería mirar el elemento más largo
-- con `(select max(char_length(x)) from unnest(...) x)`, pero Postgres NO
-- admite subconsultas dentro de un CHECK y la sentencia falla al
-- aplicarla. `array_to_string` hace el mismo trabajo sin subconsulta:
-- pega todo el array en un texto y mide ese texto, que es justo lo que
-- interesa limitar (el tamaño total que ocupa la fila).
do $$
begin
  alter table public.player_profiles
    add constraint player_profiles_rewards_len
    check (
      array_length(unlocked_reward_ids, 1) is null
      or (array_length(unlocked_reward_ids, 1) <= 200
          and char_length(array_to_string(unlocked_reward_ids, ',')) <= 4000)
    );
exception when duplicate_object then null;
end $$;

do $$
begin
  alter table public.routines
    add constraint routines_days_len
    check (array_length(days_of_week, 1) is null or array_length(days_of_week, 1) <= 7);
exception when duplicate_object then null;
end $$;

-- Y los minutos de recordatorio de una medicación: 1440 minutos tiene el
-- día, así que más de 48 avisos ya no es un uso, es un ataque.
do $$
begin
  alter table public.medications
    add constraint medications_reminders_len
    check (
      array_length(reminder_minutes_since_midnight, 1) is null
      or array_length(reminder_minutes_since_midnight, 1) <= 48
    );
exception when duplicate_object then null;
end $$;

-- C.2 — Número máximo de filas por cuenta y tabla.
--
-- El truco está en cómo se cuenta: `count(*)` sobre una tabla enorme la
-- recorre entera y haría lento cada INSERT. Con el subselect + LIMIT,
-- Postgres para de contar en cuanto llega al límite, así que el coste es
-- constante y no crece con los datos.
create or replace function public.limite_de_filas()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  maximo integer := TG_ARGV[0]::integer;
  cuantas integer;
begin
  execute format(
    'select count(*) from (select 1 from public.%I where user_id = $1 limit %s) s',
    TG_TABLE_NAME, maximo
  ) into cuantas using new.user_id;

  if cuantas >= maximo then
    raise exception 'HABITIUM_LIMITE_FILAS'
      using hint = format('Has llegado al máximo de filas en %s (%s).', TG_TABLE_NAME, maximo);
  end if;
  return new;
end;
$$;

revoke all on function public.limite_de_filas() from public, anon, authenticated;

-- Los números son generosos a propósito: 50.000 comidas son más de treinta
-- años apuntando cinco al día. Si alguna vez te quedas corto, súbelos —
-- pero que exista un techo es lo que impide que una cuenta robada te deje
-- el proyecto sin cuota en una tarde.
do $$
declare
  par record;
begin
  for par in
    select * from (values
      ('food_entries', 50000), ('weight_entries', 20000),
      ('planner_tasks', 50000), ('planner_events', 50000), ('planner_notes', 20000),
      ('transactions', 50000), ('category_budgets', 200), ('recurring_transactions', 200),
      ('medications', 200), ('medication_dose_logs', 100000),
      ('habits', 200), ('habit_logs', 100000),
      ('workout_sets', 100000),
      ('xp_events', 100000),
      ('subjects', 100), ('grades', 5000), ('study_events', 5000),
      ('routines', 50), ('routine_steps', 500), ('routine_logs', 100000)
    ) as v(tabla, maximo)
  loop
    execute format('drop trigger if exists %I on public.%I',
                   par.tabla || '_limite', par.tabla);
    execute format(
      'create trigger %I before insert on public.%I for each row execute function public.limite_de_filas(%s)',
      par.tabla || '_limite', par.tabla, par.maximo
    );
  end loop;
end $$;

-- Índices que los límites de arriba necesitan para ser baratos.
create index if not exists subjects_user_idx  on public.subjects (user_id);
create index if not exists habits_user_idx    on public.habits (user_id);
create index if not exists medications_user_idx on public.medications (user_id);
create index if not exists category_budgets_user_idx on public.category_budgets (user_id);
create index if not exists recurring_transactions_user_idx on public.recurring_transactions (user_id);
create index if not exists routines_user_idx on public.routines (user_id);

-- ── D. Higiene de permisos ──────────────────────────────────────────────
--
-- `anon` (el visitante sin cuenta) no tiene por qué poder escribir NADA.
-- RLS ya lo bloquea, pero quitarle el permiso además es cinturón y
-- tirantes: si algún día una política se escribe mal, `anon` sigue sin
-- poder tocar nada.
do $$
declare
  t text;
begin
  foreach t in array array[
    'food_entries', 'nutrition_goals', 'weight_entries',
    'planner_tasks', 'planner_events', 'planner_notes',
    'transactions', 'budget_settings', 'category_budgets', 'recurring_transactions',
    'medications', 'medication_dose_logs',
    'habits', 'habit_logs', 'workout_sets',
    'player_profiles', 'xp_events',
    'subjects', 'grades', 'study_events',
    'routines', 'routine_steps', 'routine_logs',
    'user_settings'
  ] loop
    execute format('revoke all on public.%I from anon', t);
  end loop;
end $$;

-- Y nadie puede crear tablas nuevas en `public` salvo el dueño. Sin esto,
-- una cuenta cualquiera puede crear una tabla SIN RLS y usar tu base de
-- datos como almacén gratis.
revoke create on schema public from public, anon, authenticated;
