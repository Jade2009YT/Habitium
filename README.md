# Habitium

Aplicación nativa para iOS/watchOS enfocada en el cuidado personal integral:
nutrición (con IA), calendario/recordatorios, medicación, hábitos,
entrenamientos y finanzas personales — todo en un dashboard unificado, con
soporte para Widgets de iOS y una app de Apple Watch. Empezó pensada para uso
personal 100% local; desde la **Fase 2** (ver más abajo), cada cuenta
registrada con email también sincroniza sus datos por Supabase, para que sean
los mismos en cualquier dispositivo — con una arquitectura limpia y modular
pensada desde el principio para poder publicarla más adelante.

## Stack

- **UI**: Swift + SwiftUI (iOS), SwiftUI (watchOS)
- **Arquitectura**: MVVM + Clean Architecture (Models → Repositories →
  UseCases → ViewModels → Views)
- **Persistencia**: SwiftData en el dispositivo (rápida, funciona offline,
  cifrada — ver "Seguridad y privacidad" más abajo), almacenada en un
  contenedor de App Group para que la app y los widgets compartan datos.
  Desde la Fase 2, `CloudSyncService` la mantiene en línea con Supabase
  Postgres para las cuentas de email — ver la sección dedicada.
- **Widgets**: WidgetKit, con 4 widgets (nutrición, finanzas, calendario,
  medicación) interactivos vía App Intents, para pantalla de inicio y
  pantalla de bloqueo
- **IA**: OpenAI (GPT-4o Vision) o Claude (Anthropic), seleccionable por el
  usuario, para analizar fotos/texto de comidas
- **Login**: Sign in with Apple (identidad únicamente local) o email +
  contraseña vía Supabase Auth (identidad + sincronización en la nube) — el
  usuario elige cualquiera de los dos, o ambos
