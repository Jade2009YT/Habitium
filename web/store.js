// store.js — datos locales (IndexedDB) + sincronización con Supabase.
//
// Es el equivalente en la web de lo que CloudSyncService.swift hace en
// iOS, y con las mismas reglas para que las dos nunca discrepen:
//
//   · Lo local manda para leer y escribir. La interfaz nunca espera a la
//     red: pinta desde IndexedDB al instante y la sincronización ocurre
//     por detrás. Por eso la app abre y funciona sin conexión.
//   · "Gana el más reciente" (updated_at) al fusionar una fila que existe
//     en los dos sitios. Ese timestamp lo pone SIEMPRE el dispositivo que
//     hizo el cambio real, nunca el servidor — igual que en iOS, y por la
//     misma razón: si el servidor lo reescribiera en cada subida, un
//     reenvío rutinario sin cambios parecería "más nuevo" que una edición
//     de verdad hecha en otro dispositivo, y esa edición se perdería.
//   · Los borrados van en la cola de salida como una operación más, para
//     que no reaparezcan al siguiente pull. Es el papel que juega
//     PendingCloudDeletion en iOS.
//
// La cola de salida (_outbox) es lo que hace posible escribir sin
// conexión: cada cambio se guarda localmente Y se encola; cuando vuelve
// la red se vacía en orden. Si una operación falla por algo que no es la
// red (por ejemplo datos inválidos), se descarta en vez de bloquear la
// cola para siempre.

const DB_NAME = "habitium";
// v2: xp_events + player_profiles (progresión). Subir este número es
// OBLIGATORIO al añadir una tabla: onupgradeneeded solo se ejecuta
// cuando la versión cambia, así que sin esto quien ya tuviera la app
// abierta alguna vez se quedaría sin los almacenes nuevos y fallaría al
// escribir, mientras que en un navegador nuevo funcionaría. Un fallo que
// solo le pasa a los que ya la usaban es de los peores de encontrar.
const DB_VERSION = 2;

/** Tablas replicadas en local. Deben existir en supabase/schema.sql. */
export const TABLES = [
  "food_entries",
  "weight_entries",
  "planner_tasks",
  "planner_events",
  "planner_notes",
  "transactions",
  "category_budgets",
  "recurring_transactions",
  "medications",
  "medication_dose_logs",
  "habits",
  "habit_logs",
  "workout_sets",
  "xp_events",
];

/** Tablas con exactamente una fila por usuario: se emparejan por
 *  user_id, no por id — igual que CloudSyncService.syncSingleton. */
export const SINGLETONS = [
  "nutrition_goals",
  "budget_settings",
  "user_settings",
  "player_profiles",
];

const ALL_TABLES = [...TABLES, ...SINGLETONS];
const META = "_meta";
const OUTBOX = "_outbox";

// ── IndexedDB (envoltorio mínimo sobre la API de callbacks) ─────────

let dbPromise = null;

function openDB() {
  if (dbPromise) return dbPromise;
  dbPromise = new Promise((resolve, reject) => {
    const req = indexedDB.open(DB_NAME, DB_VERSION);
    req.onupgradeneeded = () => {
      const db = req.result;
      for (const t of ALL_TABLES) {
        if (!db.objectStoreNames.contains(t)) db.createObjectStore(t, { keyPath: "id" });
      }
      if (!db.objectStoreNames.contains(OUTBOX)) {
        db.createObjectStore(OUTBOX, { keyPath: "seq", autoIncrement: true });
      }
      if (!db.objectStoreNames.contains(META)) {
        db.createObjectStore(META, { keyPath: "key" });
      }
    };
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error);
  });
  return dbPromise;
}

function tx(db, store, mode) {
  return db.transaction(store, mode).objectStore(store);
}

const asPromise = (req) =>
  new Promise((resolve, reject) => {
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error);
  });

async function idbAll(store) {
  const db = await openDB();
  return asPromise(tx(db, store, "readonly").getAll());
}

async function idbPut(store, value) {
  const db = await openDB();
  return asPromise(tx(db, store, "readwrite").put(value));
}

async function idbDelete(store, key) {
  const db = await openDB();
  return asPromise(tx(db, store, "readwrite").delete(key));
}

