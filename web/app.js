// Habitium web — interfaz.
//
// Ya NO habla con Supabase directamente: todo pasa por store.js, que
// guarda en IndexedDB y sincroniza por detrás. Esto es lo que hace que
// la app arranque al instante, funcione sin conexión, y muestre lo mismo
// que el iPhone en cuanto haya red — la misma arquitectura que
// SwiftData + CloudSyncService en iOS.
//
// Consecuencia práctica para el código de abajo: las funciones de carga
// son síncronas contra datos ya presentes, y cualquier escritura repinta
// al momento (optimista) sin esperar al servidor. store.onChange() se
// encarga de volver a pintar cuando llega algo nuevo de la nube.

import { createClient } from "https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/+esm";
import * as store from "./store.js";
import * as player from "./player.js";
import * as prog from "./progression.js";

const cfg = window.HABITIUM_CONFIG;
const isConfigured =
  cfg &&
  typeof cfg.SUPABASE_URL === "string" &&
  typeof cfg.SUPABASE_ANON_KEY === "string" &&
  cfg.SUPABASE_URL.startsWith("http") &&
  !cfg.SUPABASE_URL.includes("tu-proyecto") &&
  !cfg.SUPABASE_ANON_KEY.includes("tu_clave");

const $ = (id) => document.getElementById(id);

if (!isConfigured) {
  $("boot").hidden = true;
  $("config-error").hidden = false;
  throw new Error("Habitium: falta web/config.js o sigue con los valores de ejemplo.");
}

const supabase = createClient(cfg.SUPABASE_URL, cfg.SUPABASE_ANON_KEY);

store.configure(supabase, async () => (await supabase.auth.getUser()).data?.user?.id ?? null);

// El service worker es opcional: si el navegador no lo soporta o la
// página se sirve por http://, la app funciona igual, solo que sin
// arranque instantáneo ni modo sin conexión.
if ("serviceWorker" in navigator) {
  window.addEventListener("load", () => {
    navigator.serviceWorker.register("./sw.js").catch((e) => console.warn("SW:", e));
  });
}

// ── Utilidades ──────────────────────────────────────────────────────

const startOfToday = () => {
  const d = new Date();
  d.setHours(0, 0, 0, 0);
  return d;
};
const startOfTomorrow = () => {
  const d = startOfToday();
  d.setDate(d.getDate() + 1);
  return d;
};
const startOfMonth = () => {
  const d = new Date();
  return new Date(d.getFullYear(), d.getMonth(), 1);
};
const startOfNextMonth = () => {
  const d = new Date();
  return new Date(d.getFullYear(), d.getMonth() + 1, 1);
};
const nowISO = () => new Date().toISOString();

const inRange = (iso, from, to) => {
  const t = new Date(iso).getTime();
  return t >= from.getTime() && t < to.getTime();
};
const sameDay = (iso, day) => {
  const d = new Date(iso);
  d.setHours(0, 0, 0, 0);
  return d.getTime() === day.getTime();
};

let currencyCode = "EUR";
const money = (v) =>
  new Intl.NumberFormat("es-ES", {
    style: "currency",
    currency: currencyCode,
    maximumFractionDigits: 2,
  }).format(v ?? 0);

const timeOf = (iso) =>
  new Date(iso).toLocaleTimeString("es-ES", { hour: "2-digit", minute: "2-digit" });
const dayOf = (iso) =>
  new Date(iso).toLocaleDateString("es-ES", { day: "numeric", month: "short" });
const minutesToTime = (m) =>
  `${String(Math.floor(m / 60)).padStart(2, "0")}:${String(m % 60).padStart(2, "0")}`;

const esc = (s) =>
  String(s ?? "").replace(/[&<>"']/g, (c) =>
    ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c])
  );

const byDateDesc = (a, b) => new Date(b.date) - new Date(a.date);

// ── Indicador de sincronización ─────────────────────────────────────

function renderSyncBanner() {
  const b = $("sync-banner");
  const { online, pending, lastError } = store.syncState;

  if (!online) {
    b.className = "banner is-info";
    b.textContent =
      pending > 0
        ? `Sin conexión · ${pending} cambio${pending === 1 ? "" : "s"} se subirá${pending === 1 ? "" : "n"} al volver`
        : "Sin conexión · puedes seguir usando la app";
    b.hidden = false;
    return;
  }

  if (lastError) {
    b.className = "banner";
    b.textContent = `Problema al sincronizar: ${lastError}`;
    b.hidden = false;
    return;
  }

  if (pending > 0) {
    b.className = "banner is-info";
    b.textContent = `Subiendo ${pending} cambio${pending === 1 ? "" : "s"}…`;
    b.hidden = false;
    return;
  }

  b.hidden = true;
}

// ── Autenticación ───────────────────────────────────────────────────

let authMode = "signin";

function setAuthMode(mode) {
  authMode = mode;
  $("tab-signin").classList.toggle("is-active", mode === "signin");
  $("tab-signup").classList.toggle("is-active", mode === "signup");
  $("auth-submit").textContent = mode === "signin" ? "Iniciar sesión" : "Crear cuenta";
  $("auth-password").autocomplete = mode === "signin" ? "current-password" : "new-password";
  $("forgot-password").hidden = mode !== "signin";
  setAuthMessage("");
}

function setAuthMessage(text, ok = false) {
  const el = $("auth-message");
  el.textContent = text;
  el.classList.toggle("is-ok", ok);
}

$("tab-signin").addEventListener("click", () => setAuthMode("signin"));
$("tab-signup").addEventListener("click", () => setAuthMode("signup"));

$("auth-form").addEventListener("submit", async (e) => {
  e.preventDefault();
  const email = $("auth-email").value.trim();
  const password = $("auth-password").value;
  const submit = $("auth-submit");

  submit.disabled = true;
  setAuthMessage("");

  const { data, error } =
    authMode === "signup"
      ? await supabase.auth.signUp({ email, password })
      : await supabase.auth.signInWithPassword({ email, password });

  submit.disabled = false;
  if (error) return setAuthMessage(error.message);

  if (authMode === "signup" && !data.session) {
    setAuthMessage(`Te hemos enviado un enlace a ${email}. Ábrelo y vuelve aquí.`, true);
  }
});

$("forgot-password").addEventListener("click", async () => {
  const email = $("auth-email").value.trim();
  if (!email) return setAuthMessage("Escribe tu correo primero.");
  const { error } = await supabase.auth.resetPasswordForEmail(email, {
    redirectTo: window.location.href,
  });
  setAuthMessage(
    error ? error.message : "Te hemos enviado un enlace para restablecer tu contraseña.",
    !error
  );
});

async function doSignOut() {
  // Se borra lo local: en un dispositivo compartido (el iPad del cole)
  // los datos de una cuenta no deben quedar accesibles a la siguiente.
  await store.wipe();
  await supabase.auth.signOut();
}
$("sign-out").addEventListener("click", doSignOut);
$("sign-out-2").addEventListener("click", doSignOut);

// ── Navegación ──────────────────────────────────────────────────────