- **Notificaciones**: `UserNotifications` local (sin push remoto)
- **Generación del proyecto Xcode**: [XcodeGen](https://github.com/yonaskolb/XcodeGen)
  a partir de `project.yml` — el `.xcodeproj` no se versiona (ver `.gitignore`)

## Requisitos

- macOS con Xcode 15.4+ (iOS 17 SDK)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`
- Una cuenta de desarrollador de Apple (gratuita basta para pruebas locales)
  para habilitar el App Group en tu propio Team ID

## Puesta en marcha

```bash
git clone <este-repo>
cd Habitium

# 1. Configura tus API keys (nunca se suben al repo)
cp Configuration/Secrets.example.xcconfig Configuration/Secrets.xcconfig
# edita Configuration/Secrets.xcconfig con tus claves reales

# 2. Genera el proyecto Xcode
xcodegen generate

# 3. Ábrelo
open Habitium.xcodeproj
```

En Xcode:

1. Selecciona tu Team en **Signing & Capabilities** para los tres targets:
   `Habitium`, `HabitiumWidgetsExtension` y `HabitiumWatch`.
2. Confirma que el **App Group** `group.com.habitium.app` (o el que hayas
   puesto en `APP_GROUP_ID`) está habilitado en los tres — XcodeGen ya
   genera los `.entitlements` con esa capability, pero el grupo debe existir
   en tu cuenta de desarrollador (Xcode lo puede crear automáticamente con
   "Fix Issue" si falta).
3. Build & run sobre un iPhone (físico o simulador) con iOS 17+.

## Instalarla en tu iPhone para uso personal (gratis, sin App Store)

No hace falta pagar los 99 $/año del Apple Developer Program para tener
Habitium en tu propio teléfono — con tu Apple ID normal basta:

1. Conecta tu iPhone al Mac por cable (o usa Wi-Fi debugging) y ábrelo en
   Xcode: `Window → Devices and Simulators` para confirmarlo.
2. En el proyecto, ve a **Signing & Capabilities** (targets `Habitium` y
   `HabitiumWidgetsExtension`) y en **Team** elige "Add an Account…" con tu
   Apple ID si no aparece. Xcode generará un certificado de desarrollo
   gratuito automáticamente.
3. Selecciona tu iPhone como destino (arriba, junto al botón ▶️) y dale a
   **Run**.
4. La primera vez, iOS bloqueará la app como "de desarrollador no
   confiable". Ve a **Ajustes → General → VPN y gestión de dispositivos**
   en el iPhone y confía en tu Apple ID.
5. **Límite real**: con cuenta gratuita, la app deja de abrir a los 7 días y
   hay que volver a darle a Run desde Xcode para "renovarla". Si algún día
   quieres que dure indefinidamente (o distribuirla vía TestFlight/App
   Store), necesitas la cuenta de pago.

## ¿Y Google Play?

Sé honesto contigo: **este proyecto es Swift/SwiftUI, que solo corre en
iOS/iPadOS/macOS — no se puede publicar en Google Play tal cual.** Android
exige una app nativa en Kotlin/Java, o reescribirla con un framework
multiplataforma (Flutter, React Native, Kotlin Multiplatform). Eso sería un
proyecto aparte, no una opción de configuración aquí.

Si el objetivo es monetizar, lo que sí encaja de forma natural con este
código es una **suscripción en la App Store vía StoreKit 2** (ver siguiente
sección) — mismo proyecto, sin reescrituras. Android quedaría como una
decisión futura independiente, el día que de verdad quieras invertir en
ello.

## Inicio de sesión (Apple, email/contraseña, o sin cuenta)

`LoginView` ofrece tres formas de entrar, cualquiera de las tres desbloquea
la app (`RootView` comprueba
`authManager.isSignedIn || emailAuth.isSignedIn || localAccess.isUsingLocalOnly`).

**Empieza por aquí si estás construyendo esto con una cuenta de Apple
gratuita**: usa **"Usar sin cuenta"**. Sign in with Apple necesita un
entitlement que una cuenta gratuita no puede usar, y la opción de email solo
aparece si has configurado Supabase — así que en un primer arranque típico
las otras dos puertas están cerradas a la vez. La opción sin cuenta siempre
está disponible por eso mismo; puedes cambiar a una cuenta real más adelante
desde **Ajustes → Cuenta** sin perder nada de lo guardado.

### Sign in with Apple

Sin backend, sin contraseñas que proteger:

- **Apple verifica la identidad** (Face ID/Touch ID + tu Apple ID) — no hay
  contraseñas ni emails que Habitium tenga que proteger o filtrar por error.
- **Cero coste, cero mantenimiento.** No hay backend que tú tengas que
  pagar, actualizar o asegurar.
- **No hace falta para que las compras funcionen en varios dispositivos** —
  eso ya lo resuelve StoreKit solo (ver la siguiente sección). Este login es
  puramente de identidad: guarda tu nombre/email (solo la primera vez que
  Apple te los cede) en `UserSettings`, y el identificador estable de Apple
  en el Keychain (`Core/Auth/KeychainStore.swift`), nunca en texto plano.
- Si revocas el permiso desde **Ajustes del iPhone → tu nombre → Sign in
  with Apple**, Habitium lo detecta en el siguiente arranque
  (`credentialState(forUserID:)`) y te saca la sesión automáticamente.

Requiere que actives la capability **Sign in with Apple** en el target
`Habitium` con tu Team — XcodeGen ya genera el entitlement
(`com.apple.developer.applesignin`), pero Xcode necesita tu cuenta de
desarrollador conectada para firmarlo. **Con una cuenta de Apple gratuita
esto no funciona**: ese entitlement solo está disponible en el programa de
pago (99 €/año). Usa la opción "Usar sin cuenta" mientras tanto.

### Sin cuenta (solo en este iPhone)

Siempre disponible, y la vía correcta para uso personal con cuenta de Apple
gratuita. Guarda la elección en `UserDefaults`
(`Core/Auth/LocalAccessManager.swift`) y no cambia nada más: los datos ya
vivían en local de todos modos. Lo único que no tienes es la sincronización
entre dispositivos, que por definición necesita una cuenta de Supabase.

### Registro con email y contraseña (Supabase Auth)

Para quien prefiera crear una cuenta clásica en vez de usar su Apple ID —
y, desde la Fase 2, la que hace falta para que los datos te funcionen igual
en varios dispositivos (ver esa sección más abajo). Supabase solo ve tu
email y tu contraseña (con hash, nunca en texto plano); el resto de tus
datos (comidas, medicación, finanzas, notas) sí viajan a Supabase Postgres
ahora, pero cifrados en tránsito (HTTPS) y aislados por cuenta con Row Level
Security — nadie más los puede leer, ni siquiera con la `anon key` pública
de la app. Si entras solo con Sign in with Apple (sin cuenta de email),
nada de esto aplica: sigue siendo 100% local, como al principio.

Puesta en marcha:

1. Crea un proyecto gratis en [supabase.com](https://supabase.com).
2. En el proyecto: **Project Settings → API** — copia la **Project URL** y
   la **anon/public key**.
3. En `Configuration/Secrets.xcconfig`, rellena:
   ```
   SUPABASE_URL_SCHEME = https
   SUPABASE_URL_HOST = tu-proyecto.supabase.co
   SUPABASE_ANON_KEY = tu_clave_anon
   ```
   (la URL va partida en dos porque `//` es un comentario en formato
   xcconfig — `AppConfiguration.swift` la reconstruye).