async function idbClear(store) {
  const db = await openDB();
  return asPromise(tx(db, store, "readwrite").clear());
}

// ── Estado observable ───────────────────────────────────────────────

export const syncState = {
  online: navigator.onLine,
  syncing: false,
  pending: 0,
  lastSync: null,
  lastError: null,
};

const listeners = new Set();
/** Se llama tras cada cambio local o sincronización, para repintar. */
export function onChange(fn) {
  listeners.add(fn);
  return () => listeners.delete(fn);
}
function emit() {
  for (const fn of listeners) fn();
}

// ── API de datos (lo que usa app.js) ────────────────────────────────

const nowISO = () => new Date().toISOString();
const newID = () =>
  crypto.randomUUID?.() ??
  // Safari antiguo no trae randomUUID; getRandomValues sí está en todos
  // los navegadores con IndexedDB, así que esto siempre resuelve.
  "10000000-1000-4000-8000-100000000000".replace(/[018]/g, (c) =>
    (c ^ (crypto.getRandomValues(new Uint8Array(1))[0] & (15 >> (c / 4)))).toString(16)
  );

/** Todas las filas locales de una tabla. */
export const all = (table) => idbAll(table);

/** Inserta una fila: local al instante + encolada para subir. */
export async function insert(table, payload) {
  const row = { id: newID(), ...payload, updated_at: nowISO() };
  await idbPut(table, row);
  await enqueue({ op: "upsert", table, row });
  emit();
  return row;
}

/** Modifica campos de una fila existente. */
export async function update(table, id, fields) {
  const rows = await idbAll(table);
  const existing = rows.find((r) => r.id === id);
  if (!existing) return null;
  const row = { ...existing, ...fields, updated_at: nowISO() };
  await idbPut(table, row);
  await enqueue({ op: "upsert", table, row });
  emit();
  return row;
}

/** Borra una fila aquí y encola el borrado para la nube. */
export async function remove(table, id) {
  await idbDelete(table, id);
  await enqueue({ op: "delete", table, id });

  // Las tablas hijas caen por ON DELETE CASCADE en Postgres, pero eso
  // solo ocurre en el servidor — en local hay que limpiarlas a mano o
  // quedarían huérfanas hasta el siguiente pull.
  const cascades = { habits: ["habit_logs"], medications: ["medication_dose_logs"] };
  for (const child of cascades[table] ?? []) {
    const key = table === "habits" ? "habit_id" : "medication_id";
    for (const row of await idbAll(child)) {
      if (row[key] === id) await idbDelete(child, row.id);
    }
  }

  emit();
}

/** Crea o actualiza la única fila del usuario en una tabla singleton. */
export async function putSingleton(table, fields) {
  const rows = await idbAll(table);
  const row = { id: rows[0]?.id ?? newID(), ...rows[0], ...fields, updated_at: nowISO() };
  await idbPut(table, row);
  await enqueue({ op: "singleton", table, row });
  emit();
  return row;
}

/** La única fila del usuario, o null. */
export async function getSingleton(table) {
  return (await idbAll(table))[0] ?? null;
}

// ── Cola de salida ──────────────────────────────────────────────────

async function enqueue(entry) {
  await idbPut(OUTBOX, { ...entry, at: nowISO() });
  syncState.pending = (await idbAll(OUTBOX)).length;
  // Intento inmediato: si hay red, el cambio sube en el acto y el
  // usuario nunca ve el estado "pendiente".
  if (navigator.onLine) sync().catch(() => {});
}

/** ¿Está esta fila esperando a subir? Sirve para no borrarla en el
 *  pull solo porque el servidor todavía no la conoce. */
async function pendingIDs() {
  const entries = await idbAll(OUTBOX);
  return new Set(entries.map((e) => e.row?.id ?? e.id).filter(Boolean));
}

// ── Sincronización ──────────────────────────────────────────────────

let supabase = null;
let getUserID = async () => null;

/** app.js llama a esto una vez, tras iniciar sesión. */
export function configure(client, userIDGetter) {
  supabase = client;
  getUserID = userIDGetter;
}

/** Borra todo lo local — al cerrar sesión, para no dejar los datos de
 *  una cuenta visibles a la siguiente que entre en este navegador. */
