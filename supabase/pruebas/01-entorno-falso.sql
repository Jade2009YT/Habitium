-- Un Supabase de mentira, con la forma justa para que schema.sql se
-- pueda aplicar tal cual en un Postgres normal: los roles que Supabase
-- crea de serie, el esquema auth con su tabla users, y auth.uid()
-- leyendo el JWT de la petición igual que allí.
--
-- No se parece a Supabase en nada más, y no hace falta: lo que se quiere
-- probar es el esquema, no Supabase.
--
-- NO se ejecuta en tu proyecto de verdad. Ver LEEME.md de esta carpeta.

-- Los roles pertenecen al CLUSTER, no a la base de datos: borrar la base
-- y volver a crearla NO se los lleva por delante. Sin este bloque, la
-- segunda vez que ejecutas esto revienta en la primera línea, y como
-- todo lo demás va detrás, el resto del archivo no llega a aplicarse:
-- te quedas con una base vacía y un ataque que sale verde porque no hay
-- nada que atacar.
do $$
begin
  create role anon nologin;
exception when duplicate_object then null;
end $$;
do $$
begin
  create role authenticated nologin;
exception when duplicate_object then null;
end $$;
do $$
begin
  create role service_role nologin;
exception when duplicate_object then null;
end $$;

create extension if not exists pgcrypto;
create schema if not exists auth;
create table auth.users (
  id uuid primary key default gen_random_uuid(),
  email text unique,
  raw_user_meta_data jsonb,
  email_confirmed_at timestamptz,
  created_at timestamptz default now()
);
create or replace function auth.uid() returns uuid language sql stable as $$
  select nullif(current_setting('request.jwt.claims', true)::jsonb ->> 'sub', '')::uuid;
$$;

-- auth.role() dice con qué papel llega la petición. El esquema ya no lo
-- usa, pero se deja porque Supabase lo tiene y así este entorno se le
-- parece más.
--
-- Ojo al `nullif` de dentro, que va ANTES del cast y no después: cuando
-- no hay token, current_setting devuelve la cadena vacía, y ''::jsonb no
-- es un JSON vacío — es un error que tumba la consulta entera. Así está
-- escrito en el Supabase de verdad, y por algo será.
create or replace function auth.role() returns text language sql stable as $$
  select coalesce(
    nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role',
    'anon'
  );
$$;
alter default privileges in schema public grant all on tables to anon, authenticated, service_role;
grant usage on schema public to anon, authenticated;