4. En Supabase, **Authentication → Providers → Email** ya viene con
   "Confirm email" activado por defecto — así el registro pide verificar el
   correo antes de dejar entrar, tal y como lo montamos.

Si no rellenas las claves, `SupabaseAuthManager.isConfigured` es `false` y
`LoginView` simplemente no muestra la opción de email — Sign in with Apple
sigue funcionando igual.

**Aviso honesto**: `SupabaseAuthManager.swift` usa la API de
`supabase-swift` v2 (`client.auth.signUp/signIn/signOut/resend/
resetPasswordForEmail`) tal y como la documenta Supabase, pero lo escribí
sin poder compilarlo contra el paquete real. Si Xcode marca algún nombre de
método como inexistente, casi seguro es un renombrado casi idéntico (mira
el autocompletado de `client.auth.` — la arquitectura de alrededor no
debería tener que cambiar, solo esa línea).

## Seguridad local (App Lock + cifrado en reposo)

Sign in with Apple responde a "¿quién eres?". Esto de aquí responde a "¿quién
tiene tu iPhone desbloqueado en la mano ahora mismo?" — son capas
independientes, a propósito, y todo sigue sin servidor:

- **App Lock con Face ID/Touch ID** (`Core/Security/AppLockManager.swift`):
  Habitium se bloquea cada vez que vuelve de segundo plano, y solo se abre
  con biometría (o el código del dispositivo como respaldo). Se puede
  desactivar en **Ajustes → Seguridad**, pero viene activado por defecto.
- **Cifrado en reposo (Data Protection)**
  (`Core/Persistence/PersistenceController.swift`): el almacén de SwiftData
  se marca con `NSFileProtectionComplete`, la clase de protección más
  fuerte de iOS — el archivo es ilegible en cuanto el teléfono se bloquea,
  incluso para quien tuviera acceso físico al disco. El identificador de
  Sign in with Apple en el Keychain usa
  `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` (nunca viajero en un backup
  a otro dispositivo).
- **Fotos de comida cifradas con una clave del Secure Enclave**
  (`Core/Security/SecureEnclaveCrypto.swift`): la clave de cifrado se genera
  *dentro* del chip Secure Enclave y nunca sale de él. Guardar una foto no
  pide Face ID (usa solo la mitad pública de la clave); **verla** sí lo pide
  (botón 🖼️ junto a cualquier comida registrada con foto), porque esa
  operación sí usa la mitad privada, protegida por biometría.

En conjunto: si alguien coge tu iPhone desbloqueado, igual sigue sin poder
entrar a Habitium (App Lock). Si de algún modo accediera a los archivos en
crudo, están cifrados salvo que el teléfono esté desbloqueado (Data
Protection). Y las fotos de tus comidas necesitan tu cara, literalmente, para
poder verse.

**Compromiso a tener en cuenta**: con `NSFileProtectionComplete`, ninguna
tarea en segundo plano puede tocar la base de datos mientras el teléfono
está bloqueado — Habitium no lo necesita hoy (todo pasa en primer plano o
vía el snapshot de los widgets, que vive aparte en `UserDefaults`), pero si
algún día añades algo que sí lo necesite, tenlo presente.

## Licencia "Habitium Pro" (StoreKit 2) — preparada pero apagada

Hay dos formas de desbloquear "Pro" ya montadas en
`Core/Monetization/SubscriptionManager.swift`, pensadas para si algún día
publicas la app:

- **Suscripción mensual** — `com.habitium.app.pro.monthly`, 5,00 €/mes.
- **Pago único de por vida** — `com.habitium.app.lifetime`, 100,00 €,
  compra no-consumible (una sola vez, sin renovación).

Detalles:

- **Ahora mismo no bloquea nada.** Toda la app está desbloqueada para ti,
  compres o no — es solo scaffolding.
- Para probarlo localmente sin gastar nada ni tocar App Store Connect: abre
  el scheme `Habitium` en Xcode → **Edit Scheme → Run → Options → StoreKit
  Configuration** → selecciona `Configuration/Habitium.storekit`. Así puedes
  simular ambas compras en el Simulator.
- El estado se ve en **Ajustes → Habitium Pro** dentro de la app (accesible
  desde el ⚙️ en la pantalla de inicio).
