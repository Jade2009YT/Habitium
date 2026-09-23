-- Ataque al buzón de sugerencias.
--
-- ⚠️  NO SE EJECUTA EN TU PROYECTO DE SUPABASE. Crea usuarios, escribe
--     sugerencias y vota. Es para el Postgres de mentira de 01-entorno-falso.sql.
--     Ver LEEME.md de esta carpeta.
--
-- El buzón es la primera tabla de toda la base en la que una persona ve
-- algo escrito por otra. Eso rompe la regla que protegía todo lo demás
-- —"cada uno ve lo suyo"— así que aquí hay que comprobar a mano las seis
-- cosas que se pueden intentar:
--
--   1. Publicar firmando como otro.
--   2. Editar la sugerencia de otro.
--   3. Ascender la propia a "hecha".
--   4. Subirse los votos.
--   5. Votar mil veces.
--   6. Leerlo todo sin tener cuenta.
--
-- Y una séptima prueba que tiene que SALIR BIEN: si todas las de arriba
-- salieran bien porque la tabla está vacía o porque nadie puede leer
-- nada, el resultado sería verde y no valdría nada. La prueba de control
-- es la que detecta eso.

\set ON_ERROR_STOP off
\set QUIET on
\pset pager off

-- Los papeles: A escribe, B mira y vota, Z es el que va de listo.
\set A '''aaaaaaaa-1111-4111-8111-111111111111'''
\set B '''bbbbbbbb-2222-4222-8222-222222222222'''

reset role;
reset request.jwt.claims;

delete from public.suggestion_votes;
delete from public.suggestions;
delete from auth.users where email in ('a@habitium.test', 'b@habitium.test');

-- El disparador de registro exige invitación: se abre solo para montar
-- el escenario y se vuelve a cerrar.
update public.signup_control set mode = 'abierto';

insert into auth.users (id, email) values (:A, 'a@habitium.test'), (:B, 'b@habitium.test');

-- Tabla normal y no temporal a propósito: las temporales viven en un
-- esquema propio al que los roles `authenticated` y `anon` no llegan, y
-- las pruebas que corren bajo esos roles no podrían ni apuntar su
-- resultado. La primera vez pasó justo eso y el resumen dijo "2 de 3",
-- que no significaba nada.
drop table if exists public.resultado;
create table public.resultado (n serial, prueba text, bien boolean, detalle text);
grant all on public.resultado to authenticated, anon;
grant all on sequence public.resultado_n_seq to authenticated, anon;

-- Las tablas las creó este mismo usuario, y el dueño de una tabla se
-- salta RLS por defecto. Sin esto, TODAS las pruebas saldrían verdes sin
-- que las políticas hicieran nada.
alter table public.suggestions force row level security;
alter table public.suggestion_votes force row level security;
grant select, insert, update, delete on public.suggestions to authenticated;
grant select, insert, update, delete on public.suggestion_votes to authenticated;

-- =====================================================================
-- A escribe una sugerencia normal
-- =====================================================================
set role authenticated;
set request.jwt.claims = '{"sub":"aaaaaaaa-1111-4111-8111-111111111111","role":"authenticated"}';

insert into public.suggestions (user_id, author_name, kind, title, body)
values (:A, 'Álvaro', 'idea', 'Modo oscuro automático de noche',
        'Que a las 22:00 se ponga solo el fondo Noche.');

insert into public.suggestions (user_id, author_name, kind, title, body)
values (:A, 'Álvaro', 'fallo', 'Se me borró una comida', 'Al girar el móvil.');

-- Una tapada, para comprobar que su autor sí la ve y los demás no.
--
-- `reset role` es lo que hace que esto funcione: tapar una sugerencia es
-- cosa tuya desde el SQL Editor, y el disparador distingue quién escribe
-- por el rol de la conexión. Si esto se quedara como `authenticated`, el
-- candado revertiría el cambio —bien hecho por su parte— y la prueba de
-- abajo saldría roja sin que hubiera nada roto.
reset role;
update public.suggestions set hidden = true where title = 'Se me borró una comida';
set role authenticated;

-- =====================================================================
-- PRUEBA DE CONTROL — esta TIENE que salir bien
-- =====================================================================
set role authenticated;
set request.jwt.claims = '{"sub":"bbbbbbbb-2222-4222-8222-222222222222","role":"authenticated"}';

insert into public.resultado (prueba, bien, detalle)
select 'CONTROL · B lee la sugerencia de A (tiene que poder)',
       count(*) = 1,
       'filas visibles: ' || count(*)
from public.suggestions where title = 'Modo oscuro automático de noche';

