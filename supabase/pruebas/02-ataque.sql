-- ⚠️ NUNCA EJECUTES ESTO EN TU PROYECTO DE SUPABASE.
--
-- Crea usuarios, borra datos, inunda tablas hasta el tope y cambia el
-- modo de registro. Es para una base de datos de usar y tirar, en tu
-- propio ordenador. Cómo montarla: LEEME.md de esta carpeta.
--
-- Ataque real contra el esquema de Habitium, corriendo sobre un Postgres
-- de verdad con la misma forma que Supabase (roles anon/authenticated,
-- auth.users, auth.uid() leyendo el JWT).
--
-- Cada prueba imprime PASA o FALLA. "PASA" significa que el ataque NO
-- funcionó, que es lo que se busca.

\set ON_ERROR_STOP off
\set QUIET on
\pset tuples_only on
\pset format unaligned

create or replace function prueba(nombre text, condicion boolean) returns void
language plpgsql as $$
begin
  raise notice '% %', case when condicion then ' PASA ' else ' FALLA' end, nombre;
end $$;

-- Dos víctimas.
\set A '11111111-1111-4111-8111-111111111111'
\set B '22222222-2222-4222-8222-222222222222'

-- El portero está en modo invitación, así que primero se abre: si no, no
-- hay ni víctimas y las pruebas de RLS pasarían sobre tablas vacías.
update public.signup_control set mode = 'abierto';

-- Rastro de una ejecución anterior, si lo hay. Como postgres es el dueño
-- de las tablas, RLS no se le aplica y puede limpiar de verdad.
delete from public.routine_logs;
delete from public.routine_steps;
delete from public.routines;
delete from public.subjects;
delete from public.food_entries;
delete from public.user_settings;
delete from public.player_profiles;
delete from public.medications;
delete from public.allowed_signups where note = 'prueba';
delete from auth.users where email like '%habitium.test' or email like '%hacker.test';

insert into auth.users (id, email, email_confirmed_at) values
  (:'A', 'ana@habitium.test', now()),
  (:'B', 'bruno@habitium.test', now())
on conflict do nothing;

-- Ana guarda sus cosas.
set role authenticated;
set request.jwt.claims = '{"sub":"11111111-1111-4111-8111-111111111111","role":"authenticated"}';
insert into public.food_entries (user_id, name, date, calories)
  values (:'A', 'Tortilla de Ana', now(), 300);
insert into public.user_settings (user_id, display_name, email)
  values (:'A', 'Ana', 'ana@habitium.test');
reset role;

\echo ''
\echo '═══ 1. ¿Puede Bruno ver o tocar lo de Ana? ═════════════════════'
set role authenticated;
set request.jwt.claims = '{"sub":"22222222-2222-4222-8222-222222222222","role":"authenticated"}';

select prueba('Bruno NO ve las comidas de Ana',
  (select count(*) from public.food_entries) = 0);

select prueba('Bruno NO ve los ajustes de Ana',
  (select count(*) from public.user_settings) = 0);

-- Intento de borrar lo de Ana.
with borradas as (delete from public.food_entries returning 1)
select prueba('Bruno NO puede borrar lo de Ana', (select count(*) from borradas) = 0);

-- Intento de modificarlo.
with tocadas as (update public.food_entries set name = 'HACKEADO' returning 1)
select prueba('Bruno NO puede modificar lo de Ana', (select count(*) from tocadas) = 0);

-- Intento de escribir EN la cuenta de Ana (suplantación).
do $$
declare ok boolean := false;
begin
  begin
    insert into public.food_entries (user_id, name, date, calories)
      values ('11111111-1111-4111-8111-111111111111', 'Metido por Bruno', now(), 1);
  exception when insufficient_privilege or others then ok := true;
  end;
  perform prueba('Bruno NO puede escribir en la cuenta de Ana', ok);
end $$;

\echo ''
\echo '═══ 2. ¿Puede Ana regalarle sus filas a Bruno (o robárselas)? ══'
set request.jwt.claims = '{"sub":"11111111-1111-4111-8111-111111111111","role":"authenticated"}';
select prueba('(control) Ana sí ve lo suyo — si esto falla, las pruebas de arriba no valen',
  (select count(*) from public.food_entries) >= 1);