- **No hace falta ningún sistema de login para que esto funcione en varios
  dispositivos tuyos.** StoreKit ata la compra a tu Apple ID automáticamente
  — "Restaurar compras" la recupera en cualquier iPhone donde inicies sesión
  con esa misma cuenta. Un sistema de cuentas propio solo haría falta para
  cosas que StoreKit no cubre (sincronizar tus *datos*, no solo si pagaste,
  o si algún día hubiera una versión no-Apple).
- Si algún día publicas de verdad, crea ambos productos en App Store Connect
  con esos mismos identificadores y ya funciona contra el sistema real.

## Gestión de secretos

Las API keys **nunca** se hardcodean. `Configuration/Secrets.xcconfig` está
en `.gitignore`; `Configuration/Secrets.example.xcconfig` es la plantilla que
sí se versiona. Los valores llegan a la app en runtime a través de
`Info.plist` (ver `project.yml` → `info.properties`) y se leen de forma
tipada en `AppConfiguration.swift`. Si falta una clave, los servicios de IA
lanzan `FoodAnalysisError.missingAPIKey` en vez de fallar silenciosamente.

## Estructura del proyecto

```
Habitium/
├── project.yml                     # Especificación XcodeGen (genera el .xcodeproj)
├── Configuration/                  # xcconfig — build settings y secrets
│   ├── Secrets.example.xcconfig    # plantilla (versionada)
│   ├── Secrets.xcconfig            # tus claves reales (gitignored)
│   ├── Debug.xcconfig
│   ├── Release.xcconfig
│   └── Habitium.storekit           # Config. local de StoreKit para probar la suscripción
├── Shared/                         # Compilado en LOS TRES targets (app + widgets + watch)
│   ├── AppGroup.swift               # ID del App Group
│   ├── WidgetKind.swift             # Identificadores de cada widget
│   ├── SharedDataStore.swift        # Snapshots Codable en UserDefaults(App Group)
│   ├── PendingWidgetActions.swift   # Cola de acciones widget → app
│   └── Intents/                     # App Intents para widgets interactivos
├── SharedWatch/                    # Compilado SOLO en app + watch (no en la extensión de widgets)
│   ├── WatchConnectivityBridge.swift # Sincroniza snapshots iPhone → Watch y series Watch → iPhone
│   └── LoggedWorkoutSet.swift       # Formato de una serie contada, cruza el WatchConnectivity
├── Habitium/                       # Target de la app
│   ├── App/                         # Entry point + configuración
│   ├── Core/
│   │   ├── DesignSystem/            # Colores, tipografías, tokens compartidos
│   │   ├── Navigation/              # MainTabView (TabView raíz)
│   │   ├── Persistence/             # SwiftData ModelContainer
│   │   ├── Networking/              # Clientes de OpenAI / Claude
│   │   ├── Notifications/           # Recordatorios locales
│   │   ├── Camera/                  # Captura de foto/código de barras (VisionKit)
│   │   ├── Auth/                    # Sign in with Apple + Keychain
│   │   ├── Security/                # App Lock (Face ID) + cifrado Secure Enclave
│   │   ├── Monetization/            # StoreKit 2 — suscripción/licencia "Habitium Pro"
│   │   ├── DeepLink/                # Enruta acciones desde los widgets
│   │   ├── Sync/                    # Aplica acciones pendientes de los widgets
│   │   ├── Widgets/                 # WidgetCenter.reloadTimelines wrapper
│   │   └── DI/                      # AppDependencyContainer (composition root)
│   ├── Models/                      # @Model de SwiftData (capa de datos, incl. WorkoutSet)
│   ├── Repositories/                # Protocolo + implementación SwiftData (incl. WorkoutRepository)
│   ├── UseCases/                    # Lógica de negocio (capa de dominio)
│   ├── Features/                    # Un folder por pestaña (MVVM)
│   │   ├── Auth/                     # LoginView, AppLockView
│   │   ├── Home/                     # Dashboard unificado
│   │   ├── Nutrition/                # FoodTrackerView + IA (cámara/galería/texto/código)
│   │   ├── Planner/                  # Calendario, tareas, notas
│   │   ├── Finance/                  # Ingresos/gastos, presupuesto
│   │   ├── Medication/                # Recordatorios y tomas de medicación
│   │   ├── Habits/                    # Hábitos diarios (incl. tiempo de pantalla manual)
│   │   └── Settings/                 # Metas, cuenta, seguridad, IA, notificaciones, moneda
│   └── Resources/Assets.xcassets
├── HabitiumWidgets/                # Extensión de WidgetKit (iOS)
│   ├── HabitiumWidgetsBundle.swift  # @main WidgetBundle
│   ├── NutritionWidget.swift
│   ├── FinanceWidget.swift
│   ├── CalendarWidget.swift
│   └── MedicationWidget.swift
├── HabitiumWatch/                  # App de watchOS
│   ├── HabitiumWatchApp.swift       # @main
│   ├── WatchSummaryView.swift       # Resumen de las 4 áreas + botón para entrenar
│   ├── WorkoutSessionManager.swift  # HKWorkoutSession/HKLiveWorkoutBuilder — mantiene vivo CoreMotion
│   ├── RepCounter.swift             # Contador de repeticiones (CoreMotion, detección de picos)
│   ├── WorkoutView.swift            # Pantalla de entrenamiento — reps en vivo, series, enviar al iPhone
│   └── Assets.xcassets
└── HabitiumTests/                  # Unit tests de UseCases (con fakes)
```

