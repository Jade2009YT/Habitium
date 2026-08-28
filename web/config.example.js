// Copia este archivo a `config.js` y rellena tus dos valores de Supabase.
// `config.js` está en .gitignore, así que tus claves no se suben al repo.
//
// Dónde encontrarlos: supabase.com → tu proyecto → Project Settings → API
//   - Project URL → SUPABASE_URL — la raíz, SIN /rest/v1 al final.
//   - La clave pública → SUPABASE_ANON_KEY. Según cuándo se creara tu
//     proyecto la verás como `anon / public` (una cadena larga que empieza
//     por "eyJ...") o, en el formato nuevo, como `publishable` (empieza por
//     "sb_publishable_"). Las dos valen y significan lo mismo aquí.
//
// Sí, esa clave acaba siendo visible para cualquiera que abra la web —
// es así por diseño, va embebida en el cliente igual que en la app de
// iPhone. Lo que protege tus datos NO es esconder esta clave, sino el Row
// Level Security del esquema (supabase/schema.sql): cada política exige
// `auth.uid() = user_id`, así que con esta clave y sin iniciar sesión no
// se puede leer ni escribir absolutamente nada. Lo que nunca debe salir
// de Supabase es la otra clave — la marcada como `service_role` / `secret`
// (empieza por "sb_secret_" en el formato nuevo). Esa sí se salta el RLS,
// y no se usa en ningún sitio de este proyecto.

window.HABITIUM_CONFIG = {
  SUPABASE_URL: "https://tu-proyecto.supabase.co",
  SUPABASE_ANON_KEY: "tu_clave_anon_aqui",
};
