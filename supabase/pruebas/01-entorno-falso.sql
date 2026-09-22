-- Un Supabase de mentira, con la forma justa para que schema.sql se
-- pueda aplicar tal cual en un Postgres normal: los roles que Supabase
-- crea de serie, el esquema auth con su tabla users, y auth.uid()
-- leyendo el JWT de la petición igual que allí.
--
-- No se parece a Supabase en nada más, y no hace falta: lo que se quiere
-- probar es el esquema, no Supabase.
--
-- NO se ejecuta en tu proyecto de verdad. Ver LEEME.md de esta carpeta.

create role anon nologin;
create role authenticated nologin;
create role service_role nologin;

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
alter default privileges in schema public grant all on tables to anon, authenticated, service_role;
grant usage on schema public to anon, authenticated;