## Arquitectura

**Clean Architecture**, de afuera hacia adentro:

- **Models** (`Models/`): entidades `@Model` de SwiftData — la capa de datos.
- **Repositories** (`Repositories/`): protocolos (`NutritionRepository`,
  `PlannerRepository`, `FinanceRepository`) + una implementación SwiftData.
  Las ViewModels nunca importan `SwiftData` directamente.
- **UseCases** (`UseCases/`): lógica de negocio pura (p. ej.
  `CalculateRemainingCaloriesUseCase`), testeable con repositorios fake — ver
  `HabitiumTests`.
- **ViewModels** (`Features/*/*ViewModel.swift`): `@Observable`, orquestan
  UseCases y exponen estado a la vista.
- **Views** (`Features/*/*View.swift`): SwiftUI puro, sin lógica de negocio.

La composición de dependencias ocurre en un único lugar:
`AppDependencyContainer` (inyectado en el `Environment` desde `HabitiumApp`).

## Widgets interactivos

Los cuatro widgets (`NutritionWidget`, `FinanceWidget`, `CalendarWidget`,
`MedicationWidget`) leen snapshots `Codable` desde `SharedDataStore`
(respaldado por `UserDefaults(suiteName: APP_GROUP_ID)`) en vez de acceder a
SwiftData directamente — así evitamos contención entre procesos. Cada
repositorio de la app actualiza el snapshot correspondiente y llama a
`WidgetCenter.reloadTimelines` justo después de escribir en SwiftData.

Interactividad (App Intents en `Shared/Intents/`):

- **Escanear comida** / **Registrar gasto**: `openAppWhenRun = true` — abre
  la app y, vía `DeepLinkCoordinator`, navega directo al flujo correspondiente.
- **Completar tarea** / **Marcar toma de medicación**: `openAppWhenRun =
  false` — actualiza el snapshot al instante (el widget refleja el cambio
  sin abrir la app) y encola la escritura real, que `PendingActionProcessor`
  aplica a SwiftData la próxima vez que la app pasa a primer plano.

## Medicación

Sección nueva (`Features/Medication/`, accesible desde la tarjeta
"Medicación" en Inicio — no es una pestaña nueva, mismo patrón que Ajustes):

- Cada medicamento (`Medication`) tiene uno o más horarios de toma al día
  (`reminderMinutesSinceMidnight`), cada uno con su propio recordatorio local
  repetido a diario (`NotificationScheduler.scheduleMedicationReminders`).
- `MedicationDoseLog` registra si cada toma de cada día se marcó como
  **tomada** o **omitida** — así "Hoy" en `MedicationView` siempre refleja el
  estado real, no solo si existe el recordatorio.
- Se puede desactivar un medicamento sin borrarlo (cancela sus
  notificaciones pero conserva el historial).
- Tiene su propio widget con botón interactivo "marcar tomada" —
  mismo patrón que el de completar tareas.

## Hábitos (incluye "tiempo de pantalla" manual)

Sección nueva (`Features/Habits/`, tarjeta "Hábitos" en Inicio — mismo
patrón, no es una pestaña nueva). Nació de una pregunta concreta: "quiero
controlar mis horas de pantalla". La respuesta honesta está aquí abajo.

- Cada `Habit` es tipo **Sí/No** (ejercicio, leer, meditar...) o
  **numérico con objetivo** (tiempo de pantalla ≤ 3h, agua ≥ 8 vasos, dormir
  ≥ 8h) — `HabitGoalDirection` decide si cumplir la meta es quedarte por
  debajo o llegar como mínimo a un número.
- Racha por hábito (`HabitRepository.streak(for:)`), no solo global.
- Plantillas rápidas en `HabitTemplate.swift` para no partir de una hoja en
  blanco, incluida "Tiempo de pantalla" ya configurada.