const NAV = [
  { id: "home", label: "Inicio", icon: "🏠" },
  { id: "progress", label: "Progreso", icon: "🏆" },
  { id: "nutrition", label: "Nutrición", icon: "🍎" },
  { id: "planner", label: "Agenda", icon: "📅" },
  { id: "finance", label: "Finanzas", icon: "💶" },
  { id: "habits", label: "Hábitos", icon: "✅" },
  { id: "medication", label: "Medicación", icon: "💊" },
  { id: "settings", label: "Ajustes", icon: "⚙️" },
];

// La barra del móvil no puede con 8 destinos sin quedar ilegible.
// Medicación y Ajustes se alcanzan desde las tarjetas de Inicio, y
// Progreso desde la tarjeta de nivel que está arriba del todo.
const MOBILE_TABS = ["home", "nutrition", "planner", "finance", "habits"];

function buildNav() {
  $("side-nav").innerHTML = NAV.map(
    (n) => `<button class="side-item" data-view="${n.id}" type="button" role="tab">
              <span aria-hidden="true">${n.icon}</span>${n.label}
            </button>`
  ).join("");

  $("tabbar").innerHTML = NAV.filter((n) => MOBILE_TABS.includes(n.id))
    .map(
      (n) => `<button class="tab" data-view="${n.id}" type="button" role="tab">
                <span aria-hidden="true">${n.icon}</span>${n.label}
              </button>`
    )
    .join("");

  document.querySelectorAll("[data-view]").forEach((el) => {
    el.addEventListener("click", () => go(el.dataset.view));
    // Las tarjetas son <article role="button">, no <button>, así que el
    // teclado no las activa solo.
    if (el.getAttribute("role") === "button" && el.tagName !== "BUTTON") {
      el.addEventListener("keydown", (e) => {
        if (e.key === "Enter" || e.key === " ") {
          e.preventDefault();
          go(el.dataset.view);
        }
      });
    }
  });
}

let currentView = "home";

function go(view) {
  currentView = view;
  NAV.forEach((n) => ($(`view-${n.id}`).hidden = n.id !== view));
  document.querySelectorAll(".side-item").forEach((el) =>
    el.classList.toggle("is-active", el.dataset.view === view)
  );
  document.querySelectorAll(".tab").forEach((el) =>
    el.classList.toggle("is-active", el.dataset.view === view)
  );
  $("topbar-title").textContent = NAV.find((n) => n.id === view)?.label ?? "";
  window.scrollTo({ top: 0 });
  render();
}

/** Repinta la vista activa desde los datos locales. */
async function render() {
  renderSyncBanner();
  await {
    home: loadHome,
    progress: loadProgress,
    nutrition: loadNutrition,
    planner: loadPlanner,
    finance: loadFinance,
    habits: loadHabits,
    medication: loadMedication,
    settings: loadSettings,
  }[currentView]?.();
}

store.onChange(render);

$("refresh").addEventListener("click", () => store.sync());

/** Cablea todos los botones .delete de una lista contra una tabla. */
function wireDelete(list, table) {
  list.querySelectorAll("[data-del]").forEach((btn) => {
    btn.addEventListener("click", () => store.remove(table, btn.dataset.del));
  });
}

// ── Nutrición ───────────────────────────────────────────────────────

const MEALS = {
  breakfast: { name: "Desayuno", icon: "🌅" },
  lunch: { name: "Almuerzo", icon: "☀️" },
  dinner: { name: "Cena", icon: "🌙" },
  snack: { name: "Snack", icon: "🥕" },
};

const todaysFood = async () =>
  (await store.all("food_entries"))
    .filter((e) => inRange(e.date, startOfToday(), startOfTomorrow()))
    .sort((a, b) => new Date(a.date) - new Date(b.date));

const nutritionGoal = () => store.getSingleton("nutrition_goals");

async function loadNutrition() {
  const entries = await todaysFood();
  $("food-total").textContent = `${Math.round(entries.reduce((s, e) => s + (e.calories ?? 0), 0))} kcal`;

  const pesos = (await store.all("weight_entries")).sort(byDateDesc);
  $("weight-last").textContent = pesos.length
    ? `último: ${pesos[0].weight_kg} kg · ${dayOf(pesos[0].date)}`
    : "";

  const list = $("food-list");
  if (!entries.length) {
    list.innerHTML = `<li class="empty">Aún no has registrado nada hoy.</li>`;
    return;
  }

  list.innerHTML = entries
    .map(
      (e) => `
      <li class="row">
        <div class="row-icon">${MEALS[e.meal_type]?.icon ?? "🍽️"}</div>
        <div class="row-main">
          <div class="row-title">${esc(e.name)}</div>
          <div class="row-sub">
            <span>${MEALS[e.meal_type]?.name ?? ""} · ${timeOf(e.date)}</span>
            <span>P ${Math.round(e.protein_grams)} · C ${Math.round(e.carbs_grams)} · G ${Math.round(e.fat_grams)} g</span>
          </div>
        </div>
        <div class="row-value">${Math.round(e.calories)} kcal</div>
        <button class="delete" data-del="${e.id}" title="Eliminar" aria-label="Eliminar">✕</button>
      </li>`
    )
    .join("");

  wireDelete(list, "food_entries");
}

$("food-form").addEventListener("submit", async (e) => {
  e.preventDefault();
  const entry = await store.insert("food_entries", {
    name: $("food-name").value.trim(),
    date: nowISO(),
    meal_type: $("food-meal").value,
    source: "manual",
    calories: Number($("food-calories").value) || 0,
    protein_grams: Number($("food-protein").value) || 0,
    carbs_grams: Number($("food-carbs").value) || 0,
    fat_grams: Number($("food-fat").value) || 0,
  });
  e.target.reset();
  // La clave lleva el id de la comida y NO la fecha, igual que en iOS
  // (NutritionRepository): cada comida se premia una vez en su vida.
  await awardXP("mealLogged", `meal:${idKey(entry.id)}`);
});

// ── Agenda ──────────────────────────────────────────────────────────

async function loadPlanner() {
  const tasks = (await store.all("planner_tasks")).sort((a, b) => {
    if (!a.due_date) return 1;
    if (!b.due_date) return -1;
    return new Date(a.due_date) - new Date(b.due_date);
  });

  const pending = tasks.filter((t) => !t.is_completed);
  $("task-count").textContent = String(pending.length);
  renderTasks($("task-list"), pending, "No tienes tareas pendientes. 🎉");
  renderTasks($("task-done-list"), tasks.filter((t) => t.is_completed), "Nada completado todavía.");
}

