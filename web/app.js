// Habitium web — cliente único contra las mismas tablas de Supabase que
// usa la app de iPhone (ver supabase/schema.sql y
// Habitium/Core/Sync/CloudSyncService.swift).
//
// Diferencia importante con iOS: aquí NO hay copia local. La app de
// iPhone guarda en SwiftData y sincroniza; la web lee y escribe
// directamente en Postgres. Eso la hace mucho más simple, pero también
// significa que sin conexión no funciona — asumido a propósito, porque
// el caso de uso que la motivó (un iPad del cole, un Android prestado)
// siempre tiene navegador y red.
//
// Sobre user_id: no se manda nunca desde aquí. Las columnas tienen
// `default auth.uid()` en el esquema, así que un INSERT normal ya queda
// atribuido al usuario logueado, y el Row Level Security filtra los
// SELECT automáticamente. Por eso ninguna consulta de este archivo lleva
// un `.eq("user_id", ...)`: sería redundante y daría una falsa sensación
// de que es *eso* lo que protege los datos.

import { createClient } from "https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/+esm";

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

/** El estado de UserSettings.currencyCode manda; hasta que carga, EUR. */
let currencyCode = "EUR";
const money = (value) =>
  new Intl.NumberFormat("es-ES", { style: "currency", currency: currencyCode }).format(value ?? 0);

const timeOf = (iso) =>
  new Date(iso).toLocaleTimeString("es-ES", { hour: "2-digit", minute: "2-digit" });

const dayOf = (iso) =>
  new Date(iso).toLocaleDateString("es-ES", { day: "numeric", month: "short" });

/** Escapa texto del usuario antes de meterlo en innerHTML. */
const esc = (str) =>
  String(str ?? "").replace(/[&<>"']/g, (c) =>
    ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c])
  );

function showError(message) {
  const banner = $("sync-banner");
  banner.textContent = message;
  banner.hidden = false;
}

function clearError() {
  $("sync-banner").hidden = true;
}