export async function wipe() {
  for (const t of [...ALL_TABLES, OUTBOX, META]) await idbClear(t);
  syncState.pending = 0;
  syncState.lastSync = null;
  emit();
}

let syncing = false;

export async function sync() {
  if (!supabase || syncing || !navigator.onLine) return;
  syncing = true;
  syncState.syncing = true;
  syncState.lastError = null;
  emit();

  try {
    await flushOutbox();
    await pullAll();
    syncState.lastSync = new Date();
  } catch (error) {
    console.error("sync", error);
    syncState.lastError = error.message ?? String(error);
  } finally {
    syncing = false;
    syncState.syncing = false;
    syncState.pending = (await idbAll(OUTBOX)).length;
    emit();
  }
}

async function flushOutbox() {
  const entries = (await idbAll(OUTBOX)).sort((a, b) => a.seq - b.seq);
  const userID = await getUserID();

  for (const entry of entries) {
    let error = null;

    if (entry.op === "delete") {
      ({ error } = await supabase.from(entry.table).delete().eq("id", entry.id));
    } else if (entry.op === "singleton") {
      // Sin id: la fila se empareja por user_id, así que dejamos que
      // Postgres conserve la clave primaria que ya tuviera.
      const { id, ...fields } = entry.row;
      ({ error } = await supabase
        .from(entry.table)
        .upsert({ ...fields, user_id: userID }, { onConflict: "user_id" }));
    } else {
      ({ error } = await supabase.from(entry.table).upsert(entry.row));
    }

    if (error) {
      // Un fallo de red debe reintentarse (la entrada se queda en la
      // cola); uno de datos, no — bloquearía la cola para siempre.
      const isNetwork =
        !navigator.onLine ||
        error.message?.includes("Failed to fetch") ||
        error.message?.includes("NetworkError");
      if (isNetwork) throw error;
      console.warn("Descartando operación inválida de la cola:", entry, error);
    }

    await idbDelete(OUTBOX, entry.seq);
  }
}

async function pullAll() {
  const keep = await pendingIDs();

  for (const table of TABLES) {
    const { data, error } = await supabase.from(table).select("*");
    if (error) throw error;

    const localRows = await idbAll(table);
    const localByID = new Map(localRows.map((r) => [r.id, r]));
    const remoteIDs = new Set();

    for (const remote of data) {
      remoteIDs.add(remote.id);
      const local = localByID.get(remote.id);
      // Gana el más reciente. Sin fecha local, gana lo remoto.
      if (!local || new Date(remote.updated_at) > new Date(local.updated_at ?? 0)) {
        await idbPut(table, remote);
      }
    }

    // Lo que ya no está en el servidor se borró desde otro dispositivo —
    // salvo lo que todavía no hemos llegado a subir.
    for (const local of localRows) {
      if (!remoteIDs.has(local.id) && !keep.has(local.id)) {
        await idbDelete(table, local.id);
      }
    }
  }

  for (const table of SINGLETONS) {
    const { data, error } = await supabase.from(table).select("*").limit(1);
    if (error) throw error;
    const remote = data?.[0];
    if (!remote) continue;

    const local = (await idbAll(table))[0];
    if (!local || new Date(remote.updated_at) > new Date(local.updated_at ?? 0)) {
      // Se reemplaza entera: local y remoto pueden tener ids distintos
      // (cada dispositivo creó el suyo), y solo debe quedar una.
      await idbClear(table);
      await idbPut(table, remote);
    }
  }
}

// ── Disparadores automáticos ────────────────────────────────────────

window.addEventListener("online", () => {
  syncState.online = true;
  emit();
  sync();
});

window.addEventListener("offline", () => {
  syncState.online = false;
  emit();
});

// Al volver a la pestaña: puede haber cambios hechos desde el móvil.
document.addEventListener("visibilitychange", () => {
  if (document.visibilityState === "visible") sync();
});

// Red de seguridad para sesiones largas abiertas todo el día.
setInterval(() => sync(), 5 * 60 * 1000);

// Si la sesión anterior se cerró con cambios sin subir, el contador debe
// reflejarlo desde el primer pintado, no quedarse en cero hasta el
// siguiente cambio.
idbAll(OUTBOX)
  .then((entries) => {
    if (!entries.length) return;
    syncState.pending = entries.length;
    emit();
  })
  .catch(() => {});