function renderTasks(list, tasks, emptyText) {
  if (!tasks.length) {
    list.innerHTML = `<li class="empty">${emptyText}</li>`;
    return;
  }

  const today = startOfToday().getTime();
  list.innerHTML = tasks
    .map((t) => {
      const overdue =
        !t.is_completed && t.due_date && new Date(t.due_date).setHours(0, 0, 0, 0) < today;
      return `
      <li class="row">
        <button class="check ${t.is_completed ? "is-checked" : ""}"
                data-toggle="${t.id}" data-done="${t.is_completed}"
                aria-label="Marcar como completada">✓</button>
        <div class="row-main">
          <div class="row-title ${t.is_completed ? "is-done" : ""}">${esc(t.title)}</div>
          ${t.due_date ? `<div class="row-sub"><span>${overdue ? "⚠️ " : ""}${dayOf(t.due_date)}</span></div>` : ""}
        </div>
        <button class="delete" data-del="${t.id}" title="Eliminar" aria-label="Eliminar">✕</button>
      </li>`;
    })
    .join("");

  list.querySelectorAll("[data-toggle]").forEach((btn) => {
    btn.addEventListener("click", async () => {
      const completing = btn.dataset.done !== "true";
      const task = await store.update("planner_tasks", btn.dataset.toggle, {
        is_completed: completing,
      });
      // Solo se premia completar, nunca desmarcar. La clave lleva el id
      // de la tarea y no la fecha: una tarea concreta se premia una vez
      // en su vida, aunque se marque y desmarque en días distintos.
      if (completing && task) {
        await awardXP(
          task.is_focus ? "focusTaskCompleted" : "taskCompleted",
          `task:${idKey(task.id)}`
        );
      }
    });
  });

  wireDelete(list, "planner_tasks");
}

$("task-form").addEventListener("submit", async (e) => {
  e.preventDefault();
  const due = $("task-due").value;
  await store.insert("planner_tasks", {
    title: $("task-title").value.trim(),
    // El input date da "YYYY-MM-DD" sin hora; mediodía evita que un
    // desfase de zona horaria lo mueva al día anterior.
    due_date: due ? new Date(`${due}T12:00:00`).toISOString() : null,
    is_completed: false,
    priority: "medium",
    is_focus: false,
  });
  e.target.reset();
});

// ── Finanzas ────────────────────────────────────────────────────────

const CATEGORIES = {
  food: { name: "Comida", icon: "🍽️" },
  leisure: { name: "Ocio", icon: "🎮" },
  savings: { name: "Ahorro", icon: "🏦" },
  services: { name: "Servicios", icon: "⚡" },
  transport: { name: "Transporte", icon: "🚗" },
  health: { name: "Salud", icon: "❤️" },
  salary: { name: "Salario", icon: "💰" },
  other: { name: "Otro", icon: "•••" },
};

const monthTransactions = async () =>
  (await store.all("transactions"))
    .filter((t) => inRange(t.date, startOfMonth(), startOfNextMonth()))
    .sort(byDateDesc);

async function budgetSettings() {
  const b = await store.getSingleton("budget_settings");
  if (b?.currency_code) currencyCode = b.currency_code;
  return b;
}

async function loadFinance() {
  const budget = await budgetSettings(); // fija la moneda antes de formatear
  const txs = await monthTransactions();

  const income = txs.filter((t) => t.type === "income").reduce((s, t) => s + t.amount, 0);
  const expense = txs.filter((t) => t.type === "expense").reduce((s, t) => s + t.amount, 0);
  const monthly = budget?.monthly_budget ?? 0;

  $("fin-income").textContent = money(income);
  $("fin-expense").textContent = money(expense);
  $("fin-available").textContent = money(Math.max(0, monthly - expense));

  const byCategory = {};
  for (const t of txs) {
    if (t.type !== "expense") continue;
    byCategory[t.category] = (byCategory[t.category] ?? 0) + t.amount;
  }
  const ordered = Object.entries(byCategory).sort((a, b) => b[1] - a[1]);
  const max = ordered[0]?.[1] ?? 0;

  $("fin-categories").innerHTML = ordered.length
    ? ordered
        .map(
          ([cat, amount]) => `
        <div class="cat-bar">
          <div class="cat-name">${CATEGORIES[cat]?.icon ?? ""} ${CATEGORIES[cat]?.name ?? cat}</div>
          <div class="track"><div class="track-fill orange" style="width:${(amount / max) * 100}%"></div></div>
          <div class="cat-amount">${money(amount)}</div>
        </div>`
        )
        .join("")
    : `<p class="empty">Sin gastos este mes.</p>`;

  const list = $("tx-list");
  if (!txs.length) {
    list.innerHTML = `<li class="empty">Sin movimientos este mes.</li>`;
    return;
  }

  list.innerHTML = txs
    .map((t) => {
      const isIncome = t.type === "income";
      return `
      <li class="row">
        <div class="row-icon">${CATEGORIES[t.category]?.icon ?? "•"}</div>
        <div class="row-main">
          <div class="row-title">${esc(t.note || CATEGORIES[t.category]?.name || "Movimiento")}</div>
          <div class="row-sub"><span>${CATEGORIES[t.category]?.name ?? ""} · ${dayOf(t.date)}</span></div>
        </div>
        <div class="row-value ${isIncome ? "is-income" : "is-expense"}">${isIncome ? "+" : "−"}${money(t.amount)}</div>
        <button class="delete" data-del="${t.id}" title="Eliminar" aria-label="Eliminar">✕</button>
      </li>`;
    })
    .join("");

  wireDelete(list, "transactions");
}

$("tx-form").addEventListener("submit", async (e) => {
  e.preventDefault();
  await store.insert("transactions", {
    amount: Number($("tx-amount").value) || 0,
    type: $("tx-type").value,
    category: $("tx-category").value,
    note: $("tx-note").value.trim() || null,
    date: nowISO(),
  });
  e.target.reset();
});

// ── Hábitos ─────────────────────────────────────────────────────────

// Mismas plantillas que HabitTemplate.swift en iOS.
const HABIT_TEMPLATES = [
  { name: "Tiempo de pantalla", kind: "numeric", target: 3, dir: "atMost", unit: "h" },
  { name: "Agua", kind: "numeric", target: 8, dir: "atLeast", unit: "vasos" },
  { name: "Dormir", kind: "numeric", target: 8, dir: "atLeast", unit: "h" },
  { name: "Ejercicio", kind: "checkbox" },
  { name: "Leer", kind: "checkbox" },
  { name: "Meditar", kind: "checkbox" },
];

function syncHabitKindFields() {
  const numeric = $("habit-kind").value === "numeric";
  $("habit-target").hidden = !numeric;
  $("habit-direction").hidden = !numeric;
  $("habit-unit").hidden = !numeric;
}
$("habit-kind").addEventListener("change", syncHabitKindFields);

$("habit-templates").innerHTML = HABIT_TEMPLATES.map(
  (t, i) => `<button class="chip" type="button" data-tpl="${i}">${esc(t.name)}</button>`
).join("");

$("habit-templates").querySelectorAll("[data-tpl]").forEach((btn) => {
  btn.addEventListener("click", () => {
    const t = HABIT_TEMPLATES[Number(btn.dataset.tpl)];
    $("habit-name").value = t.name;
    $("habit-kind").value = t.kind;
    syncHabitKindFields();
    $("habit-target").value = t.target ?? "";
    $("habit-direction").value = t.dir ?? "atLeast";
    $("habit-unit").value = t.unit ?? "";
  });
});

/** ¿Cumple este registro el objetivo? Misma regla que
 *  HabitStatus.isGoalMetToday en iOS. */
function goalMet(habit, log) {
  if (!log) return false;
  if (habit.kind === "checkbox") return log.is_completed;
  if (log.value == null || habit.target_value == null) return false;
  return habit.goal_direction === "atMost"
    ? log.value <= habit.target_value
    : log.value >= habit.target_value;
}