do $$
declare ok boolean := false;
begin
  begin
    update public.food_entries
       set user_id = '22222222-2222-4222-8222-222222222222';
  exception when others then ok := true;
  end;
  perform prueba('Nadie puede cambiar el dueño de una fila', ok);
end $$;

select prueba('...y la fila sigue siendo de Ana',
  (select user_id from public.food_entries limit 1) = '11111111-1111-4111-8111-111111111111');

\echo ''
\echo '═══ 3. ¿Puede un visitante sin cuenta hacer algo? ══════════════'
reset role;
set role anon;
set request.jwt.claims = '{}';
do $$
declare ok boolean := false;
begin
  begin
    perform * from public.food_entries;
  exception when insufficient_privilege then ok := true;   -- ni permiso para mirar
  end;
  perform prueba('anon NO ve nada (ni permiso para mirar la tabla tiene)', ok);
end $$;
do $$
declare ok boolean := false;
begin
  begin
    insert into public.food_entries (name, date, calories) values ('anon', now(), 1);
  exception when others then ok := true;
  end;
  perform prueba('anon NO puede escribir', ok);
end $$;

\echo ''
\echo '═══ 4. Las tablas de control, ¿son invisibles de verdad? ═══════'
reset role;
set role authenticated;
set request.jwt.claims = '{"sub":"22222222-2222-4222-8222-222222222222","role":"authenticated"}';
do $$
declare ok boolean := false;
begin
  begin perform * from public.allowed_signups;
  exception when others then ok := true; end;
  perform prueba('Nadie logueado puede leer la lista de invitados', ok);
end $$;
do $$
declare ok boolean := false;
begin
  begin
    insert into public.allowed_signups (email) values ('yo_mismo@hacker.test');
  exception when others then ok := true; end;
  perform prueba('Nadie logueado puede auto-invitarse', ok);
end $$;
do $$
declare ok boolean := false;
begin
  begin update public.signup_control set mode = 'abierto';
  exception when others then ok := true; end;
  perform prueba('Nadie logueado puede abrir el registro', ok);
end $$;
do $$
declare ok boolean := false;
begin
  begin perform public.check_signup_allowed();
  exception when others then ok := true; end;
  perform prueba('Nadie puede llamar al portero a mano', ok);
end $$;
do $$
declare ok boolean := false;
begin
  begin execute 'create table public.almacen_gratis (x text)';
  exception when others then ok := true; end;
  perform prueba('Nadie puede crear tablas sin RLS en public', ok);
end $$;
select prueba('signup_mode() sí se puede consultar (y solo dice el modo)',
  public.signup_mode() in ('abierto', 'invitacion', 'cerrado'));

\echo ''
\echo '═══ 5. ¿Se puede llenar la base con basura? ════════════════════'
set request.jwt.claims = '{"sub":"11111111-1111-4111-8111-111111111111","role":"authenticated"}';
do $$
declare ok boolean := false;
begin
  begin
    insert into public.food_entries (user_id, name, date, calories)
      values ('11111111-1111-4111-8111-111111111111', repeat('A', 5000000), now(), 1);
  exception when check_violation then ok := true; end;
  perform prueba('Un nombre de 5 MB se rechaza', ok);
end $$;
do $$
declare ok boolean := false;
begin
  begin
    insert into public.player_profiles (user_id, unlocked_reward_ids)
      values ('11111111-1111-4111-8111-111111111111',
              array(select repeat('x', 100) from generate_series(1, 5000)));
  exception when check_violation then ok := true; end;
  perform prueba('Un array de 5000 premios se rechaza', ok);
end $$;
do $$
declare ok boolean := false;
begin
  begin
    insert into public.medications (user_id, name, reminder_minutes_since_midnight)
      values ('11111111-1111-4111-8111-111111111111', 'Spam',
              array(select g from generate_series(1, 1440) g));
  exception when check_violation then ok := true; end;
  perform prueba('1440 recordatorios en una medicación se rechazan', ok);
