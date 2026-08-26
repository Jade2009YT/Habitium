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
-- Preferencias del usuario (singleton por cuenta)
-- =========================================================================

create table if not exists public.user_settings (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null unique default auth.uid() references auth.users(id) on delete cascade,
  preferred_ai_provider text not null default 'openAI',
  meal_reminder_notifications_enabled boolean not null default true,
  event_notifications_enabled boolean not null default true,
  display_name text,
  email text,
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