/** Días consecutivos cumpliendo el objetivo, hacia atrás desde hoy —
 *  mismo recorrido que HabitRepository.streak(for:) en iOS. */
function streakFor(habit, logs) {
  const byDay = new Map();
  for (const log of logs) {
    const d = new Date(log.date);
    d.setHours(0, 0, 0, 0);
    byDay.set(d.getTime(), log);
  }

  const cursor = startOfToday();
  // Si hoy aún no está cumplido, la racha se mide desde ayer — no se
  // rompe solo porque el día no haya terminado todavía.
  if (!goalMet(habit, byDay.get(cursor.getTime()))) cursor.setDate(cursor.getDate() - 1);

  let streak = 0;
  while (goalMet(habit, byDay.get(cursor.getTime()))) {
    streak += 1;
    cursor.setDate(cursor.getDate() - 1);
  }
  return streak;
}

const logForToday = (logs, habitId) =>
  logs.find((l) => l.habit_id === habitId && sameDay(l.date, startOfToday()));

async function fetchHabits() {
  const habits = (await store.all("habits"))
    .filter((h) => h.is_active)
    .sort((a, b) => (a.sort_order ?? 0) - (b.sort_order ?? 0));
  return { habits, logs: await store.all("habit_logs") };
}

async function loadHabits() {
  const { habits, logs } = await fetchHabits();
  const list = $("habit-list");

  if (!habits.length) {
    list.innerHTML = `<li class="empty">Aún no tienes hábitos. Añade uno arriba o toca una plantilla.</li>`;
    return;
  }

  list.innerHTML = habits
    .map((h) => {
      const log = logForToday(logs, h.id);
      const streak = streakFor(h, logs.filter((l) => l.habit_id === h.id));
      const met = goalMet(h, log);

      const control =
        h.kind === "checkbox"
          ? `<button class="check ${log?.is_completed ? "is-checked" : ""}"
                     data-toggle-habit="${h.id}" data-done="${!!log?.is_completed}"
                     aria-label="Marcar como hecho">✓</button>`
          : `<input class="numeric-input" type="number" step="0.1" min="0"
                    value="${log?.value ?? ""}" data-log-habit="${h.id}"
                    placeholder="${esc(h.unit ?? "")}" aria-label="Valor de hoy">`;

      const target =
        h.kind === "numeric" && h.target_value != null
          ? `${h.goal_direction === "atMost" ? "máx." : "mín."} ${h.target_value}${h.unit ? " " + esc(h.unit) : ""}`
          : "";

      return `
      <li class="row">
        <div class="row-icon">${met ? "✅" : "⚪️"}</div>
        <div class="row-main">
          <div class="row-title">${esc(h.name)}</div>
          <div class="row-sub">
            ${target ? `<span>${target}</span>` : ""}
            ${streak > 0 ? `<span class="streak">🔥 ${streak} días</span>` : ""}
          </div>
        </div>
        ${control}
        <button class="delete" data-del="${h.id}" title="Eliminar" aria-label="Eliminar">✕</button>
      </li>`;
    })
    .join("");

  list.querySelectorAll("[data-toggle-habit]").forEach((btn) => {
    btn.addEventListener("click", () =>
      upsertHabitLog(btn.dataset.toggleHabit, { is_completed: btn.dataset.done !== "true" })
    );
  });

  list.querySelectorAll("[data-log-habit]").forEach((input) => {
    input.addEventListener("change", () => {
      const value = input.value === "" ? null : Number(input.value);
      // Un número registrado cuenta como "hecho" ese día, se cumpla el
      // objetivo o no — igual que HabitRepository.logValue en iOS.
      upsertHabitLog(input.dataset.logHabit, { value, is_completed: value != null });
    });
  });

  wireDelete(list, "habits");
}

/** Crea o actualiza el registro de HOY para un hábito. */
async function upsertHabitLog(habitId, fields) {
  const existing = logForToday(await store.all("habit_logs"), habitId);
  const log = existing
    ? await store.update("habit_logs", existing.id, fields)
    : await store.insert("habit_logs", {
        habit_id: habitId,
        date: startOfToday().toISOString(),
        is_completed: false,
        ...fields,
      });

  await awardHabitXP(habitId);
  return log;
}

/** Experiencia por cumplir un hábito y, si con este se cierra el día
 *  entero, la bonificación de "todos los hábitos".
 *
 *  Se comprueba el objetivo de verdad (goalMet) y no el simple
 *  `is_completed`: en un hábito numérico —"bebe 2 litros"— apuntar medio
 *  litro deja el registro creado pero el objetivo sin cumplir, y premiar
 *  eso sería premiar el gesto y no el hábito. */
async function awardHabitXP(habitId) {
  const { habits, logs } = await fetchHabits();
  const habit = habits.find((h) => h.id === habitId);
  if (!habit || !goalMet(habit, logForToday(logs, habitId))) return;

  await awardXP("habitCompleted", prog.dedupeKey(`habit:${idKey(habitId)}`));

  if (habits.length && habits.every((h) => goalMet(h, logForToday(logs, h.id)))) {
    await awardXP("allHabitsCompleted", prog.dedupeKey("all-habits"));
  }
}

$("habit-form").addEventListener("submit", async (e) => {
  e.preventDefault();
  const numeric = $("habit-kind").value === "numeric";
  await store.insert("habits", {
    name: $("habit-name").value.trim(),
    symbol_name: "checkmark.circle.fill",
    kind: $("habit-kind").value,
    target_value: numeric ? Number($("habit-target").value) || null : null,
    goal_direction: numeric ? $("habit-direction").value : "atLeast",
    unit: numeric ? $("habit-unit").value.trim() || null : null,
    is_active: true,
    sort_order: 0,
    linked_to_workouts: false,
  });
  e.target.reset();
  syncHabitKindFields();
});

// ── Medicación ──────────────────────────────────────────────────────

/** Cruza los horarios de cada medicamento con los registros de hoy —
 *  misma construcción que MedicationRepository.todaysDoses() en iOS. */
async function todaysDoses() {
  const meds = (await store.all("medications"))
    .filter((m) => m.is_active)
    .sort((a, b) => a.name.localeCompare(b.name));

  const logs = (await store.all("medication_dose_logs")).filter((l) =>
    sameDay(l.date, startOfToday())
  );

  const doses = [];
  for (const med of meds) {
    for (const minute of med.reminder_minutes_since_midnight ?? []) {
      const log = logs.find((l) => l.medication_id === med.id && l.minute_of_day === minute);
      doses.push({
        med,
        minute,
        taken: !!log?.taken_at,
        skipped: !!log?.skipped,
        logId: log?.id ?? null,
      });
    }
  }
  return { meds, doses: doses.sort((a, b) => a.minute - b.minute) };
}