-- =====================================================================
-- 1. Publicar firmando como otro
-- =====================================================================
do $$
begin
  insert into public.suggestions (user_id, author_name, title)
  values ('aaaaaaaa-1111-4111-8111-111111111111', 'Álvaro', 'Esto lo escribe B haciéndose pasar por A');
  insert into public.resultado (prueba, bien, detalle)
  values ('B publica firmando como A', false, 'ENTRÓ: la política de insert no filtra');
exception when others then
  insert into public.resultado (prueba, bien, detalle)
  values ('B publica firmando como A', true, 'rechazado: ' || substr(sqlerrm, 1, 60));
end $$;

-- =====================================================================
-- 2. Editar la sugerencia de otro
-- =====================================================================
update public.suggestions
   set title = 'Título secuestrado por B'
 where title = 'Modo oscuro automático de noche';

insert into public.resultado (prueba, bien, detalle)
select 'B edita la sugerencia de A',
       count(*) = 0,
       'filas cambiadas: ' || count(*)
from public.suggestions where title = 'Título secuestrado por B';

-- =====================================================================
-- 3. Borrar la sugerencia de otro
-- =====================================================================
delete from public.suggestions where title = 'Modo oscuro automático de noche';

insert into public.resultado (prueba, bien, detalle)
select 'B borra la sugerencia de A',
       count(*) = 1,
       case when count(*) = 1 then 'sigue ahí' else 'DESAPARECIÓ' end
from public.suggestions where title = 'Modo oscuro automático de noche';

-- =====================================================================
-- 4. Ver una sugerencia tapada de otro
-- =====================================================================
insert into public.resultado (prueba, bien, detalle)
select 'B ve la sugerencia tapada de A',
       count(*) = 0,
       'filas visibles: ' || count(*)
from public.suggestions where title = 'Se me borró una comida';

-- =====================================================================
-- 5. Votar. Una vez sí; dos, no.
-- =====================================================================
insert into public.suggestion_votes (suggestion_id, user_id)
select id, :B from public.suggestions where title = 'Modo oscuro automático de noche';

insert into public.resultado (prueba, bien, detalle)
select 'CONTROL · el voto de B cuenta (tiene que contar)',
       vote_count = 1,
       'vote_count = ' || vote_count
from public.suggestions where title = 'Modo oscuro automático de noche';

do $$
declare
  objetivo uuid;
begin
  select id into objetivo from public.suggestions where title = 'Modo oscuro automático de noche';
  insert into public.suggestion_votes (suggestion_id, user_id)
  values (objetivo, 'bbbbbbbb-2222-4222-8222-222222222222');
  insert into public.resultado (prueba, bien, detalle)
  values ('B vota dos veces la misma', false, 'ENTRÓ: se puede votar repetido');
exception when others then
  insert into public.resultado (prueba, bien, detalle)
  values ('B vota dos veces la misma', true, 'rechazado: ' || substr(sqlerrm, 1, 40));
end $$;

-- Votar en nombre de otro
do $$
declare
  objetivo uuid;
begin
  select id into objetivo from public.suggestions where title = 'Modo oscuro automático de noche';
  insert into public.suggestion_votes (suggestion_id, user_id)
  values (objetivo, 'aaaaaaaa-1111-4111-8111-111111111111');
  insert into public.resultado (prueba, bien, detalle)
  values ('B vota en nombre de A', false, 'ENTRÓ: se puede votar por otro');
exception when others then
  insert into public.resultado (prueba, bien, detalle)
  values ('B vota en nombre de A', true, 'rechazado: ' || substr(sqlerrm, 1, 40));
end $$;

-- =====================================================================
-- 6. A, dueño de su fila, intenta ascenderla
-- =====================================================================
set request.jwt.claims = '{"sub":"aaaaaaaa-1111-4111-8111-111111111111","role":"authenticated"}';

update public.suggestions
   set status = 'hecha', vote_count = 9999, hidden = false,
       user_id = 'bbbbbbbb-2222-4222-8222-222222222222'
 where title = 'Modo oscuro automático de noche';

reset role;
insert into public.resultado (prueba, bien, detalle)
select 'A se asciende su idea a "hecha"', status = 'nueva', 'status = ' || status
from public.suggestions where title = 'Modo oscuro automático de noche';

insert into public.resultado (prueba, bien, detalle)
select 'A se pone 9999 votos', vote_count = 1, 'vote_count = ' || vote_count
from public.suggestions where title = 'Modo oscuro automático de noche';

insert into public.resultado (prueba, bien, detalle)
select 'A regala su sugerencia a B', user_id = :A, 'user_id acaba en ' || right(user_id::text, 4)
from public.suggestions where title = 'Modo oscuro automático de noche';