- `Habit.linkedToWorkouts`: un hábito Sí/No (por defecto, la plantilla
  "Ejercicio") se puede marcar para que se complete solo en cuanto termina un
  entrenamiento contado desde el Apple Watch — sin tocar el iPhone. Lo
  resuelve `WorkoutRepository.save`, que llama a
  `HabitRepository.markCompletedToday` (idempotente: dos entrenamientos el
  mismo día no "des-completan" nada).

**Por qué es manual y no automático**: iOS protege muy en serio los datos
reales de Tiempo de Uso — leerlos o bloquear apps de verdad necesita el
permiso restringido `Family Controls`
(`FamilyControls`/`DeviceActivity`/`ManagedSettings`), que Apple tiene que
**aprobar a mano** tras rellenar un formulario, y que normalmente exige la
cuenta de pago de Apple Developer (99 $/año) para poder ni siquiera
solicitarlo. No es algo que se resuelva con código en una sesión — por eso
este módulo funciona hoy sin pedir ningún permiso especial: miras el número
que ya te da Ajustes → Tiempo de Uso y lo registras aquí, como cualquier
otro hábito. Si algún día consigues ese permiso de Apple, el hueco para
conectarlo de verdad ya está — solo faltaría que algo escriba en
`HabitLog` automáticamente en vez de que lo hagas tú a mano.

## Apple Watch

Solo Apple Watch: "cualquier reloj digital" no es viable con Swift/SwiftUI —
Garmin, Wear OS, etc. son sistemas operativos distintos, con SDKs propios;
sería un proyecto aparte por completo (igual que pasaba con Google Play).

Lo que hay montado en `HabitiumWatch/` (target watchOS independiente,
`project.yml`) y `SharedWatch/`:

- Una pantalla glanceable: calorías restantes, próxima toma de medicación,
  próximo evento, saldo disponible — el resumen de Inicio, pero en la
  muñeca.
- **Sincronización iPhone → Watch** (snapshots) vía `WatchConnectivity`
  (`SharedWatch/WatchConnectivityBridge.swift`), no App Groups — el iPhone y
  el Watch son dispositivos físicos distintos con almacenamiento separado,
  así que un App Group no comparte nada entre ellos por sí solo. Cada vez
  que un repositorio escribe algo, además de refrescar los widgets, empuja
  los cuatro snapshots al reloj con `updateApplicationContext` ("el último
  gana", ideal para datos de un vistazo, no necesita que ninguna app esté
  en primer plano).
- **Contador de repeticiones al entrenar** (`WorkoutView`, botón
  "Entrenar" en la esquina de la pantalla del reloj):
  1. `WorkoutSessionManager` abre una `HKWorkoutSession` real (HealthKit) —
     no es ceremonia opcional: es lo que le da a la app acceso continuo en
     segundo plano al acelerómetro mientras la pantalla del reloj está
     apagada o la muñeca baja. Sin sesión activa, CoreMotion se suspende en
     cuanto se apaga la pantalla.
  2. `RepCounter` lee `CMDeviceMotion` a 50 Hz, suaviza la magnitud de la
     aceleración con una media móvil exponencial y cuenta una repetición en
     cada cruce ascendente del umbral, con un tiempo mínimo entre
     repeticiones para no contar dos veces el mismo movimiento.
  3. Al terminar, `WatchConnectivityBridge.sendLoggedWorkoutSets` envía las
     series (`LoggedWorkoutSet`) al iPhone con `transferUserInfo` (a
     diferencia de `updateApplicationContext`, esto se **encola** y llega
     igual aunque el iPhone esté bloqueado o la app del reloj se cierre justo
     después de "Finalizar"). El iPhone las recibe en
     `WatchConnectivityBridge` (`didReceiveUserInfo`) y `WorkoutRepository`
     las guarda como `WorkoutSet` — y completa automáticamente cualquier
     hábito marcado como `linkedToWorkouts` (ver sección Hábitos).
  - **Aviso honesto**: esto es detección de picos sobre la aceleración de la
    muñeca, no el nivel de un sensor de barra dedicado (PUSH Band, Vitruve,
    GymAware...) — no da velocidad ni potencia de la barra, solo un conteo
    de repeticiones. Funciona bien en ejercicios donde la muñeca se mueve
    con el peso (curl, press, remo); peor en los que la muñeca casi no se
    mueve (sentadilla sin agarrar nada, prensa). Suficiente para registrar
    "hoy entrené" sin comprar un sensor aparte — no es un instrumento de
    laboratorio.