async function loadMedication() {
  const { meds, doses } = await todaysDoses();

  const list = $("dose-list");
  list.innerHTML = doses.length
    ? doses
        .map(
          (d, i) => `
      <li class="row">
        <button class="check ${d.taken ? "is-checked" : ""}"
                data-dose="${i}" aria-label="Marcar como tomada">✓</button>
        <div class="row-icon">💊</div>
        <div class="row-main">
          <div class="row-title ${d.taken ? "is-done" : ""}">${esc(d.med.name)}</div>
          <div class="row-sub">
            <span>${minutesToTime(d.minute)}</span>
            ${d.med.dosage ? `<span>${esc(d.med.dosage)}</span>` : ""}
            ${d.skipped ? `<span>omitida</span>` : ""}
          </div>
        </div>
      </li>`
        )
        .join("")
    : `<li class="empty">No tienes tomas programadas para hoy.</li>`;

  list.querySelectorAll("[data-dose]").forEach((btn) => {
    btn.addEventListener("click", () => {
      const d = doses[Number(btn.dataset.dose)];
      setDoseTaken(d, !d.taken);
    });
  });

  const medList = $("med-list");
  medList.innerHTML = meds.length
    ? meds
        .map(
          (m) => `
      <li class="row">
        <div class="row-icon">💊</div>
        <div class="row-main">
          <div class="row-title">${esc(m.name)}</div>
          <div class="row-sub">
            <span>${(m.reminder_minutes_since_midnight ?? []).map(minutesToTime).join(" · ") || "sin horarios"}</span>
            ${m.dosage ? `<span>${esc(m.dosage)}</span>` : ""}
          </div>
        </div>
        <button class="delete" data-del="${m.id}" title="Eliminar" aria-label="Eliminar">✕</button>
      </li>`
        )
        .join("")
    : `<li class="empty">Aún no has añadido ningún medicamento.</li>`;

  wireDelete(medList, "medications");
}

async function setDoseTaken(dose, taken) {
  const fields = { taken_at: taken ? nowISO() : null, skipped: false };
  const log = dose.logId
    ? await store.update("medication_dose_logs", dose.logId, fields)
    : await store.insert("medication_dose_logs", {
        medication_id: dose.med.id,
        date: startOfToday().toISOString(),
        minute_of_day: dose.minute,
        ...fields,
      });

  // La clave lleva medicamento + hora + día: cada toma concreta se
  // premia una vez, pero dos tomas del mismo medicamento el mismo día
  // cuentan por separado.
  if (taken) {
    await awardXP(
      "medicationTaken",
      prog.dedupeKey(`dose:${idKey(dose.med.id)}:${dose.minute}`)
    );
  }
  return log;
}

$("med-form").addEventListener("submit", async (e) => {
  e.preventDefault();

  // "08:00, 20:00" → [480, 1200] (minutos desde medianoche, como en iOS).
  const minutes = $("med-times")
    .value.split(",")
    .map((s) => s.trim())
    .filter(Boolean)
    .map((s) => {
      const [h, m] = s.split(":").map(Number);
      return Number.isFinite(h) && Number.isFinite(m) ? h * 60 + m : null;
    })
    .filter((m) => m !== null && m >= 0 && m < 1440)
    .sort((a, b) => a - b);

  if (!minutes.length) {
    const b = $("sync-banner");
    b.className = "banner";
    b.textContent = "Escribe al menos una hora válida, por ejemplo 08:00 o 08:00, 20:00";
    b.hidden = false;
    return;
  }

  await store.insert("medications", {
    name: $("med-name").value.trim(),
    dosage: $("med-dosage").value.trim() || null,
    reminder_minutes_since_midnight: minutes,
    is_active: true,
  });
  e.target.reset();
});

// ── Ajustes ─────────────────────────────────────────────────────────

async function loadSettings() {
  const goal = await nutritionGoal();
  $("goal-calories").value = goal?.daily_calorie_goal ?? 2000;
  $("goal-protein").value = goal?.protein_goal_grams ?? 120;
  $("goal-carbs").value = goal?.carbs_goal_grams ?? 225;
  $("goal-fat").value = goal?.fat_goal_grams ?? 65;

  const budget = await budgetSettings();
  $("budget-monthly").value = budget?.monthly_budget ?? 1000;
  $("budget-savings").value = budget?.total_savings ?? 0;
  $("budget-currency").value = budget?.currency_code ?? "EUR";

  const { data } = await supabase.auth.getUser();
  $("settings-email").textContent = data?.user?.email ?? "";
}

$("goal-form").addEventListener("submit", async (e) => {
  e.preventDefault();
  await store.putSingleton("nutrition_goals", {
    daily_calorie_goal: Number($("goal-calories").value) || 2000,
    protein_goal_grams: Number($("goal-protein").value) || 0,
    carbs_goal_grams: Number($("goal-carbs").value) || 0,
    fat_goal_grams: Number($("goal-fat").value) || 0,
  });
  showSaved($("goal-form"));
});

$("budget-form").addEventListener("submit", async (e) => {
  e.preventDefault();
  currencyCode = $("budget-currency").value;
  await store.putSingleton("budget_settings", {
    monthly_budget: Number($("budget-monthly").value) || 0,
    total_savings: Number($("budget-savings").value) || 0,
    currency_code: currencyCode,
  });
  showSaved($("budget-form"));
});

// ── Fondo ───────────────────────────────────────────────────────────
//
// Los mismos seis fondos que en iOS (BackgroundTheme.swift). Aquí solo
// están los colores de la MINIATURA: los de la página de verdad viven
// en styles.css, en los bloques [data-bg="…"]. Están duplicados a
// propósito y no leídos del CSS — sacarlos de getComputedStyle
// obligaría a pintar seis veces la página entera solo para dibujar
// seis cuadraditos.

const BACKGROUNDS = [
  { id: "system", name: "Automático", screen: "linear-gradient(90deg, #f2f2f7 0 50%, #0b0d10 50%)" },
  { id: "light", name: "Claro", screen: "#f2f2f7", card: "#ffffff" },
  { id: "cream", name: "Crema", screen: "#fbfaf7", card: "#ffffff" },
  { id: "vanilla", name: "Vainilla", screen: "#fff8e9", card: "#fffdf6" },
  { id: "graphite", name: "Grafito", screen: "#17181c", card: "#24262b" },
  { id: "night", name: "Noche", screen: "#0b0d10", card: "#16171c" },
];

const BG_KEY = "habitium.bg";

/** El fondo elegido, o "system" si no hay nada guardado o no se puede leer. */
function currentBackground() {
  try {
    const saved = localStorage.getItem(BG_KEY);
    if (BACKGROUNDS.some((b) => b.id === saved)) return saved;
  } catch (e) {
    // Almacenamiento bloqueado (modo privado en algunos navegadores).
  }
  return "system";
}

function applyBackground(id) {
  document.documentElement.setAttribute("data-bg", id);
  try {
    localStorage.setItem(BG_KEY, id);
  } catch (e) {
    // Sin guardar: el fondo aguanta esta sesión y punto. Mejor eso que
    // reventar la pantalla de Ajustes por no poder escribir.
  }
  updateThemeColor(id);
  renderBackgroundPicker();
}

/** Pinta la barra del navegador del color del fondo, no de verde.
 *  Con la app instalada en Android es la diferencia entre que se vea
 *  entera de un color o con una franja verde que no pega con nada. */
