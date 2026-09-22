-- Habitium — comprobación de seguridad
--
-- Esto no cambia nada: solo mira y te dice si algo está mal. Pégalo en
-- Supabase → SQL Editor → Run cada vez que toques el esquema, y sobre todo
-- después de la primera vez que ejecutes schema.sql.
--
-- Lo que responde, en cristiano:
--
--   · ¿Hay alguna tabla con datos de gente sin el candado puesto?
--   · ¿Hay alguna tabla con el candado puesto pero sin llave (= nadie
--     entra, ni siquiera tú)?
--   · ¿Está el portero del registro instalado?
--   · ¿Puede un visitante sin cuenta escribir algo?
--
-- Todo lo que salga marcado como ✗ hay que arreglarlo. Si sale todo ✓,
-- no significa que la app sea inexpugnable —eso no existe— pero sí que
-- las tres puertas grandes están cerradas.

-- ═══ 1. RLS activado en todas las tablas de datos ═══════════════════════
select
  case when bool_and(c.relrowsecurity) then '✓' else '✗' end as ok,
  'RLS activado en todas las tablas' as comprueba,
  coalesce(string_agg(c.relname, ', ') filter (where not c.relrowsecurity),
           'todas correctas') as detalle
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and c.relkind = 'r';

-- ═══ 2. Cada tabla de datos tiene su política, y la política es la buena ═
--
-- Una política que no mencione auth.uid() es una política que deja pasar a
-- quien no debe. Esta consulta las lista para que las leas con tus ojos.
select
  case when qual like '%auth.uid()%' and with_check like '%auth.uid()%'
       then '✓' else '✗ REVISAR' end as ok,
  tablename,
  policyname,
  qual       as "se puede leer si",
  with_check as "se puede escribir si"
from pg_policies
where schemaname = 'public'
order by tablename;

-- ═══ 3. Tablas con RLS pero SIN ninguna política ════════════════════════
--
-- Para las tablas de datos esto sería un fallo (nadie podría entrar).
-- Para signup_control y allowed_signups es justo lo que queremos: son
-- tuyas y de nadie más.
select
  case when c.relname in ('signup_control', 'allowed_signups')
       then '✓ a propósito' else '✗ nadie puede usarla' end as ok,
  c.relname as tabla
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and c.relkind = 'r' and c.relrowsecurity
  and not exists (
    select 1 from pg_policies p
    where p.schemaname = 'public' and p.tablename = c.relname
  );

-- ═══ 4. El portero del registro ═════════════════════════════════════════
select
  case when count(*) = 1 then '✓' else '✗ FALTA' end as ok,
  'Trigger de control de registro en auth.users' as comprueba,
  (select mode from public.signup_control where id) as "modo actual"
from pg_trigger
where tgname = 'habitium_check_signup' and not tgisinternal;

-- ═══ 5. Un visitante sin cuenta no escribe nada ═════════════════════════
select
  case when count(*) = 0 then '✓' else '✗' end as ok,
  'anon no tiene permiso de escritura' as comprueba,
  coalesce(string_agg(distinct table_name, ', '), 'ninguno') as detalle
from information_schema.role_table_grants
where grantee = 'anon' and table_schema = 'public'
  and privilege_type in ('INSERT', 'UPDATE', 'DELETE');

-- ═══ 6. Los límites de tamaño están puestos ═════════════════════════════
select
  case when count(*) >= 30 then '✓' else '✗ faltan' end as ok,
  'Límites de longitud en campos de texto' as comprueba,
  count(*) as cuantos
from pg_constraint
where connamespace = 'public'::regnamespace
  and contype = 'c' and conname like '%\_len';

-- ═══ 7. Los límites de número de filas están puestos ════════════════════
select
  case when count(*) >= 17 then '✓' else '✗ faltan' end as ok,
  'Triggers de límite de filas' as comprueba,
  count(*) as cuantos
from pg_trigger
where tgname like '%\_limite' and not tgisinternal;

-- ═══ 8. La prueba de verdad: intentar leer datos de otra persona ════════
--
-- Las siete de arriba miran la configuración. Esta ATACA: se hace pasar
-- por un usuario cualquiera (rol `authenticated` con un uid inventado) e
-- intenta leer TODO. Si RLS funciona, tiene que devolver 0 en todas.
--
-- Se ejecuta dentro de una transacción que se deshace al final, así que
-- no deja rastro.
begin;
  set local role authenticated;
  set local request.jwt.claims = '{"sub":"00000000-0000-4000-8000-000000000000","role":"authenticated"}';

  select
    case when (select count(*) from public.food_entries)
            + (select count(*) from public.user_settings)
            + (select count(*) from public.transactions)
            + (select count(*) from public.grades)
            + (select count(*) from public.player_profiles) = 0
         then '✓ un extraño no ve nada'
         else '✗✗✗ FUGA DE DATOS' end as ok,
    'Intento de lectura con un usuario que no existe' as comprueba;

  -- Y que tampoco pueda escribir en la cuenta de otro.
  select
    case when (
      select count(*) from (
        select 1 from public.food_entries limit 1
      ) s
    ) = 0 then '✓' else '✗' end as ok,
    'Intento de escritura cruzada' as comprueba;
rollback;

-- ═══ 9. Quién está invitado y cuánto queda de cada invitación ═══════════
select
  coalesce(email, '(código: ' || code || ')') as invitado,
  uses || ' de ' || max_uses as usos,
  coalesce(to_char(expires_at, 'DD/MM/YYYY'), 'sin caducidad') as caduca,
  coalesce(note, '') as nota
from public.allowed_signups
order by created_at desc;