end $$;
do $$
declare ok boolean := false; i integer;
begin
  -- El techo de subjects son 100 filas. Se intentan 150.
  --
  -- El manejador de excepciones va DENTRO del bucle a propósito: si
  -- envolviera al bucle entero, Postgres desharía las 100 inserciones
  -- buenas al saltar la excepción y el recuento de después saldría 0 --
  -- un suspenso falso que parecería un fallo del esquema y no lo es.
  for i in 1..150 loop
    begin
      insert into public.subjects (user_id, name)
        values ('11111111-1111-4111-8111-111111111111', 'Asignatura ' || i);
    exception when others then ok := true;
    end;
  end loop;
  perform prueba('El límite de filas por tabla corta la inundación', ok);
end $$;
select prueba('...y corta en el techo exacto (100)',
  (select count(*) from public.subjects) = 100);

reset role;
reset request.jwt.claims;

\echo ''
\echo '═══ 6. El portero del registro ═════════════════════════════════'
update public.signup_control set mode = 'invitacion';
insert into public.allowed_signups (email, note) values ('invitada@habitium.test', 'prueba');
insert into public.allowed_signups (code, max_uses, note) values ('CLASE-2026', 2, 'prueba');
insert into public.allowed_signups (code, max_uses, expires_at, note)
  values ('CADUCADO', 9, now() - interval '1 day', 'prueba');

do $$
declare ok boolean := false;
begin
  begin insert into auth.users (email) values ('colado@hacker.test');
  exception when others then ok := true; end;
  perform prueba('Sin invitación NO se crea la cuenta', ok);
end $$;

do $$
declare ok boolean := false;
begin
  begin
    insert into auth.users (email, raw_user_meta_data)
      values ('colado2@hacker.test', '{"invite_code":"NO-EXISTE"}');
  exception when others then ok := true; end;
  perform prueba('Con un código inventado tampoco', ok);
end $$;

do $$
declare ok boolean := false;
begin
  begin
    insert into auth.users (email, raw_user_meta_data)
      values ('colado3@hacker.test', '{"invite_code":"CADUCADO"}');
  exception when others then ok := true; end;
  perform prueba('Con un código caducado tampoco', ok);
end $$;

insert into auth.users (email) values ('invitada@habitium.test');
select prueba('La invitada por correo SÍ entra',
  exists(select 1 from auth.users where email = 'invitada@habitium.test'));

do $$
declare ok boolean := false;
begin
  begin insert into auth.users (email) values ('invitada2@habitium.test');
  exception when others then ok := true; end;
  perform prueba('Una invitación de un solo uso no vale dos veces', ok);
end $$;

-- El código da para dos, y no distingue mayúsculas.
insert into auth.users (email, raw_user_meta_data)
  values ('companero1@habitium.test', '{"invite_code":"clase-2026"}');
insert into auth.users (email, raw_user_meta_data)
  values ('companero2@habitium.test', '{"invite_code":"  CLASE-2026  "}');
select prueba('El código vale para los dos usos, en minúsculas o con espacios',
  (select count(*) from auth.users where email like 'companero%') = 2);

do $$
declare ok boolean := false;
begin
  begin
    insert into auth.users (email, raw_user_meta_data)
      values ('tercero@habitium.test', '{"invite_code":"CLASE-2026"}');
  exception when others then ok := true; end;
  perform prueba('El tercero ya no entra: el código estaba agotado', ok);
end $$;

update public.signup_control set mode = 'cerrado';
do $$
declare ok boolean := false;
begin
  begin
    insert into auth.users (email, raw_user_meta_data)
      values ('nadie@habitium.test', '{"invite_code":"CLASE-2026"}');
  exception when others then ok := true; end;
  perform prueba('Con el registro CERRADO no entra ni un invitado', ok);
end $$;

update public.signup_control set mode = 'abierto';
insert into auth.users (email) values ('cualquiera@habitium.test');
select prueba('Con el registro ABIERTO entra cualquiera',
  exists(select 1 from auth.users where email = 'cualquiera@habitium.test'));

update public.signup_control set mode = 'invitacion';
\echo ''