**Qué falta a propósito (v2, más delicado):**
- **Interactuar con medicación/tareas desde el reloj** (marcar una toma
  como hecha, completar una tarea) — necesita sincronización en las dos
  direcciones, con manejo de conflictos si ambos dispositivos cambian algo
  casi a la vez. Nada de eso está montado todavía; el contador de
  repeticiones es la primera pieza de escritura Watch → iPhone, no cubre el
  resto.
- **Complicación para la esfera del reloj** — necesitaría otro target
  (extensión de widgets para watchOS) encima del target de la app; lo dejé
  fuera de esta ronda para no arriesgar la configuración del target
  principal, que ya es la parte más delicada de todo el `project.yml`.

**Aviso honesto**: el target de watchOS es, con diferencia, el tipo de
target más delicado de configurar bien a ciegas (sin poder compilar yo
mismo para comprobarlo). Si `xcodegen generate` o Xcode se quejan de
`HabitiumWatch`, el plan B está anotado como comentario en el propio
`project.yml`: borra ese target de ahí, añade uno nuevo a mano en Xcode
(**File → New → Target → watchOS → App**), y apunta sus fuentes a
`HabitiumWatch/` y `SharedWatch/`.

## Fase 2 — multidispositivo (Supabase como origen de verdad)

Origen: un amigo con Android quería usar Habitium con frecuencia, y el iPad
del cole solo permite páginas web — para que a los dos les funcione con
**su propia cuenta y sus propios datos**, hacía falta dejar de guardar todo
solo en el iPhone. Esto es el cambio de arquitectura para conseguirlo.

**Qué cambió exactamente**: hasta ahora, crear una cuenta por email
(`SupabaseAuthManager`) era solo identidad — ningún dato viajaba. Desde esta
ronda, sí viaja: `Core/Sync/CloudSyncService.swift` mantiene sincronizados
SwiftData (en el dispositivo) y las tablas de Supabase Postgres
(`supabase/schema.sql`) para cualquier cuenta que haya iniciado sesión por
email/contraseña.

- **Solo cuentas de email, no Sign in with Apple**: Apple no crea una sesión
  de Supabase, así que no hay un `auth.uid()` al que Postgres pueda atar tus
  filas. Si entras solo con Apple, Habitium sigue funcionando exactamente
  como antes — 100% local, nada sale del dispositivo. La sincronización es
  un añadido para quien elige la cuenta de email, no algo que le pasó a todo
  el mundo sin avisar.
- **Cuándo sincroniza**: al abrir la app, al volver a primer plano, y justo
  después de iniciar sesión — no en cada pulsación. `CloudSyncService.syncAll`
  hace un reconcile completo (baja todo lo del usuario, sube todo lo local)
  en vez de subir solo lo que cambió; a la escala de una persona (o dos) es
  barato y, sobre todo, mucho más fácil de tener bien sin compilador que
  llevar la cuenta de qué fila concreta cambió.
- **Quién gana un conflicto**: cada tabla tiene `updated_at`, puesto siempre
  por el dispositivo que hizo el cambio real (cada método de cada
  repositorio que muta algo lo actualiza) — nunca por el servidor. Al
  fusionar, gana la copia con `updated_at` más nuevo. Ver
  `supabase/README.md` para el porqué de que sea el cliente y no un trigger.
- **Los borrados sí se propagan**: cada `deleteX` de cada repositorio
  también inserta un `PendingCloudDeletion` (una "tumba") en el mismo
  `save()` que el borrado real — `CloudSyncService` las vacía al principio
  de cada sincronización, antes de bajar nada, para que un elemento borrado
  no reaparezca "como si fuera nuevo" en la siguiente sincronización.
- **Qué NO sincroniza a propósito**: las fotos de las comidas, los
  identificadores de notificaciones locales, y las claves de IA — ver
  `supabase/README.md` para el detalle de cada una.

Archivos nuevos de esta ronda:

- `supabase/schema.sql` + `supabase/README.md` — el esquema de Postgres
  (16 tablas, Row Level Security por `user_id`) y cómo aplicarlo.
- `Core/Sync/CloudSyncDTOs.swift` — un `Codable` por tabla, con
  `CodingKeys` explícitas a snake_case.
- `Core/Sync/CloudSyncTransport.swift` — la única capa que habla con
  Postgrest de verdad (upsert/fetch/delete), con fallos silenciosos
  (offline no debe romper nada; los datos reales siguen en SwiftData).
- `Core/Sync/CloudSyncService.swift` — el reconcile en sí, tabla por tabla.
- `Models/PendingCloudDeletion.swift` — las tumbas para propagar borrados.
- Todos los `@Model` ganaron un campo `updatedAt` que antes no tenían
  (los que ya llevaban uno, como `PlannerNote`, `NutritionGoal` o
  `BudgetSettings`, se quedaron igual).