function updateThemeColor(id) {
  const meta = document.querySelector('meta[name="theme-color"]');
  if (!meta) return;
  const prefersDark = window.matchMedia?.("(prefers-color-scheme: dark)").matches;
  const resolved = id === "system" ? (prefersDark ? "night" : "light") : id;
  meta.setAttribute("content", BACKGROUNDS.find((b) => b.id === resolved)?.screen ?? "#f2f2f7");
}

function renderBackgroundPicker() {
  const host = $("bg-picker");
  if (!host) return;
  const active = currentBackground();

  host.innerHTML = BACKGROUNDS.map(
    (b) => `
    <button class="bg-opt" type="button" data-bg-id="${b.id}"
            aria-pressed="${b.id === active}" title="${b.name}">
      <span class="bg-prev" style="background:${b.screen}">
        ${b.card ? `<span class="bg-prev-card" style="background:${b.card}"></span>` : ""}
      </span>
      <span>${b.name}</span>
    </button>`
  ).join("");

  host.querySelectorAll("[data-bg-id]").forEach((btn) => {
    btn.addEventListener("click", () => applyBackground(btn.dataset.bgId));
  });
}

// Con "Automático", seguir al sistema también cuando cambia con la app
// abierta — al anochecer, sin tocar nada.
window.matchMedia?.("(prefers-color-scheme: dark)").addEventListener?.("change", () => {
  if (currentBackground() === "system") updateThemeColor("system");
});

/** Confirmación breve en el propio botón, sin sacar un diálogo. */
function showSaved(form) {
  const btn = form.querySelector("button[type=submit]");
  const original = btn.textContent;
  btn.textContent = "Guardado ✓";
  btn.disabled = true;
  setTimeout(() => {
    btn.textContent = original;
    btn.disabled = false;
  }, 1400);
}

// ── Progresión ──────────────────────────────────────────────────────
//
// Nivel, racha, retos del día y pase. Todo esto ya existía en el iPhone;
// aquí está el mismo sistema, con los mismos números y las mismas
// claves, para que sea UNA cuenta y no dos.

/** Los identificadores dentro de una clave anti-repetición van en
 *  MAYÚSCULAS.
 *
 *  Detalle pequeño y con consecuencias grandes: en Swift, interpolar un
 *  UUID da "A1B2-…" en mayúsculas, mientras que `crypto.randomUUID()` y
 *  Postgres los dan en minúsculas. Si la web escribiera la clave en
 *  minúsculas, "habit:a1b2…:2026-09-04" y "habit:A1B2…:2026-09-04"
 *  serían dos claves distintas para el MISMO hábito del MISMO día: el
 *  iPhone y la web premiarían cada uno por su cuenta y al sincronizar
 *  saldría XP duplicado, sin ningún error que lo delatara. */
const idKey = (id) => String(id ?? "").toUpperCase();

/** Concede experiencia y lo celebra en pantalla. Todo lo que da puntos
 *  pasa por aquí. */
async function awardXP(source, key, date = new Date()) {
  const award = await player.award(source, key, date);
  if (award) checkChallengeBonus();
  return award;
}

/** Comprueba si los tres retos están hechos y cobra la bonificación.
 *  Se llama después de cada concesión porque cualquier acción puede
 *  haber sido la que cerró el tercer reto. */
async function checkChallengeBonus() {
  try {
    await player.awardBonusIfComplete(await challengeCounts());
  } catch (error) {
    console.warn("retos:", error);
  }
}

/** El progreso de cada tipo de reto, medido contra los datos reales de
 *  hoy. No se guarda en ningún sitio: un contador aparte sería una
 *  segunda fuente de verdad que se rompería en cuanto alguien borrase
 *  una comida. */
async function challengeCounts() {
  const today = startOfToday();
  const isToday = (value) => value && new Date(value) >= today;

  const { habits, logs } = await fetchHabits();
  const tasks = await store.all("planner_tasks");
  const completedToday = tasks.filter((t) => t.is_completed && isToday(t.updated_at));
  const { doses } = await todaysDoses();

  return {
    habits: habits.filter((h) => goalMet(h, logForToday(logs, h.id))).length,
    tasks: completedToday.length,
    focus: completedToday.filter((t) => t.is_focus).length,
    meals: (await store.all("food_entries")).filter((e) => isToday(e.date)).length,
    weight: (await store.all("weight_entries")).filter((e) => isToday(e.date)).length,
    workout: (await store.all("workout_sets")).some((s) => isToday(s.date)) ? 1 : 0,
    // Sin medicación configurada el reto no aplica; se da por cumplido
    // en vez de dejarlo imposible para siempre.
    medication: !doses.length ? 1 : doses.every((d) => d.taken || d.skipped) ? 1 : 0,
  };
}

// ── Avisos en pantalla ──────────────────────────────────────────────

let toastTimer = null;

player.onAward((award) => {
  showXPToast(award);
  if (award.didLevelUp) showLevelUp(award);
  render();
});

function showXPToast(award) {
  const source = prog.XP_SOURCES[award.source];
  const toast = $("xp-toast");
  toast.innerHTML = `<span aria-hidden="true">${source?.icon ?? "⭐"}</span>
    +${award.amount} XP <small>${esc(source?.name ?? "")}</small>`;
  toast.hidden = false;
  toast.classList.remove("is-leaving");

  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => {
    toast.classList.add("is-leaving");
    setTimeout(() => {
      toast.hidden = true;
      toast.classList.remove("is-leaving");
    }, 280);
  }, 2200);
}

function showLevelUp(award) {
  $("levelup-level").textContent = award.newLevel;
  $("levelup-name").textContent = prog.titleForLevel(award.newLevel);

  const rewards = award.unlockedTiers
    .map((id) => prog.SEASON_TIERS.find((t) => t.id === id))
    .filter(Boolean);
  $("levelup-rewards").innerHTML = rewards
    .map((t) => `<li>${t.icon} ${esc(prog.tierRewardName(t))}</li>`)
    .join("");

  spawnConfetti();
  $("levelup").hidden = false;
}

/** Confeti: 40 trozos con posición, color y ritmo distintos. Se generan
 *  aquí y no en CSS porque hacen falta valores aleatorios por trozo, y
 *  se borran al cerrar para no dejar 40 animaciones corriendo. */
function spawnConfetti() {
  const host = $("levelup-confetti");
  const colores = ["#7c3aed", "#15a34a", "#f59e0b", "#2563eb", "#db2777"];
  host.innerHTML = Array.from({ length: 40 }, () => {
    const left = Math.random() * 100;
    const delay = Math.random() * 0.5;
    const dur = 1.6 + Math.random() * 1.4;
    const color = colores[Math.floor(Math.random() * colores.length)];
    return `<i class="confetti-bit" style="left:${left}%;background:${color};
      animation-duration:${dur}s;animation-delay:${delay}s"></i>`;
  }).join("");
}

$("levelup-close").addEventListener("click", closeLevelUp);
$("levelup").addEventListener("click", (e) => {
  if (e.target === $("levelup")) closeLevelUp();
});

function closeLevelUp() {
  $("levelup").hidden = true;
  $("levelup-confetti").innerHTML = "";
}

// ── Acento ──────────────────────────────────────────────────────────