-- Pero editar el texto propio SÍ tiene que funcionar.
set role authenticated;
set request.jwt.claims = '{"sub":"aaaaaaaa-1111-4111-8111-111111111111","role":"authenticated"}';
update public.suggestions
   set body = 'Corrijo: a las 21:00 mejor.'
 where title = 'Modo oscuro automático de noche';

insert into public.resultado (prueba, bien, detalle)
select 'CONTROL · A corrige su propio texto (tiene que poder)',
       body like 'Corrijo%', 'body = ' || substr(body, 1, 20)
from public.suggestions where title = 'Modo oscuro automático de noche';

-- =====================================================================
-- 7. Sin cuenta no se lee nada
-- =====================================================================
reset role;
set role anon;
set request.jwt.claims = '{}';

-- Sin cuenta puede pasar una de dos cosas, y las dos están bien: que la
-- consulta devuelva cero filas (lo para RLS) o que ni siquiera le dejen
-- mirar la tabla (lo para el revoke de schema.sql). La primera versión
-- de esta prueba solo contemplaba la primera, así que el error se comía
-- la fila del resultado y la prueba desaparecía de la lista en vez de
-- salir en verde.
do $$
declare
  visibles integer;
begin
  select count(*) into visibles from public.suggestions;
  insert into public.resultado (prueba, bien, detalle)
  values ('Alguien sin cuenta lee el buzón', visibles = 0, 'filas visibles: ' || visibles);
exception when others then
  insert into public.resultado (prueba, bien, detalle)
  values ('Alguien sin cuenta lee el buzón', true, 'ni puede mirar la tabla: ' || substr(sqlerrm, 1, 40));
end $$;

-- =====================================================================
-- 8. Cinco al día
-- =====================================================================
reset role;
set role authenticated;
set request.jwt.claims = '{"sub":"bbbbbbbb-2222-4222-8222-222222222222","role":"authenticated"}';

do $$
declare
  i integer;
  metidas integer := 0;
begin
  for i in 1..9 loop
    begin
      insert into public.suggestions (user_id, author_name, title)
      values ('bbbbbbbb-2222-4222-8222-222222222222', 'B', 'Spam número ' || i);
      metidas := metidas + 1;
    exception when others then
      -- Se traga el error de ESTA fila y sigue. Si el bloque envolviera
      -- el bucle entero, Postgres desharía también las que sí entraron y
      -- el recuento saldría en cero: parecería un límite durísimo cuando
      -- en realidad no habría límite ninguno.
      null;
    end;
  end loop;

  insert into public.resultado (prueba, bien, detalle)
  values ('Nueve sugerencias de golpe', metidas = 5, 'entraron ' || metidas || ' de 9');
end $$;

-- =====================================================================
-- 9. Textos imposibles
-- =====================================================================
do $$
begin
  insert into public.suggestions (user_id, title)
  values ('aaaaaaaa-1111-4111-8111-111111111111', repeat('x', 400));
  insert into public.resultado (prueba, bien, detalle)
  values ('Título de 400 caracteres', false, 'ENTRÓ');
exception when others then
  insert into public.resultado (prueba, bien, detalle)
  values ('Título de 400 caracteres', true, 'rechazado');
end $$;

do $$
begin
  insert into public.suggestions (user_id, title, body)
  values ('aaaaaaaa-1111-4111-8111-111111111111', 'Corto', repeat('y', 9000));
  insert into public.resultado (prueba, bien, detalle)
  values ('Texto de 9000 caracteres', false, 'ENTRÓ');
exception when others then
  insert into public.resultado (prueba, bien, detalle)
  values ('Texto de 9000 caracteres', true, 'rechazado');
end $$;

do $$
begin
  insert into public.suggestions (user_id, title, status)
  values ('aaaaaaaa-1111-4111-8111-111111111111', 'Nazco hecha', 'hecha');
  insert into public.resultado (prueba, bien, detalle)
  values ('Nacer ya con status "hecha"', false, 'ENTRÓ: se puede publicar algo ya marcado como hecho');
exception when others then
  insert into public.resultado (prueba, bien, detalle)
  values ('Nacer ya con status "hecha"', true, 'rechazado');
end $$;

-- =====================================================================
-- Resultado
-- =====================================================================
reset role;
reset request.jwt.claims;
update public.signup_control set mode = 'invitacion';

\pset format aligned
\pset border 2
\echo ''
\echo '  ── Ataque al buzón de sugerencias ──'
\echo ''

select
  case when bien then '  ✓' else '  ✗ FALLA' end as "Bien",
  prueba as "Prueba",
  detalle as "Qué pasó"
from public.resultado order by n;

select
  count(*) filter (where bien) || ' de ' || count(*) || ' bien'
  || case when count(*) filter (where not bien) > 0
          then '   ⚠️  HAY AGUJEROS' else '   todo cerrado' end as "Resumen"
from resultado;