**Aviso honesto**: igual que con supabase-swift y el target de watchOS, esto
está escrito contra el patrón documentado de `PostgrestClient` en
supabase-swift v2 (`.from(tabla).select()/.upsert()/.delete()/.eq()/.execute()`)
sin poder compilarlo yo mismo. Si Xcode se queja de algún nombre de método,
lo más probable es que sea un cambio de nombre casi idéntico — la
arquitectura de estos archivos no debería necesitar cambiar por eso.

**Qué falta a propósito**: la app nativa de Android — este apartado es solo
la base de datos compartida que Android también usará cuando llegue.

### Web (`web/`)

Ya construida y funcionando sobre estas mismas tablas: HTML, CSS y un JS,
sin servidor propio. Cubre login/registro, Inicio, Nutrición, Agenda,
Finanzas y Hábitos. Pensada para el iPad del cole (que solo permite
páginas web) y para cualquier Android sin instalar nada, y preparada para
"Añadir a pantalla de inicio" como si fuera una app.

Misma arquitectura que iOS: **los datos viven en el dispositivo**
(IndexedDB, vía `web/store.js`) y la nube es la copia que los iguala en
todos lados, con la misma regla de "gana el más reciente" y la misma
propagación de borrados. Un service worker (`web/sw.js`) cachea los
archivos de la app, así que arranca al instante y sigue funcionando sin
conexión o con el NAS apagado. Ver `web/README.md` para ponerla en marcha
y para publicarla en un Synology con Web Station.

## Lo mejor de las apps mejor valoradas, adaptado a Habitium

Antes de esta ronda, investigué qué hace tan queridas a la app de nutrición,
la de finanzas (que no fuera un banco) y la de calendario mejor valoradas de
la App Store, y adapté lo más valioso de cada una:

| Inspirado en | Qué hace bien | Dónde está en Habitium |
|---|---|---|
| **PlateLens** (4.8★) / **Lose It!** | Tendencia de peso + repetir comida en un toque | `WeightTrendCard`, `FoodTrackerViewModel.repeatEntry` |
| **Fooducate** / **Lose It!** | Racha de días registrando, como refuerzo motivacional | `CalculateLoggingStreakUseCase` |
| **Monarch Money** (4.8★) / **Goodbudget** | Presupuesto por categoría (sobres) + desglose visual | `CategoryBudget`, `CategoryDonutChart`, `CategoryBudgetsSheet` |
| **EveryDollar** | Meta de ahorro con monto y fecha objetivo | `BudgetSettings.savingsGoal*`, `SavingsGoalCard` |
| **Fantastical** (4.6★, Apple Design Award) | Crear eventos escribiendo en lenguaje natural | `NaturalLanguageQuickAdd`, `QuickAddBar` |
| **Structured** | Vista de línea de tiempo por horas, no solo una lista | `DayTimelineView` |

Segunda ronda — el resto del backlog, ya cerrado:

| Inspirado en | Qué hace bien | Dónde está en Habitium |
|---|---|---|
| **PlateLens** | Objetivo de calorías que se recalibra solo según tu tendencia real de peso | `CalculateAdaptiveCalorieGoalUseCase`, `AdaptiveGoalCard` (opt-in en Ajustes) |
| **Sunsama** | "Foco del día" — 1-3 prioridades en vez de una lista larga | `PlannerTask.isFocus`, tarjeta en `HomeView` |
| **Monarch Money** / **EveryDollar** | Gastos/ingresos fijos que se registran solos cada mes | `RecurringTransaction`, `RecurringTransactionsSheet` |
| **MyFitnessPal** / **Fooducate** | Escanear el código de barras de un producto envasado | `BarcodeScannerView` (VisionKit) + `OpenFoodFactsService` (API gratuita, sin key) |

### Backlog restante (a propósito, no implementado)

- Notificaciones inteligentes basadas en patrones de uso.
- Compartir/exportar reportes (PDF o imagen) del resumen mensual.
- ~~Sincronización opcional entre dispositivos propios~~ — hecho en la Fase 2
  (ver esa sección), aunque solo para cuentas de email, no Sign in with Apple.

## Otros próximos pasos sugeridos

- Sustituir los placeholders de `AppIcon`/`AccentColor` por assets reales.
- Añadir Live Activities para el registro de comidas en curso.
- Exportar/importar datos (backup manual, ya que todo es local).
- Tests de UI con `XCUITest` para los flujos principales.