const ACCENT_KEY = "habitium.accent";

function currentAccent() {
  try {
    const saved = localStorage.getItem(ACCENT_KEY);
    if (saved && prog.ACCENTS[saved]) return saved;
  } catch (e) {
    // Almacenamiento bloqueado.
  }
  return "classic";
}

function applyAccent(id) {
  // El clásico no pone atributo: así el CSS de :root vale tal cual.
  if (id === "classic") document.documentElement.removeAttribute("data-accent");
  else document.documentElement.setAttribute("data-accent", id);
  try {
    localStorage.setItem(ACCENT_KEY, id);
  } catch (e) {
    // Sin guardar: aguanta esta sesión y punto.
  }
}

async function renderAccentPicker(profile) {
  const disponibles = new Set(prog.availableAccents(profile.unlocked_reward_ids));
  const activo = currentAccent();
  const host = $("accent-picker");

  host.innerHTML = Object.entries(prog.ACCENTS)
    .map(([id, a]) => {
      const libre = disponibles.has(id);
      return `<button class="accent-opt" type="button" data-accent-id="${id}"
                      aria-pressed="${id === activo}" ${libre ? "" : "disabled"}
                      title="${libre ? a.name : `${a.name} — bloqueado`}">
                <span class="accent-dot" style="background:${a.color}">${libre ? (id === activo ? "✓" : "") : "🔒"}</span>
                <span>${a.name}</span>
              </button>`;
    })
    .join("");

  host.querySelectorAll("[data-accent-id]").forEach((btn) => {
    btn.addEventListener("click", () => {
      applyAccent(btn.dataset.accentId);
      renderAccentPicker(profile);
    });
  });
}

// ── Pantalla de Progreso ────────────────────────────────────────────

async function loadProgress() {
  const profile = await player.reconcile();
  const nivel = prog.levelForTotalXP(profile.total_xp);

  $("prog-level").textContent = nivel;
  $("prog-title").textContent = prog.highestTitle(profile.unlocked_reward_ids) ?? prog.titleForLevel(nivel);
  $("prog-detail").textContent = `${prog.xpRemainingToNextLevel(profile.total_xp)} XP para el nivel ${nivel + 1}`;
  $("prog-streak").textContent = profile.login_streak;
  $("prog-record").textContent = profile.longest_login_streak;
  $("prog-total").textContent = profile.total_xp;

  const ring = $("level-ring");
  const CIRC = 2 * Math.PI * 52;
  ring.style.strokeDasharray = String(CIRC);
  ring.style.strokeDashoffset = String(CIRC * (1 - prog.progressWithinLevel(profile.total_xp)));

  // Semana
  const semana = await player.dailyXP(7);
  // El máximo nunca baja de 20 para que un día de 5 XP no salga como
  // una barra a tope: la semana se lee comparando días, y con un solo
  // dato pequeño la escala engañaría.
  const maximo = Math.max(20, ...semana.map((d) => d.xp));
  // Altura en PÍXELES y no en porcentaje: el hueco de la barra son los
  // 116px de .xp-week menos las dos etiquetas y sus separaciones, y un
  // porcentaje dentro de un flex no tiene contra qué resolverse.
  const ALTO_MAX = 78;

  $("week-total").textContent = `${semana.reduce((s, d) => s + d.xp, 0)} XP`;
  $("xp-week").innerHTML = semana
    .map((d, i) => {
      const alto = Math.max(3, Math.round((d.xp / maximo) * ALTO_MAX));
      const hoy = i === semana.length - 1;
      const clases = ["xp-day", d.xp === 0 ? "is-empty" : "", hoy ? "is-today" : ""].join(" ");
      return `<div class="${clases}">
                <span class="xp-day-value">${d.xp || ""}</span>
                <div class="xp-bar" style="height:${alto}px"></div>
                <span class="xp-day-label">${d.date.toLocaleDateString("es-ES", { weekday: "narrow" })}</span>
              </div>`;
    })
    .join("");

  // Pase
  $("season-name").textContent = new Date().toLocaleDateString("es-ES", { month: "long" });
  $("season-xp").textContent = `${profile.season_xp} XP`;
  const siguiente = prog.nextTier(profile.season_xp);
  const desbloqueados = new Set(profile.unlocked_reward_ids);

  $("tier-list").innerHTML = prog.SEASON_TIERS.map((t) => {
    const hecho = desbloqueados.has(t.id) || profile.season_xp >= t.xpRequired;
    const esSiguiente = siguiente?.id === t.id;
    const clases = ["tier", hecho ? "is-unlocked" : "", esSiguiente ? "is-next" : ""].join(" ");
    const estado = hecho
      ? "✓"
      : esSiguiente
        ? `faltan ${t.xpRequired - profile.season_xp}`
        : "🔒";
    return `<li class="${clases}">
              <span class="tier-icon" aria-hidden="true">${t.icon}</span>
              <span class="tier-body">
                <span class="tier-name">${esc(prog.tierRewardName(t))}</span>
                <span class="tier-req">Nivel ${t.tier} del pase · ${t.xpRequired} XP</span>
              </span>
              <span class="tier-state">${estado}</span>
            </li>`;
  }).join("");

  await renderAccentPicker(profile);

  // Historial
  const eventos = await player.recentEvents(12);
  $("xp-log").innerHTML = eventos.length
    ? eventos
        .map((e) => {
          const src = prog.XP_SOURCES[e.source];
          return `<li class="row">
                    <span aria-hidden="true">${src?.icon ?? "⭐"}</span>
                    <div class="row-main">
                      <div class="row-title">${esc(src?.name ?? e.source)}</div>
                      <div class="row-sub">${dayOf(e.date)}</div>
                    </div>
                    <span class="pill">+${e.amount}</span>
                  </li>`;
        })
        .join("")
    : `<li class="empty">Todavía no has ganado puntos. Cumple un hábito o completa una tarea.</li>`;
}

// ── Inicio ──────────────────────────────────────────────────────────

