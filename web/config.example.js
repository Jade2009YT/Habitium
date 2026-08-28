// Copia este archivo a `config.js` y rellena tus dos valores de Supabase.
// `config.js` está en .gitignore, así que tus claves no se suben al repo.
//
// Dónde encontrarlos: supabase.com → tu proyecto → Project Settings → API
//   - Project URL       → SUPABASE_URL
//   - anon / public key → SUPABASE_ANON_KEY
//
// Sí, la anon key acaba siendo visible para cualquiera que abra la web —
// es así por diseño, va embebida en el cliente igual que en la app de
// iPhone. Lo que protege tus datos NO es esconder esta clave, sino el Row
// Level Security del esquema (supabase/schema.sql): cada política exige
// `auth.uid() = user_id`, así que con esta clave y sin iniciar sesión no
// se puede leer ni escribir absolutamente nada. Lo que nunca debe salir
// de Supabase es la *service_role* key — esa sí se salta el RLS, y no se
// usa en ningún sitio de este proyecto.

window.HABITIUM_CONFIG = {
  SUPABASE_URL: "https://tu-proyecto.supabase.co",
  SUPABASE_ANON_KEY: "tu_clave_anon_aqui",
};