/** Envuelve una consulta: devuelve los datos, o enseña el error y null. */
async function run(promise, what) {
  const { data, error } = await promise;
  if (error) {
    console.error(what, error);
    showError(`No se pudo ${what}: ${error.message}`);
    return null;
  }
  clearError();
  return data;
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

$("auth-form").addEventListener("submit", async (event) => {
  event.preventDefault();
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

  if (error) {
    setAuthMessage(error.message);
    return;
  }

  // Con "Confirm email" activado (el ajuste por defecto de Supabase), el
  // registro no devuelve sesión hasta que se abre el enlace del correo.
  if (authMode === "signup" && !data.session) {
    setAuthMessage(`Te hemos enviado un enlace a ${email}. Ábrelo y vuelve aquí.`, true);
  }
});

$("forgot-password").addEventListener("click", async () => {
  const email = $("auth-email").value.trim();
  if (!email) {
    setAuthMessage("Escribe tu correo primero.");
    return;
  }
  const { error } = await supabase.auth.resetPasswordForEmail(email, {
    redirectTo: window.location.href,
  });
  setAuthMessage(
    error ? error.message : "Te hemos enviado un enlace para restablecer tu contraseña.",
    !error
  );
});

$("sign-out").addEventListener("click", async () => {
  await supabase.auth.signOut();
});

// ── Navegación por pestañas ─────────────────────────────────────────

const VIEWS = ["home", "nutrition", "planner", "finance", "habits"];

document.querySelectorAll(".tab").forEach((tab) => {
  tab.addEventListener("click", () => {
    const target = tab.dataset.view;
    VIEWS.forEach((v) => ($(`view-${v}`).hidden = v !== target));
    document.querySelectorAll(".tab").forEach((t) => t.classList.toggle("is-active", t === tab));
    refreshView(target);
  });
});

function refreshView(view) {
  if (view === "home") return loadHome();
  if (view === "nutrition") return loadNutrition();
  if (view === "planner") return loadPlanner();
  if (view === "finance") return loadFinance();
  if (view === "habits") return loadHabits();
}

// ── Nutrición ───────────────────────────────────────────────────────

const MEAL_NAMES = {
  breakfast: "Desayuno",
  lunch: "Almuerzo",
  dinner: "Cena",
  snack: "Snack",
};

async function todaysFood() {
  return await run(
    supabase
      .from("food_entries")
      .select("*")
      .gte("date", startOfToday().toISOString())
      .lt("date", startOfTomorrow().toISOString())
      .order("date", { ascending: true }),
    "cargar las comidas"
  );
}

async function nutritionGoal() {
  const rows = await run(
    supabase.from("nutrition_goals").select("*").limit(1),
    "cargar tu objetivo de calorías"
  );
  return rows?.[0] ?? null;
}

async function loadNutrition() {
  const entries = (await todaysFood()) ?? [];
  const list = $("food-list");

  if (entries.length === 0) {
    list.innerHTML = `<li class="empty">Aún no has registrado nada hoy.</li>`;
    return;
  }

  list.innerHTML = entries
    .map(
      (e) => `
      <li class="row" data-id="${e.id}">
        <div class="row-main">
          <div class="row-title">${esc(e.name)}</div>
          <div class="row-sub">${MEAL_NAMES[e.meal_type] ?? ""} · ${timeOf(e.date)}
            · P ${Math.round(e.protein_grams)}g · C ${Math.round(e.carbs_grams)}g · G ${Math.round(e.fat_grams)}g</div>
        </div>
        <div class="row-value">${Math.round(e.calories)} kcal</div>
        <button class="delete" data-delete-food="${e.id}" title="Eliminar" aria-label="Eliminar">✕</button>
      </li>`
    )
    .join("");

  list.querySelectorAll("[data-delete-food]").forEach((btn) => {
    btn.addEventListener("click", async () => {
      await run(
        supabase.from("food_entries").delete().eq("id", btn.dataset.deleteFood),
        "eliminar la comida"
      );
      loadNutrition();
    });
  });
}

$("food-form").addEventListener("submit", async (event) => {
  event.preventDefault();
  const payload = {
    name: $("food-name").value.trim(),
    date: nowISO(),
    meal_type: $("food-meal").value,
    source: "manual",
    calories: Number($("food-calories").value) || 0,
    protein_grams: Number($("food-protein").value) || 0,
    carbs_grams: Number($("food-carbs").value) || 0,
    fat_grams: Number($("food-fat").value) || 0,
    updated_at: nowISO(),
  };
  await run(supabase.from("food_entries").insert(payload), "guardar la comida");
  event.target.reset();
  ["food-protein", "food-carbs", "food-fat"].forEach((id) => ($(id).value = ""));
  loadNutrition();
});

// ── Planner ─────────────────────────────────────────────────────────

async function loadPlanner() {
  const tasks =
    (await run(
      supabase.from("planner_tasks").select("*").order("due_date", { ascending: true, nullsFirst: false }),
      "cargar las tareas"
    )) ?? [];

  const pending = tasks.filter((t) => !t.is_completed);
  const done = tasks.filter((t) => t.is_completed);

  renderTasks($("task-list"), pending, "No tienes tareas pendientes.");
  renderTasks($("task-done-list"), done, "Nada completado todavía.");
}

function renderTasks(list, tasks, emptyText) {
  if (tasks.length === 0) {
    list.innerHTML = `<li class="empty">${emptyText}</li>`;
    return;
  }

  list.innerHTML = tasks
    .map(
      (t) => `
      <li class="row">
        <button class="check ${t.is_completed ? "is-checked" : ""}"
                data-toggle-task="${t.id}" data-completed="${t.is_completed}"
                aria-label="Marcar como completada">✓</button>
        <div class="row-main">
          <div class="row-title ${t.is_completed ? "is-done" : ""}">${esc(t.title)}</div>
          ${t.due_date ? `<div class="row-sub">${dayOf(t.due_date)}</div>` : ""}
        </div>
        <button class="delete" data-delete-task="${t.id}" title="Eliminar" aria-label="Eliminar">✕</button>
      </li>`
    )
    .join("");

  list.querySelectorAll("[data-toggle-task]").forEach((btn) => {
    btn.addEventListener("click", async () => {
      await run(
        supabase
          .from("planner_tasks")
          .update({ is_completed: btn.dataset.completed !== "true", updated_at: nowISO() })
          .eq("id", btn.dataset.toggleTask),
        "actualizar la tarea"
      );
      loadPlanner();
    });
  });

  list.querySelectorAll("[data-delete-task]").forEach((btn) => {
    btn.addEventListener("click", async () => {
      await run(
        supabase.from("planner_tasks").delete().eq("id", btn.dataset.deleteTask),
        "eliminar la tarea"
      );
      loadPlanner();
    });
  });
}

$("task-form").addEventListener("submit", async (event) => {
  event.preventDefault();
  const due = $("task-due").value;
  await run(
    supabase.from("planner_tasks").insert({
      title: $("task-title").value.trim(),
      // El input date da "YYYY-MM-DD" (sin hora); mediodía evita que un
      // desfase de zona horaria lo mueva al día anterior.
      due_date: due ? new Date(`${due}T12:00:00`).toISOString() : null,
      is_completed: false,
      priority: "medium",
      is_focus: false,
      updated_at: nowISO(),
    }),
    "guardar la tarea"
  );
  event.target.reset();
  loadPlanner();
});

// ── Finanzas ────────────────────────────────────────────────────────

const CATEGORY_NAMES = {
  food: "Comida",
  leisure: "Ocio",
  savings: "Ahorro",
  services: "Servicios",
  transport: "Transporte",
  health: "Salud",
  salary: "Salario",
  other: "Otro",
};

async function monthTransactions() {
  return await run(
    supabase
      .from("transactions")
      .select("*")
      .gte("date", startOfMonth().toISOString())
      .lt("date", startOfNextMonth().toISOString())
      .order("date", { ascending: false }),
    "cargar los movimientos"
  );
}

async function budgetSettings() {
  const rows = await run(
    supabase.from("budget_settings").select("*").limit(1),
    "cargar tu presupuesto"
  );
  const budget = rows?.[0] ?? null;
  if (budget?.currency_code) currencyCode = budget.currency_code;
  return budget;
}

async function loadFinance() {
  await budgetSettings(); // fija la moneda antes de formatear nada
  const transactions = (await monthTransactions()) ?? [];
  const list = $("tx-list");

  if (transactions.length === 0) {
    list.innerHTML = `<li class="empty">Sin movimientos este mes.</li>`;
    return;
  }

  list.innerHTML = transactions
    .map((t) => {
      const income = t.type === "income";
      return `
      <li class="row">
        <div class="row-main">
          <div class="row-title">${esc(t.note || CATEGORY_NAMES[t.category] || "Movimiento")}</div>
          <div class="row-sub">${CATEGORY_NAMES[t.category] ?? ""} · ${dayOf(t.date)}</div>
        </div>
        <div class="row-value ${income ? "is-income" : "is-expense"}">
          ${income ? "+" : "−"}${money(t.amount)}
        </div>
        <button class="delete" data-delete-tx="${t.id}" title="Eliminar" aria-label="Eliminar">✕</button>
      </li>`;
    })
    .join("");

  list.querySelectorAll("[data-delete-tx]").forEach((btn) => {
    btn.addEventListener("click", async () => {
      await run(
        supabase.from("transactions").delete().eq("id", btn.dataset.deleteTx),
        "eliminar el movimiento"
      );
      loadFinance();
    });
  });
}

$("tx-form").addEventListener("submit", async (event) => {
  event.preventDefault();
  await run(
    supabase.from("transactions").insert({
      amount: Number($("tx-amount").value) || 0,
      type: $("tx-type").value,
      category: $("tx-category").value,
      note: $("tx-note").value.trim() || null,
      date: nowISO(),
      updated_at: nowISO(),
    }),
    "guardar el movimiento"
  );
  event.target.reset();
  loadFinance();
});

// ── Hábitos ─────────────────────────────────────────────────────────

$("habit-kind").addEventListener("change", () => {
  const numeric = $("habit-kind").value === "numeric";
  $("habit-target").hidden = !numeric;
  $("habit-direction").hidden = !numeric;
  $("habit-unit").hidden = !numeric;
});

/** ¿Cumple este registro el objetivo del hábito? Misma regla que
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
    const day = new Date(log.date);
    day.setHours(0, 0, 0, 0);
    byDay.set(day.getTime(), log);
  }

  let cursor = startOfToday();
  // Si hoy aún no está cumplido, la racha se mide desde ayer — no se
  // rompe solo porque el día no haya terminado.
  if (!goalMet(habit, byDay.get(cursor.getTime()))) {
    cursor.setDate(cursor.getDate() - 1);
  }

  let streak = 0;
  while (goalMet(habit, byDay.get(cursor.getTime()))) {
    streak += 1;
    cursor.setDate(cursor.getDate() - 1);
  }
  return streak;
}

async function loadHabits() {
  const habits =
    (await run(
      supabase.from("habits").select("*").eq("is_active", true).order("sort_order"),
      "cargar los hábitos"
    )) ?? [];

  const logs = (await run(supabase.from("habit_logs").select("*"), "cargar los registros")) ?? [];
  const list = $("habit-list");

  if (habits.length === 0) {
    list.innerHTML = `<li class="empty">Aún no tienes hábitos. Añade uno arriba.</li>`;
    return;
  }

  const today = startOfToday().getTime();
  const todaysLog = (habitId) =>
    logs.find((l) => {
      if (l.habit_id !== habitId) return false;
      const d = new Date(l.date);
      d.setHours(0, 0, 0, 0);
      return d.getTime() === today;
    });

  list.innerHTML = habits
    .map((h) => {
      const log = todaysLog(h.id);
      const streak = streakFor(h, logs.filter((l) => l.habit_id === h.id));
      const streakLabel = streak > 0 ? `<span class="streak">🔥 ${streak} días</span>` : "";

      const control =
        h.kind === "checkbox"
          ? `<button class="check ${log?.is_completed ? "is-checked" : ""}"
                     data-toggle-habit="${h.id}" data-completed="${!!log?.is_completed}"
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
        <div class="row-main">
          <div class="row-title">${esc(h.name)}</div>
          <div class="row-sub">${target} ${streakLabel}</div>
        </div>
        ${control}
        <button class="delete" data-delete-habit="${h.id}" title="Eliminar" aria-label="Eliminar">✕</button>
      </li>`;
    })
    .join("");

  list.querySelectorAll("[data-toggle-habit]").forEach((btn) => {
    btn.addEventListener("click", async () => {
      await upsertHabitLog(btn.dataset.toggleHabit, {
        is_completed: btn.dataset.completed !== "true",
      });
      loadHabits();
    });
  });

  list.querySelectorAll("[data-log-habit]").forEach((input) => {
    input.addEventListener("change", async () => {
      const value = input.value === "" ? null : Number(input.value);
      // Un número registrado cuenta como "hecho" ese día, se cumpla el
      // objetivo o no — igual que HabitRepository.logValue en iOS.
      await upsertHabitLog(input.dataset.logHabit, { value, is_completed: value != null });
      loadHabits();
    });
  });

  list.querySelectorAll("[data-delete-habit]").forEach((btn) => {
    btn.addEventListener("click", async () => {
      // habit_logs cae solo por el ON DELETE CASCADE del esquema.
      await run(
        supabase.from("habits").delete().eq("id", btn.dataset.deleteHabit),
        "eliminar el hábito"
      );
      loadHabits();
    });
  });
}

/** Crea o actualiza el registro de HOY para un hábito. */
async function upsertHabitLog(habitId, fields) {
  const today = startOfToday();
  const existing = await run(
    supabase
      .from("habit_logs")
      .select("id")
      .eq("habit_id", habitId)
      .gte("date", today.toISOString())
      .lt("date", startOfTomorrow().toISOString())
      .limit(1),
    "buscar el registro de hoy"
  );

  if (existing?.length) {
    return run(
      supabase
        .from("habit_logs")
        .update({ ...fields, updated_at: nowISO() })
        .eq("id", existing[0].id),
      "guardar el hábito"
    );
  }

  return run(
    supabase.from("habit_logs").insert({
      habit_id: habitId,
      date: today.toISOString(),
      is_completed: false,
      ...fields,
      updated_at: nowISO(),
    }),
    "guardar el hábito"
  );
}

$("habit-form").addEventListener("submit", async (event) => {
  event.preventDefault();
  const numeric = $("habit-kind").value === "numeric";
  await run(
    supabase.from("habits").insert({
      name: $("habit-name").value.trim(),
      symbol_name: "checkmark.circle.fill",
      kind: $("habit-kind").value,
      target_value: numeric ? Number($("habit-target").value) || null : null,
      goal_direction: numeric ? $("habit-direction").value : "atLeast",
      unit: numeric ? $("habit-unit").value.trim() || null : null,
      is_active: true,
      sort_order: 0,
      linked_to_workouts: false,
      updated_at: nowISO(),
    }),
    "guardar el hábito"
  );
  event.target.reset();
  $("habit-kind").dispatchEvent(new Event("change"));
  loadHabits();
});

// ── Inicio ──────────────────────────────────────────────────────────

async function loadHome() {
  const [entries, goal, budget, transactions] = await Promise.all([
    todaysFood(),
    nutritionGoal(),
    budgetSettings(),
    monthTransactions(),
  ]);

  // Calorías
  const consumed = (entries ?? []).reduce((sum, e) => sum + (e.calories ?? 0), 0);
  const goalCalories = goal?.daily_calorie_goal ?? 2000;
  const remaining = goalCalories - consumed;
  $("home-calories").textContent = Math.round(remaining);
  $("home-calories-detail").textContent =
    `${Math.round(consumed)} de ${Math.round(goalCalories)} kcal · ${(entries ?? []).length} comidas`;
  const bar = $("home-calories-bar");
  bar.style.width = `${Math.min(100, (consumed / goalCalories) * 100)}%`;
  bar.classList.toggle("is-over", consumed > goalCalories);

  // Hábitos
  const habits =
    (await run(
      supabase.from("habits").select("*").eq("is_active", true),
      "cargar los hábitos"
    )) ?? [];
  const logs = (await run(supabase.from("habit_logs").select("*"), "cargar los registros")) ?? [];
  const today = startOfToday().getTime();
  const metToday = habits.filter((h) => {
    const log = logs.find((l) => {
      if (l.habit_id !== h.id) return false;
      const d = new Date(l.date);
      d.setHours(0, 0, 0, 0);
      return d.getTime() === today;
    });
    return goalMet(h, log);
  }).length;
  $("home-habits").textContent = habits.length ? `${metToday}/${habits.length}` : "—";
  $("home-habits-detail").textContent = habits.length
    ? metToday === habits.length
      ? "¡Todos cumplidos hoy!"
      : "Cumplidos hoy"
    : "Aún no tienes hábitos.";

  // Próxima tarea
  const upcoming =
    (await run(
      supabase
        .from("planner_tasks")
        .select("*")
        .eq("is_completed", false)
        .not("due_date", "is", null)
        .gte("due_date", startOfToday().toISOString())
        .order("due_date", { ascending: true })
        .limit(1),
      "cargar tu próxima tarea"
    )) ?? [];
  $("home-next").textContent = upcoming[0]?.title ?? "Nada pendiente";
  $("home-next-detail").textContent = upcoming[0]?.due_date ? dayOf(upcoming[0].due_date) : "";

  // Disponible
  const spent = (transactions ?? [])
    .filter((t) => t.type === "expense")
    .reduce((sum, t) => sum + (t.amount ?? 0), 0);
  const monthlyBudget = budget?.monthly_budget ?? 0;
  $("home-available").textContent = money(Math.max(0, monthlyBudget - spent));
  $("home-available-detail").textContent =
    `${money(spent)} gastado de ${money(monthlyBudget)}`;
}

// ── Arranque y sesión ───────────────────────────────────────────────

function showAuth() {
  $("boot").hidden = true;
  $("app").hidden = true;
  $("auth-screen").hidden = false;
}

function showApp() {
  $("boot").hidden = true;
  $("auth-screen").hidden = true;
  $("app").hidden = false;
  loadHome();
}

supabase.auth.onAuthStateChange((_event, session) => {
  if (session) {
    showApp();
  } else {
    showAuth();
    setAuthMessage("");
  }
});

// Sesión inicial: onAuthStateChange también dispara al arrancar, pero
// comprobarlo aquí evita el parpadeo de la pantalla de carga.
const { data: { session } } = await supabase.auth.getSession();
if (session) showApp();
else showAuth();

setAuthMode("signin");