async function loadHome() {
  await loadHomeProgression();

  const entries = await todaysFood();
  const goal = await nutritionGoal();
  const budget = await budgetSettings();
  const txs = await monthTransactions();

  // Anillo de calorías
  const consumed = entries.reduce((s, e) => s + (e.calories ?? 0), 0);
  const goalCal = goal?.daily_calorie_goal ?? 2000;
  $("home-calories").textContent = Math.round(goalCal - consumed);
  $("home-calories-detail").textContent =
    `${Math.round(consumed)} de ${Math.round(goalCal)} kcal · ${entries.length} comidas`;

  const ratio = goalCal > 0 ? Math.min(1, consumed / goalCal) : 0;
  const ring = $("ring-progress");
  const CIRCUMFERENCE = 2 * Math.PI * 52;
  ring.style.strokeDashoffset = String(CIRCUMFERENCE * (1 - ratio));
  ring.classList.toggle("is-over", consumed > goalCal);

  // Macros
  const sum = (key) => entries.reduce((s, e) => s + (e[key] ?? 0), 0);
  const macros = [
    { name: "Proteína", got: sum("protein_grams"), target: goal?.protein_goal_grams ?? 0 },
    { name: "Carbos", got: sum("carbs_grams"), target: goal?.carbs_goal_grams ?? 0 },
    { name: "Grasas", got: sum("fat_grams"), target: goal?.fat_goal_grams ?? 0 },
  ];
  $("home-macros").innerHTML = macros
    .map(
      (m) => `
      <div class="macro">
        <div class="macro-name">${m.name}</div>
        <div class="track"><div class="track-fill" style="width:${m.target ? Math.min(100, (m.got / m.target) * 100) : 0}%"></div></div>
        <div class="macro-val">${Math.round(m.got)}${m.target ? ` / ${Math.round(m.target)}` : ""} g</div>
      </div>`
    )
    .join("");

  // Hábitos
  const { habits, logs } = await fetchHabits();
  const met = habits.filter((h) => goalMet(h, logForToday(logs, h.id))).length;
  $("home-habits").textContent = habits.length ? `${met}/${habits.length}` : "—";
  $("home-habits-detail").textContent = habits.length
    ? met === habits.length
      ? "¡Todos cumplidos hoy!"
      : "Cumplidos hoy"
    : "Aún no tienes hábitos.";
  $("home-habits-bar").style.width = habits.length ? `${(met / habits.length) * 100}%` : "0%";

  // Presupuesto
  const spent = txs.filter((t) => t.type === "expense").reduce((s, t) => s + t.amount, 0);
  const monthly = budget?.monthly_budget ?? 0;
  $("home-available").textContent = money(Math.max(0, monthly - spent));
  $("home-available-detail").textContent = `${money(spent)} gastado de ${money(monthly)}`;
  const budgetBar = $("home-budget-bar");
  budgetBar.style.width = monthly ? `${Math.min(100, (spent / monthly) * 100)}%` : "0%";
  budgetBar.classList.toggle("is-over", spent > monthly);

  // Próxima tarea
  const today = startOfToday();
  const next = (await store.all("planner_tasks"))
    .filter((t) => !t.is_completed && t.due_date && new Date(t.due_date) >= today)
    .sort((a, b) => new Date(a.due_date) - new Date(b.due_date))[0];
  $("home-next").textContent = next?.title ?? "Nada pendiente";
  $("home-next-detail").textContent = next?.due_date ? dayOf(next.due_date) : "";

  // Próxima toma
  const { doses } = await todaysDoses();
  const pending = doses.find((d) => !d.taken && !d.skipped);
  $("home-dose").textContent = pending ? pending.med.name : "Sin tomas pendientes";
  $("home-dose-detail").textContent = pending
    ? `${minutesToTime(pending.minute)}${pending.med.dosage ? " · " + pending.med.dosage : ""}`
    : "";
}

/** La tarjeta de nivel y los retos, arriba de Inicio. */
async function loadHomeProgression() {
  // Antes de pintar, recalcular el total desde los eventos: así se
  // recoge el XP ganado en el iPhone en cuanto ha sincronizado, sin
  // depender de qué perfil ganó la última escritura. Solo escribe si
  // algo cambió, así que la segunda pasada no hace nada.
  const profile = await player.reconcile();
  const nivel = prog.levelForTotalXP(profile.total_xp);

  $("home-level").textContent = nivel;
  $("home-level-title").textContent =
    prog.highestTitle(profile.unlocked_reward_ids) ?? prog.titleForLevel(nivel);
  $("home-level-bar").style.width = `${prog.progressWithinLevel(profile.total_xp) * 100}%`;
  $("home-level-detail").textContent = `${prog.xpRemainingToNextLevel(profile.total_xp)} XP para el nivel ${nivel + 1}`;

  // La racha solo se enseña si existe: un "🔥 0" es un recordatorio de
  // que no tienes racha, que es justo lo contrario de lo que hace un
  // contador de rachas.
  const rachaVisible = (profile.login_streak ?? 0) > 0;
  $("home-streak-pill").hidden = !rachaVisible;
  $("home-streak").textContent = profile.login_streak;

  const retos = player.todaysChallenges(await challengeCounts());
  const hechos = retos.filter(prog.challengeIsComplete).length;

  $("home-challenge-count").textContent = `${hechos}/${retos.length}`;
  $("home-challenges").innerHTML = retos
    .map((c) => {
      const hecho = prog.challengeIsComplete(c);
      const contador = c.goal > 1 ? `${Math.min(c.progress, c.goal)}/${c.goal}` : "";
      return `<li class="challenge ${hecho ? "is-done" : ""}">
                <span class="challenge-icon" aria-hidden="true">${hecho ? "✅" : prog.challengeIcon(c.kind)}</span>
                <span class="challenge-name">${esc(prog.challengeTitle(c.kind, c.goal))}</span>
                <span class="challenge-count">${hecho ? "" : contador}</span>
              </li>`;
    })
    .join("");

  $("home-challenge-foot").textContent =
    hechos === retos.length
      ? `¡Los tres hechos! +${prog.CHALLENGE_BONUS_XP} XP de bonificación.`
      : `Completa los tres y te llevas +${prog.CHALLENGE_BONUS_XP} XP extra.`;
}

// ── Peso ────────────────────────────────────────────────────────────

$("weight-form").addEventListener("submit", async (e) => {
  e.preventDefault();
  const kg = Number($("weight-kg").value);
  if (!kg || kg <= 0) return;

  const entry = await store.insert("weight_entries", {
    date: nowISO(),
    weight_kg: kg,
  });
  $("weight-kg").value = "";
  // Una vez al día: apuntar el peso cinco veces no da cinco premios.
  await awardXP("weightLogged", prog.dedupeKey("weight", new Date(entry.date)));
});

// ── Arranque y sesión ───────────────────────────────────────────────

function showAuth() {
  $("boot").hidden = true;
  $("app").hidden = true;
  $("auth-screen").hidden = false;
}

async function showApp() {
  $("boot").hidden = true;
  $("auth-screen").hidden = true;
  $("app").hidden = false;

  $("topbar-date").textContent = new Date().toLocaleDateString("es-ES", {
    weekday: "long",
    day: "numeric",
    month: "long",
  });

  const { data } = await supabase.auth.getUser();
  const email = data?.user?.email ?? "";
  $("side-email").textContent = email;
  $("side-avatar").textContent = email.charAt(0) || "·";

  go("home");        // pinta ya, desde lo que haya en local

  // Cuenta el día y actualiza la racha. Es idempotente: abrir la web
  // diez veces hoy solo cuenta una. Va después de pintar para que no
  // retrase la primera pantalla.
  try {
    await player.registerDailyLogin();
  } catch (error) {
    console.warn("racha:", error);
  }

  store.sync();      // y actualiza por detrás
}

buildNav();
syncHabitKindFields();
setAuthMode("signin");
renderBackgroundPicker();
updateThemeColor(currentBackground());
applyAccent(currentAccent());

supabase.auth.onAuthStateChange((_event, session) => {
  if (session) showApp();
  else {
    showAuth();
    setAuthMessage("");
  }
});

// Sesión inicial: onAuthStateChange también dispara al arrancar, pero
// comprobarlo aquí evita el parpadeo de la pantalla de carga.
const {
  data: { session },
} = await supabase.auth.getSession();
if (session) showApp();
else showAuth();
