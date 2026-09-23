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

## Sin cuenta: Habitium contra el navegador y nada más

En la pantalla de entrada hay un **"Usar sin cuenta"**. Todo se guarda en
el dispositivo y no sale de ahí: sin registro, sin servidor, sin que
nadie te invite. Le pasas el enlace a un amigo y lo usa en su Android el
mismo día.

Por dentro casi no cambia nada, y eso es lo bueno: la app **siempre** ha
guardado todo en IndexedDB, y Supabase solo servía para copiarlo entre
tus dispositivos. Quitarlo de la ecuación es no llamar a
`store.configure()`.

Lo que sí hubo que cuidar:

- **La cola de subida no se llena.** `enqueue()` sale temprano en modo
  local: sin servidor al que subir, guardar una cola que nunca se vacía
  solo ocupa sitio en el móvil para siempre.
- **"Salir" no borra nada.** Con cuenta sí se borra lo local al cerrar
  sesión (el iPad del instituto). Sin cuenta, los datos son del
  dispositivo y no de una sesión: borrarlos sería tirar el trabajo de
  alguien que solo quería ver qué hay detrás del botón.
- **Supabase no manda.** Un `SIGNED_OUT` suyo —que llega solo por
  existir el cliente— echaría a la calle a quien entró sin cuenta.
- **Se puede salir del modo local sin perder nada.** `migrarANube()`
  encola todas las filas locales como si se acabaran de crear, y el sync
  normal hace el resto. Sin esa salida, el modo local sería una trampa
  amable: quien lo usa tres meses y luego quiere el portátil tendría que
  empezar de cero — y no lo haría.
- **Y se pueden descargar los datos.** Cuando la app te dice "esto solo
  está aquí", poder bajarte un archivo es el mínimo honesto.

Ajustes enseña la tarjeta de "Sin cuenta" con las dos cosas: dónde están
tus datos y **qué pasa si borras los del navegador**.

### Un fallo de la prueba que merece recordarse

`emptyState()` pinta un `<li class="empty">`, así que **una lista vacía
tiene un `li`**. Contar `#task-list li` a secas confunde "vacía" con "un
elemento", y la prueba decía que guardar no funcionaba cuando funcionaba
perfectamente. Los arneses cuentan ahora `li:not(.empty)`.

## Subirla a internet y ponerla en la pantalla de inicio

Se puede, y está construida para eso: manifest, service worker, iconos y
base de datos local. Subes `web/` a cualquier sitio con HTTPS, la añades
a la pantalla de inicio del iPhone y **se comporta como una app** —
icono propio, sin barra de Safari, pantalla completa y sin cobertura.

Dos guías, según dónde la pongas:

- **[`docs/synology-y-supabase.md`](docs/synology-y-supabase.md)** — la web
  en tu NAS y los datos en Supabase. Incluye los cuatro ajustes de
  Supabase que hay que tocar para que el login funcione fuera de tu
  ordenador; el que más se olvida es el de las **URL de redirección**,
  y sin él los correos de confirmación llevan a `localhost`.
- **[`docs/subir-a-internet.md`](docs/subir-a-internet.md)** — las
  opciones de hosting gratuito (Cloudflare Pages, Netlify) y la
  comparación honesta con la app nativa.
Lo que hay que saber antes de decidir:

- **Ya no caduca a los 7 días**, no hace falta Mac ni Xcode, funciona en
  Android, se actualiza sola y se la puedes pasar a alguien con un
  enlace.
- **Lo que se pierde**: los avisos con la app cerrada, el Apple Watch,
  los atajos de Siri y los widgets.

Lo de los avisos es lo que de verdad duele, y no es un fallo de
Habitium: la API que programaba notificaciones diferidas en el navegador
se probó en Chrome y se retiró. En la PWA los avisos saltan mientras la
app esté abierta (aunque sea de fondo) y al volver te recuerdan una vez
el que se acaba de pasar. Se arregla del todo con Web Push y un servidor
que empuje — con Supabase Edge Functions entra en el plan gratuito.

El manifest se llama **`manifest.json`** y no `manifest.webmanifest`,
que sería lo oficial: casi ningún servidor conoce esa extensión y la
sirve como texto plano — y cuando eso pasa, el iPhone ignora el manifest
entero y la app instalada se queda sin nombre, sin icono y abriéndose
dentro de Safari, sin dar ningún error. Es el fallo más típico al montar
una PWA en un servidor propio, y con `.json` no puede ocurrir.

### Tres cosas que salieron de probar la app instalada, en modo avión

Con la red puesta no se nota ninguna:

1. **La app no arrancaba sin conexión.** `app.js` importaba supabase-js
   de un CDN con un `import` estático, y un import que no se resuelve
   hace que el módulo **entero** no se evalúe: ni una línea de la app se
   ejecuta, no salta ningún error visible, y la pantalla se queda en
   "Cargando…" para siempre. Ahora la carga es dinámica y prueba primero
   `./vendor/supabase.js`; el CDN es solo el respaldo.
2. **Y un seguro por si acaso** (`theme-boot.js`): si a los ocho
   segundos sigue la pantalla de arranque, es que `app.js` nunca llegó a
   correr — así que lo dice y ofrece reintentar, en vez de dejarte
   mirando un "Cargando…" eterno.
3. **Al hacer dinámico ese import, dejó de registrarse el service
   worker.** El registro esperaba al evento `load`, pero con un `await`
   de nivel superior ese evento **ya había disparado** cuando se añadía
   el listener — y un listener de `load` añadido tarde no se ejecuta
   nunca. Sin un solo error en consola se iban el arranque instantáneo y
   el modo sin conexión. Se arregló mirando `document.readyState`.

Hay una comprobación que recorre todo esto sola (`auditar-pwa.mjs` en el
scratchpad): el manifest, lo que mira el iPhone al instalarla, el
service worker, la carga **sin servidor levantado**, y que el seguro de
los ocho segundos salta.

## Seguridad — auditoría con ataque real

No es una lista de buenas intenciones: se atacó la app de verdad. El
guion está en el historial de esta rama y lo que hace es meter payloads
en **todos** los campos de texto que acaban pintados (nombres de
hábitos, comidas, asignaturas, notas, medicamentos, categorías…), abrir
la app en Chromium con una clave de IA de mentira guardada, y medir tres
cosas: si algo se ejecuta, si sale alguna petición a un dominio externo,
y si la clave se puede leer.

### Lo que NO se pudo romper

- **XSS clásico**: cero. Todo el texto de usuario pasa por `esc()` antes
  de llegar al HTML. Se probaron `<img onerror>`, `<svg onload>`,
  `</span><script>` y payloads de atributo con `onmouseover`, y se
  simularon los `mouseover` sobre cada fila. Ninguno ejecutó nada.
- **RLS de Supabase**: las 21 tablas tienen política, todas con
  `auth.uid() = user_id`, todas con `user_id not null` y
  `default auth.uid()`. No hay `using (true)`, ni `to anon`, ni
  `security definer`.
- **Llavero de iOS**: `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` —
  el nivel correcto, y sin copia a iCloud.

### Lo que SÍ se rompió, y cómo está arreglado

**1. Inyección de CSS → fuga de datos a un dominio externo** *(era
explotable de verdad; la petición salía)*

El color de una asignatura se metía en un atributo `style` pasando por
`esc()`. Pero `esc()` escapa `< > & " '` — **no el punto y coma**. Un
color como `#fff;background-image:url('http://malo/x')` seguía siendo
CSS válido, y el navegador pedía esa imagen. Con CSS se puede sacar
información fuera (selectores de atributo que solo cargan la imagen si
un campo empieza por cierta letra), así que no era cosmético.

Arreglo: a un atributo `style` **no se le escapa, se le valida**.
`colorSeguro()` solo deja pasar `#rrggbb`; cualquier otra cosa cae al
color por defecto.

**2. Sin Content-Security-Policy**

Nada limitaba lo que la página podía cargar o a dónde podía conectarse.
Ahora hay una CSP en el `<head>`, y **sin `'unsafe-inline'` para
scripts**, que es la mitad que importa: un `<script>` inyectado no se
ejecuta aunque llegue al HTML. El único script en línea que había (el
que aplica el fondo antes de pintar) se sacó a `theme-boot.js` para
poder prohibirlos del todo.

`img-src 'self'` es lo que habría bloqueado la fuga del punto 1 aunque
la inyección siguiera ahí. Verificado: tras el arreglo, la petición al
dominio externo ya no aparece.

`style-src` sí lleva `'unsafe-inline'`, porque la app pone estilos en
línea por todas partes. Es una concesión consciente y por eso los
colores se validan con lista blanca en vez de confiar en la política.

**3. Dependencia del CDN sin anclar**

`@supabase/supabase-js@2` es un **rango**: el CDN sirve la última 2.x
que haya en cada momento. El día que alguien publique una versión con
código malicioso —o le roben la cuenta a quien publica— ese código se
ejecuta aquí con acceso a la sesión y a `localStorage`, sin que nadie
toque este repositorio. Ahora está anclado a `2.58.0`.

Lo ideal es no depender del CDN. En tu Mac:

```bash
mkdir -p web/vendor
curl -o web/vendor/supabase.js \
  "https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.58.0/+esm"
# y cambia el import de app.js por "./vendor/supabase.js"
```

Desde el entorno donde se escribió esto el proxy bloquea la descarga.

**4. Las claves de IA viajaban dentro de la app**

Estaban en `Info.plist` vía `Secrets.xcconfig`. Todo lo que hay en
`Info.plist` se lee **descomprimiendo la app**: no hay que saltarse
nada, se abre el archivo y ahí está en texto plano. Se han quitado; la
clave se escribe en Ajustes y vive en el Llavero (`AIKeyStore`).

**5. Contraseña de 6 caracteres**

Subida a 10, con rechazo de las más usadas y de las que contienen tu
propio correo. **Sin** reglas de "una mayúscula y un símbolo": esas
empujan a poner `Contraseña1!`, que es de las primeras que prueba
cualquier ataque, mientras que la longitud sí multiplica el tiempo que
cuesta romperla.

**6. El Llavero fallaba en silencio**

Se ignoraba el resultado de `SecItemAdd`, así que la app decía
"Guardada ✓" sobre una clave que podía no existir. Ahora devuelve si se
guardó y Ajustes lo dice si falla.

**7. Sesión eterna en dispositivo compartido**

En el iPad del colegio la sesión vivía en `localStorage`: sobrevive a
cerrar la pestaña, al navegador y al reinicio. Quien lo cogiera después
entraba en tu cuenta sin saber tu contraseña. Ahora el login tiene
**"Este no es mi dispositivo"**: la sesión —y la clave de IA— van a
`sessionStorage` y mueren al cerrar la pestaña. Nadie se acuerda de
darle a "cerrar sesión" cuando suena el timbre.

Además, cerrar sesión ahora borra también la clave de IA: si se quedara,
la siguiente persona que entrase con SU cuenta seguiría gastando la de
quien la dejó puesta.

### Lo que sigue siendo un riesgo aceptado, y por qué

- **La clave de IA se puede leer desde el navegador.** Quien tenga tu
  equipo desbloqueado la ve desde las herramientas de desarrollo. No
  tiene arreglo sin un servidor propio que haga de intermediario, que es
  un proyecto aparte. La pantalla lo dice en vez de disimularlo, y en
  dispositivo compartido la clave ya no sobrevive al cierre.
- **La clave pública de Supabase es pública.** Es su diseño: lo que
  protege los datos es RLS, no que esa clave sea secreta.
- **`style-src 'unsafe-inline'`**: ver punto 2.

### Cabeceras para el Synology

Tres protecciones solo funcionan como cabecera HTTP, no en el HTML:
antiframe (clickjacking), HSTS y `nosniff`. Están en
**`web/seguridad-cabeceras.conf`** con las instrucciones de dónde
pegarlas en DSM.

## Segunda ronda de seguridad — registro, cuentas y cuota

La primera ronda cerró lo que un atacante podía hacer **desde fuera**
(inyecciones, robo de la clave de IA, clickjacking). Esta cierra las tres
cosas que quedaban, que son las que importan cuando la app vive en una
página web abierta a internet.

### 1. Quién puede registrarse — y esto responde a lo de Android

**Sí, la app va conectada a un servidor, y ese servidor ya existe: es
Supabase.** No hace falta montar nada aparte. La diferencia es que la
decisión de quién entra no se toma en la app, se toma en la base de
datos — y eso vale igual para el iPhone, para Android y para el
navegador, porque los tres hablan con el mismo sitio.

Por qué no puede estar en la app: cualquiera abre las herramientas del
navegador (o descompila el APK) y se salta la comprobación en diez
segundos. En el servidor no hay nada que saltarse.

Tres modos, y se cambian con una línea en el SQL Editor de Supabase:

```sql
update public.signup_control set mode = 'abierto';     -- cualquiera
update public.signup_control set mode = 'invitacion';  -- solo los de la lista
update public.signup_control set mode = 'cerrado';     -- nadie más
```

`'cerrado'` es el botón de pánico: si alguien se pone a crear cuentas en
masa para llenarte la cuota, lo paras en cinco segundos y sin tocar ni
una línea de código.

En modo invitación, la lista se rellena así:

```sql
-- una persona concreta
insert into public.allowed_signups (email, note)
values ('amigo@correo.com', 'Clase de 1º');

-- un código para treinta, que caduca en una semana
insert into public.allowed_signups (code, max_uses, expires_at, note)
values ('HABITIUM-2026', 30, now() + interval '7 days', 'Clase entera');
```

Quien lo hace cumplir es `habitium_check_signup`, un trigger sobre
`auth.users` que se ejecuta **dentro** de la transacción que crea al
usuario: si dice que no, el usuario no llega a existir. Las apps (web e
iOS) mandan el código como metadato del registro y enseñan un mensaje
decente, pero eso es cortesía: la que decide es la base de datos.

Un detalle deliberado: la función `signup_mode()`, que es la única que
la app puede llamar sin cuenta, **solo dice el modo**. Nunca confirma si
un correo concreto está invitado ni si ya tiene cuenta. Si lo hiciera,
Habitium se convertiría en una máquina de averiguar qué correos existen.

### 2. Verificación en dos pasos (lo que evita que te roben la cuenta)

RLS impide que una cuenta vea los datos de otra, y eso ya estaba. Lo que
RLS **no** puede impedir es que alguien entre *siendo tú*: si averigua
tu contraseña —normalmente porque la reutilizabas en otro sitio que tuvo
una filtración— para el servidor es una sesión legítima.

Ahora está en **Ajustes → Seguridad**, en los dos sitios:

- **Web**: sale un QR y se escanea. El QR lo dibuja Supabase (viene como
  SVG dentro de un `data:`), así que **no hay que cargar ninguna
  librería de fuera** — y por tanto la Content-Security-Policy no se
  toca. Eso no es casualidad, es por lo que se eligió ese camino.
- **iPhone**: no hay QR, hay un botón que abre tu app de códigos
  directamente con el enlace `otpauth://`. En un móvil un QR habría que
  escanearlo con *otro* aparato; el enlace se abre de un toque.

El alta va en dos tiempos (primero el secreto, después confirmarlo con
un código) a propósito. Si se activara de golpe y la app de códigos no
lo hubiera guardado bien, te quedarías fuera de tu propia cuenta sin
forma de volver a entrar.

Al entrar, la sesión se queda **a medias** hasta que entra el código:
`SupabaseAuthManager.State.needsSecondFactor` en iOS, `continuarSesion()`
en la web. Los dos comprueban **antes** de pintar, no después, para que
no se vea ni un dato de refilón.

### 3. Que una cuenta no pueda reventar la base de datos

Esta era la brecha de verdad, y no se ve leyendo el código de la app:
RLS impide que leas datos ajenos, pero no impide que metas basura en los
**tuyos**. Con la clave pública (que es pública a propósito) y una cuenta
creada, un script podía subir un campo `nombre` de 50 MB, o diez
millones de filas, y dejar el proyecto sin cuota para todos.

Dos cerrojos, los dos en el servidor:

- **Tamaño por campo.** Un `CHECK` de longitud en los ~40 campos de
  texto. Los límites se aplican por *nombre* de columna, así que una
  tabla nueva con un `name` hereda el límite sin acordarse de nada.
- **Filas por cuenta y tabla.** Un trigger `limite_de_filas` con un
  techo generoso (50.000 comidas son más de treinta años apuntando cinco
  al día). El truco está en cómo cuenta: `count(*)` recorrería la tabla
  entera en cada INSERT, así que usa un subselect con `LIMIT` y Postgres
  para de contar en cuanto llega al techo — coste constante.

Y de propina: `anon` (el visitante sin cuenta) pierde el permiso de
escritura sobre todas las tablas, y nadie puede crear tablas nuevas en
`public`. Sin eso último, una cuenta cualquiera podía crear una tabla
**sin RLS** y usar tu base de datos como almacén gratis.

### 4. Lo pequeño que también cuenta

- **Freno a los intentos.** Tres fallos gratis y después 5s, 15s, 45s,
  2min, 5min. No para al que ataca el servidor desde fuera (para eso está
  el límite de Supabase) sino al caso realista: alguien con tu móvil en la
  mano. Media hora sin fallar borra el castigo.
- **Nunca se dice si un correo existe.** Ni al iniciar sesión ("el correo
  o la contraseña no son correctos", sin decir cuál) ni al recuperarla
  ("si hay una cuenta con ese correo, te llegará un enlace").
- **Cierre por inactividad** en dispositivo compartido: 20 minutos sin
  tocar nada y fuera. El iPad del instituto era el caso que faltaba.
- **Errores en cristiano.** El trigger del registro hace que Supabase
  conteste "Database error saving new user", que no le dice nada a nadie.
  `web/seguridad.js` y `friendlyMessage(for:)` lo traducen.

### Cómo comprobar que todo está puesto

Dos cosas distintas, y conviene no confundirlas:

**En tu proyecto de verdad** — `supabase/comprobar-seguridad.sql` → SQL
Editor → Run. No cambia nada: mira y contesta con ✓ o ✗. La comprobación
8 es la que de verdad importa: se hace pasar por un usuario inventado e
intenta leerlo todo, y si RLS funciona devuelve cero en todas las tablas.

**En una base de usar y tirar** — `supabase/pruebas/` levanta un Postgres
local, le aplica `schema.sql` tal cual y lo **ataca**: 28 intentos de
leer datos ajenos, robar filas cambiándoles el dueño, auto-invitarse,
inundar la base y colarse en el registro. Instrucciones en
`supabase/pruebas/LEEME.md`. Todo esto ya se ejecutó contra un Postgres
16 real antes de subirlo: **28 de 28**, y de paso salieron dos fallos que
leyendo el SQL no se veían — una subconsulta dentro de un `CHECK` (que
Postgres no admite y habría reventado al aplicar el esquema) y tres
pruebas que daban aprobados falsos porque corrían sobre tablas vacías.

Y del lado del navegador: `node --test web/*.test.mjs` (64 pruebas, 28 de
ellas en `web/seguridad.test.mjs`).

## El aspecto (la capa del final de `web/styles.css`)

Va al final del archivo a propósito: **redefine** lo de arriba sin
tocarlo, así que todo lo anterior sigue funcionando y la capa entera se
puede borrar si algún día deja de gustar.

De dónde sale: de una referencia de Notion — oscuro, portada de color
arriba, bandas de sección, esquinas redondeadas, etiquetas de colores.
Lo que se hizo distinto, y por qué:

- **Profundidad de verdad.** En oscuro lo que separa lo barato de lo caro
  no es la sombra (no se ve), es una línea de luz de 1px en el canto
  superior de cada superficie — `--luz`. Imita cómo la luz pega en un
  borde. Sin ella una app oscura es una mancha plana. En claro esa misma
  variable sube al 55 %; en oscuro baja al 6 %, porque al 55 % sería un
  subrayado blanco.
- **La portada se mueve.** Notion pone una foto; aquí es un degradado que
  gira en 18 segundos y que toma **tu** color. Cero bytes que descargar,
  y cambia cuando cambias el acento.
- **Números enormes.** Lo que se mira es la cifra, no la etiqueta:
  redondeada, apretada (`letter-spacing: -0.035em`) y con cifras de ancho
  fijo para que no baile al actualizarse.
- **Radio de 16 a 22.** Es el ajuste que más cambia la sensación de
  "herramienta" a "app que apetece abrir".
- **Inicio en bento**: tarjetas de tamaños distintos en pantalla ancha.
  Una rejilla toda igual se lee como una tabla. En móvil sigue siendo una
  columna, que es lo cómodo con una mano.
- **Oscuro por defecto**, con los seis fondos intactos por si se prefiere
  otro.

### Comodidad, que era la otra mitad de lo pedido

- Nada pulsable por debajo de **44 px** de alto: es la medida por debajo
  de la cual el pulgar empieza a fallar.
- **Botón flotante en móvil** abajo a la derecha, donde llega el pulgar
  sin recolocar la mano. Lo que hace cambia según la pantalla: en
  Nutrición abre el campo de comida, en Estudios el de nota. El "+" de la
  cabecera obliga a estirarse hasta arriba en un móvil grande.
- **La cabecera se reorganiza en móvil**: los controles suben a la
  esquina de la portada y el saludo se queda con el ancho entero. Sin eso
  "Buenas tardes, Álvaro" y la píldora de nivel se peleaban y el título
  salía en tres líneas.
- Tipografía redondeada donde el sistema la tenga (SF Pro Rounded en
  iPhone y Mac) y la de siempre si no. **No se descarga ninguna fuente**:
  esta app presume de funcionar sin conexión y una fuente remota la
  dejaría a medio pintar.

## Rutinas encadenadas y avisos

El caso que las pide, tal cual: *"a las 7:15 me levanto, luego me ducho,
luego me lavo los dientes, luego desayunar"*. Eso no es una lista de
tareas ni cinco alarmas sueltas: es **una** cosa, con orden y con ritmo.

### La decisión de diseño, que no es obvia

Se guarda **una hora de inicio + una duración por paso**, nunca una hora
por paso. Las dos alternativas sueltas fallan:

- **Hora fija en cada paso.** El día que te levantas diez minutos tarde,
  los cuatro avisos van desfasados y acabas silenciándolos. Y el día que
  te duchas rápido, esperas mirando el móvil.
- **Encadenado puro** (cada paso arranca al marcar el anterior). El
  PRIMER aviso no suena nunca: no hay nada que marcar antes de él.

Con inicio + duraciones se hacen las dos cosas a la vez. La regla, en una
frase: **el reloj lo pone el último paso marcado.** Los pasos hechos
enseñan la hora real a la que se marcaron; los que quedan se encadenan
desde ahí. Si te duchas en cinco minutos, el aviso de los dientes se
adelanta cinco minutos. Si te quedas dormido, todo se desplaza contigo en
vez de gritarte. La fila lo dice: "7:37 · recalculado".

El cálculo está en `web/routines.js` y en `RoutineSchedule.swift`. Son
dos copias a propósito —una en JS y otra en Swift— porque la misma cuenta
tiene que ver lo mismo en los dos sitios; los dos juegos de pruebas usan
los mismos casos.

### Los avisos: dónde funcionan de verdad y dónde no

Aquí el iPhone gana a la web, y por mucho. Conviene saberlo antes de
fiarse:

| | iPhone (app nativa) | Web / Android (PWA) |
|---|---|---|
| App cerrada | ✅ suenan | ❌ no |
| Móvil bloqueado | ✅ suenan | ✅ solo si la app sigue abierta de fondo |
| Programación | 3 días por adelantado | mientras la pestaña viva |

**Por qué.** Una página web no puede programar una notificación para
dentro de tres horas y desentenderse: la API que hacía justo eso
("Notification Triggers") se probó en Chrome y se retiró, y no está en
ningún navegador. Las push sí funcionan con la app cerrada, pero
necesitan un servidor propio empujándolas (claves VAPID, un proceso
escuchando) — Supabase solo no basta, y eso es otro proyecto.

Así que `web/avisos.js` hace el máximo que se puede sin servidor, y la
pantalla lo dice en vez de disimularlo: los avisos saltan mientras
Habitium esté abierta, y al volver se te recuerda **una sola vez** el que
se te acaba de pasar (solo el último, y solo si fue hace menos de diez
minutos — soltar cuatro notificaciones de golpe al abrir la app por la
tarde es la forma más rápida de que alguien las desactive para siempre).

En iOS son `UNCalendarNotificationTrigger` de verdad. Dos detalles que
tiene `RoutineNotifications.swift`:

- Se programan **3 días por adelantado**, no solo hoy: si solo fuera hoy
  y no abrieras la app por la noche, mañana no sonaría nada. Pero no más,
  porque iOS admite 64 notificaciones pendientes por app y **tira las que
  sobran sin avisar**.
- Van con `threadIdentifier`, así que las cuatro de la mañana se agrupan
  en una sola pila en la pantalla de bloqueo. Cuatro notificaciones
  sueltas a las siete de la mañana son cuatro interrupciones; una pila
  con cuatro dentro es una.

### Detalles que parecen tonterías y no lo son

- **El fin de semana no rompe la racha** de una rutina de L-V. Los días
  que no toca se saltan, no cuentan en contra. Castigarte el sábado por
  una rutina de días de colegio es el fallo que tienen la mitad de las
  apps de hábitos.
- **Hoy a medias tampoco la rompe**: si aún no la has terminado pero el
  día no ha acabado, la racha es la de ayer.
- **"Ahora" no es "el siguiente".** El primer paso sin marcar de la
  rutina de noche también lo es a las dos de la tarde; la etiqueta
  "ahora" solo sale si el paso toca dentro de ±15 minutos. Esto se vio
  mirando la pantalla, no leyendo el código.
- **Un atraso de horas no es un atraso.** Antes ponía "vas 392 min
  tarde", que hacía que la tarjeta pareciera rota. Pasadas dos horas dice
  "Hoy no ha salido" o "Se quedó en 2 de 4".
- **El XP se da al terminar la rutina entera**, nunca paso a paso. Si
  cada paso puntuara, la forma más rápida de subir de nivel sería crear
  una rutina de veinte pasos tontos.
- **El id de cada aviso no lleva la hora.** Si la llevara, cada recálculo
  crearía un aviso nuevo en vez de reemplazar el anterior, y acabarías
  con cinco del mismo paso.

38 pruebas en `web/routines.test.mjs`.

## Nutrición: el objetivo lo decide la IA (pero no del todo)

Tu objetivo diario ya no sale de una tabla genérica. Al entrar por
primera vez, un cuestionario de siete preguntas y la IA calcula tus
calorías y macros. **Sin clave de IA la sección no se abre**: es una
decisión dura a propósito — media sección funcionando, con el objetivo
puesto a ojo, no es lo que se quería construir.

También: fotos de la comida analizadas por la IA, y un botón de "¿qué
como ahora?" que mira lo que llevas hoy y lo que te queda.

### El cerrojo, que es lo que de verdad importa

Un modelo de lenguaje puede devolver 900 kcal. Por un error de formato,
porque escribiste algo raro en el cuestionario, o porque le pediste
"quiero adelgazar rápido". Si la app se traga ese número y te lo pone
como objetivo, **la app está empujando a un chaval de 16 años a comer la
mitad de lo que su cuerpo necesita para seguir funcionando**.

Así que el reparto es:

- **La IA decide**: el reparto de macros, el ritmo, los consejos, el
  tono, y los matices que una fórmula no puede tener en cuenta.
- **La fórmula acota**: se calcula el metabolismo basal con Mifflin-St
  Jeor y el gasto diario, y la propuesta de la IA tiene que caer en un
  rango razonable alrededor de eso.

Los límites, en `nutricion-ia.js`:

| Qué | Límite | Por qué |
|---|---|---|
| Calorías | nunca por debajo del basal | es lo que gasta el cuerpo tumbado sin hacer nada |
| Calorías | nunca más del doble del gasto | |
| Proteína | 0,8 – 3 g/kg | por debajo no se mantiene músculo; por encima no aporta |
| Grasa | mínimo 15% de las calorías | hace que funcionen las hormonas, y es la primera que todo el mundo recorta |
| Macros | tienen que sumar las calorías | si no, se recalculan los carbohidratos |

Y **las correcciones se enseñan**. Cambiar el número a escondidas sería
peor que no cambiarlo: la app estaría mintiendo sobre de dónde sale su
propio objetivo.

Hay una segunda parte, que salió de mirar la pantalla y no el código:
cuando el cerrojo ha tenido que corregir, **la explicación y el consejo
de la IA tampoco se enseñan**. La explicación describía un objetivo de
900 kcal mientras arriba ponía 1718 — la app contradiciéndose a sí
misma. Y el consejo, en verde y destacado, era *"No comas después de las
seis"*, dicho por el mismo modelo que acababa de proponer una dieta de
hambre. Eso no es un consejo que Habitium deba dar con su propia voz.

### Si la IA se cae

El objetivo se calcula igual, con la fórmula, y la tarjeta lo dice. La
sección no se queda bloqueada por un error de red: la referencia se
calcula SIEMPRE antes de llamar a la IA, no después.

### Dónde va cada cosa

- `web/ia.js` — el cliente de OpenAI/Anthropic. La clave va del navegador
  al proveedor directamente, sin pasar por ningún servidor nuestro. Las
  fotos se encogen a 1024 px antes de mandarlas: una foto de iPhone son
  4 MB y se paga por píxel, y a ese tamaño la IA reconoce un plato
  exactamente igual.
- `web/nutricion-ia.js` — el cuestionario, la fórmula y el cerrojo. Todo
  funciones puras, 25 pruebas.
- Los datos del cuestionario (peso, edad, sexo) se quedan en este
  navegador y **no** suben a la nube: lo que se sincroniza es el
  resultado, no tu ficha médica.

### Un fallo que costó encontrar, y la lección

Al terminar el cuestionario, el plan no aparecía: el cuestionario volvía
a salir encima. `loadNutrition` es `async` y se estaba ejecutando **tres
veces a la vez** — guardar el objetivo dispara `store.onChange(render)`
mientras `calcularObjetivo` va por la mitad. Cada copia leía el estado en
un instante distinto, y el que terminaba el último ganaba, que no es el
que empezó el último. Encima, el pintado *mutaba* el estado
(`if (!quiz.activo) empezarQuiz(...)`), así que un pintado tardío
reabría el cuestionario que ya se había cerrado.

Dos arreglos: un contador de generación (quien vuelve de sus `await` y ve
que ya no es el último, se calla) y que el pintado **deduzca** si toca
cuestionario en vez de guardarlo en una bandera que compite con los
renders.

## Finanzas: un plan de ahorro con las cuentas hechas

Al entrar por primera vez, un cuestionario: cuánto tienes, cuánto te
entra, cuánto se te va, cuánto quieres ahorrar y para cuándo. Con eso
monta el plan.

### Aquí manda la aritmética, no la IA

En Nutrición la IA propone y la fórmula acota. Aquí es más simple: **las
cuentas las hace la aritmética y la IA solo comenta.** Un plan de ahorro
es restar y dividir — no hay nada que opinar sobre si 500 € al mes caben
en 20 € de margen.

Y cuando no caben, la app **no lo maquilla**:

> Para llegar a 3000 € en 6 meses harían falta 500 € al mes, y solo te
> sobran 20 €.
> Con tu ritmo real llegarías en 150 meses. Si quieres mantener el plazo,
> hay que gastar 480 € menos al mes.

Una app que te dice "sí, puedes" cuando no puedes no te está ayudando: te
está preparando para fallar en enero y dejarlo. Cuando el plan no sale,
la barra deja de ser verde y **el texto de la IA no se enseña** — igual
que en Nutrición cuando el cerrojo corrige. Un "vas muy bien" encima de
un plan que no cuadra es peor que no decir nada.

Tres casos que la aritmética sola resuelve y que una IA fallaría:

- **Gastas más de lo que ingresas.** No se calcula ningún plazo: dividir
  entre un margen negativo daría "llegas en −12 meses". Primero se dice
  que hay un agujero, y no se dan consejos de ahorro hasta taparlo.
- **El plan sale justo** (la cuota se come el 90% del margen). Sale, pero
  avisa: cualquier imprevisto lo tumba.
- **Ya tienes lo que querías.** No puede salir "inviable" algo que ya
  está hecho.

### "En qué se te va"

El gasto del mes por categorías, ordenado de más a menos y con el
porcentaje. Y el aviso de "te vas a pasar" se decide **por la
proyección, no por lo gastado**: el día 10 con 100 € de 250 vas bien por
lo gastado, pero a ese ritmo acabas el mes en 300. Avisarte el día 28 de
que te has pasado no sirve de nada.

### Apuntar un gasto escribiéndolo

**Finanzas → "Rápido: 4,20 bocadillo"**. Coge el primer número (así
`4,20 bocadillo para 2` son 4,20 € y no 2) y adivina la categoría por la
palabra. Funciona **sin IA y sin internet** a propósito: es el mismo
camino que usa el atajo de Apple Pay, y en la cola del súper con mala
cobertura un atajo que depende de un servidor falla justo cuando hace
falta. La IA, si está, solo afina la categoría *después* — el gasto ya
está guardado.

## Apple Pay: lo que se puede y lo que no

**Ninguna app de terceros puede leer tus pagos de Apple Pay.** No hay
API. El importe y el comercio no salen de Wallet, ni en iOS ni en
Android. La automatización de Atajos con disparador "Transacción" sí da
el importe, pero solo con Apple Card y Apple Cash, que en España no
existen.

Lo que **sí** funciona: cuando pagas con el doble clic del botón lateral,
iOS abre Wallet y al terminar la cierra — y Atajos sabe dispararse
**al cerrarse una app**. Así que la automatización no adivina el importe,
pero te lo pregunta **en el momento exacto en que acabas de pagar**, que
es cuando te acuerdas.

Los pasos están en **[`docs/apple-pay-atajo.md`](docs/apple-pay-atajo.md)**
(cinco minutos, una vez). Habitium expone tres acciones a Atajos y a
Siri, en `Core/Intents/HabitiumIntents.swift`:

- **Apuntar un gasto** — acepta "4,20 bocadillo" y lo guarda sin abrir la
  app.
- **Marcar el siguiente paso de mi rutina** — *"Oye Siri, siguiente paso
  en Habitium"* mientras te duchas. Marca el paso que toca y recalcula
  los avisos de los que quedan.
- **¿Cuánto me queda este mes?**

`ExpenseParser.swift` y `interpretarGasto` en JavaScript son dos copias
de la misma lógica **con los mismos casos de prueba**: escribir "4,20
bocadillo" en el iPhone y en la web tiene que dar el mismo gasto.

## Agenda: el calendario del mes

Un calendario que solo enseña los días es un adorno. Este pone un punto
por cada cosa que tienes ese día —🟢 tareas, 🔵 eventos, 🩷 exámenes— y al
pulsar un día abre lo que hay debajo. Los exámenes salen de Estudios, así
que la agenda y el curso no van por separado.

Detalle de calendario que se equivoca la mitad de las veces: la semana
empieza en **lunes**. `getDay()` devuelve domingo = 0, así que el
desplazamiento es `(primerDia.getDay() + 6) % 7`. Sin eso, el calendario
sale corrido un día.

### El móvil, que es donde se usa esto

Todas las pantallas nuevas se habían mirado a 1180 px. A 390 px —que es
un iPhone— salieron dos cosas:

- **La tarjeta de "Disponible" se salía por la derecha.** `.grid-3` era
  `repeat(3, 1fr)`, y `1fr` es `minmax(auto, 1fr)`: ese *auto* impide
  que la columna baje del ancho de su contenido, así que las tres
  tarjetas sumaban más que la pantalla. Con `minmax(0, 1fr)` se encogen
  de verdad.
- **Estudios hacía scroll horizontal de la página entera.** La tabla de
  notas tiene `min-width: 430px` y su contenedor `overflow-x: auto` —
  correcto sobre el papel. Pero los hijos de `.view` son grid items, y
  un grid item tiene `min-width: auto`: no puede encogerse por debajo
  de su contenido. Así que la tabla empujaba su tarjeta a 472 px, y con
  ella la vista, la columna y el documento. El `overflow-x` no servía
  de nada mientras el contenedor no pudiera encogerse.

Ese segundo venía de antes de esta tanda. Queda una comprobación que lo
caza sola (`medir-desborde.mjs` en el scratchpad): recorre las diez
pantallas a 390 px y avisa de cualquier elemento que se salga —
ignorando, eso sí, lo que se sale *dentro de un contenedor con scroll
propio*, que es justo lo que hace una tabla ancha bien resuelta.

## Un fallo de CSS que se llevó por delante tres pantallas

Todo el CSS nuevo de esta tanda usaba el atajo `font`:

```css
.goal-now { font: 700 30px/1 inherit; }   /* ← INVÁLIDO */
```

`inherit` **no vale como familia dentro del atajo `font`**, así que el
navegador descarta la declaración **entera** — no solo la familia. El
resultado: siete reglas silenciosamente muertas y números que debían
medir 30px saliendo a 15px, con el peso por defecto.

No se vio leyendo el código ni con las pruebas en verde: se vio midiendo
los estilos computados en el navegador. Ahora van como propiedades
sueltas, que heredan la familia solas.

De paso salió otro: `.card h2` (especificidad 0,1,1) le ganaba a
`.quiz-question` (0,1,0), así que la pregunta del cuestionario salía a
11px **y en mayúsculas**, como el titulillo de una tarjeta.

## Estudios — asignaturas, notas y asistencia

El módulo que cierra la idea original del sistema de niveles: *"cada día
que inicies sesión, luego que saques buenas notas, etc., vas a subir de
nivel"*. La parte de las notas no existía hasta ahora.

Tres tablas nuevas (`subjects`, `grades`, `study_events`) y un motor
probado aparte en `web/study.js` (13 pruebas en `web/study.test.mjs`).

**La cuenta que casi todo el mundo hace mal.** La media ponderada se
divide entre el peso REALMENTE evaluado, no entre 100. A mitad de curso
con un 7 y un 8 que pesan 20 % cada uno, dividir entre 100 da un 3 —
"estás suspendiendo" — cuando en realidad llevas un 7,5 de lo corregido.
Es el error clásico de la hoja de cálculo y hay una prueba dedicada a
que no vuelva.

Otras dos decisiones:

- **`counts_for_average`** existe porque hay notas que aún no cuentan (un
  parcial a recuperar, un trabajo sin corregir). Meterlas a la fuerza
  daría un número falso; esconderlas te las haría olvidar.
- **La asistencia manda sobre la media.** Si te has pasado de faltas, la
  asignatura se marca en rojo aunque lleves un 9: la nota no te salva de
  perder la convocatoria.

XP: apuntar una nota da 10, sacar un 7 o más da 35, y dejar una
asignatura aprobada da 25 (una vez por asignatura y temporada). Apuntar
da poco a propósito — si diera lo mismo, lo rentable sería inventarse
pruebas en vez de estudiar.

## Tu propia clave de IA

Hasta ahora la clave solo podía venir de `Configuration/Secrets.xcconfig`,
o sea de quien compila la app. Cualquier otra persona que se la instalara
se quedaba sin análisis de comidas y sin forma de arreglarlo desde
dentro.

- **iPhone** — `Ajustes → Análisis de comidas por foto`. La clave se
  guarda en el **Llavero** (`AIKeyStore`), no en `UserDefaults`: este
  último es un plist en claro que viaja en cualquier copia de seguridad
  sin cifrar. La del xcconfig sigue valiendo como respaldo.
- **Web** — `Ajustes → Tu clave de IA`, en `localStorage`.

**No viaja a la nube, y es deliberado.** Una clave de API en una tabla de
Postgres acaba replicada en copias de seguridad y en cualquier volcado; si
alguien la saca, la factura la paga su dueño. El precio es que hay que
ponerla en cada dispositivo, y es el precio correcto. En la web, además,
"guardada en este navegador" significa que quien tenga el portátil
desbloqueado puede leerla desde las herramientas de desarrollo — la
pantalla lo dice en vez de disimularlo.

## Apple Watch (Ajustes → Apple Watch)

Un interruptor de sí/no que, al encenderlo, **pide de verdad** los
permisos de Salud y de notificaciones (`WatchHealthAccess`). Un "sí" que
no pide nada dejaría la función apagada sin avisar.

Por qué importa para la nutrición: la IA que mira la foto estima lo que
**comes**, pero no sabe nada de lo que **gastas**. Sin reloj, las
calorías gastadas salen de una fórmula con tu peso y tu edad — la media
de una persona que no eres tú. Con reloj son tus pulsaciones y tu
movimiento de hoy. Son las dos mitades de la misma cuenta.

Dos cosas que impone iOS y que la pantalla explica en vez de esconder:

1. **Solo se puede preguntar una vez.** Si dices que no, volver a pedirlo
   no hace nada, así que Ajustes enseña la ruta a mano (Ajustes → Salud →
   Acceso de apps → Habitium) en lugar de un botón que fingiría.
2. **iOS nunca confirma un permiso de LECTURA.** `authorizationStatus`
   solo es fiable para escribir; para leer devuelve siempre "no
   determinado", a propósito, para que una app no pueda deducir que
   tienes una condición médica por el hecho de que le niegues un dato.
   Por eso se comprueba de la única forma que funciona: pidiendo permiso
   y luego intentando leer.

⚠️ **Con una cuenta de Apple gratuita el entitlement de HealthKit no se
puede firmar.** Si al compilar salta un error de firma, quita las dos
líneas `com.apple.developer.healthkit` del target `Habitium` en
`project.yml`: la app funciona igual, solo que sin datos del reloj.

## Rediseño de Nutrición, Agenda y Finanzas

Las tres pantallas que quedaron fuera del rediseño anterior. Ahora usan el
mismo lenguaje que Inicio, Hábitos, Medicación y Progreso: tarjetas con
`CardHeader` + `IconBadge`, `ProgressBar`/`RingProgress` en vez de los
`ProgressView` del sistema, `EmptyHint` en los vacíos y entrada
escalonada con `.appearIn(n)`.

### Fuera `List`, dentro `ScrollView` + tarjetas

Nutrición y Finanzas iban en un `List` con cada tarjeta metida en una
fila y disimulada con `listRowInsets(EdgeInsets())` +
`listRowBackground(.clear)`. Eso es pelear contra el control en vez de
usarlo, y encima obligaba a `scrollContentBackground(.hidden)` para que
el fondo elegido se viera.

**Lo que cuesta:** las `swipeActions` solo existen dentro de `List`. Así
que eliminar pasa a ser **mantener pulsado** (`contextMenu`), que es lo
que ya hacían Hábitos y Medicación — antes la app tenía dos formas
distintas de borrar según la pantalla. Cada lista lo dice en letra
pequeña, porque un gesto que no se anuncia no existe.

### Decisiones concretas

- **Nutrición** — el anillo pasa a ser el protagonista, con las kcal que
  quedan contando desde 0 (`CountingInt`) y los tres macros en barras a
  su lado. La racha de registro sale de una línea suelta a su propia
  tarjeta: es lo que sostiene el hábito de apuntar, que es la parte que
  todo el mundo abandona la segunda semana.
- **Finanzas** — manda **lo que te queda**, no lo gastado: es la cifra
  con la que decides si te puedes permitir algo ahora. Los ingresos van
  en verde y los gastos en el color normal del texto — pintar cada gasto
  de rojo haría que un mes normal pareciera una alarma. Y "Editar
  presupuesto" y "Gastos fijos" salen del menú `…` de la barra, donde no
  los encontraba nadie, a una tarjeta al final de la pantalla.
- **Agenda** — la papelera de cada tarea desaparece: tres botones por
  fila (marcar, destacar, borrar) convertían la fila en un panel de
  control, y el de borrar estaba pegado al de destacar. La estrella solo
  se pinta cuando la tarea es foco del día, para que se sepa qué
  significa. En el calendario, "hoy" es un aro y el día elegido es un
  círculo lleno: con dos rellenos no se distinguía cuál estaba elegido.
- **Meta de ahorro** — dice lo que falta ("Te faltan 260 €") además del
  porcentaje. Un 52 % no es una cifra con la que puedas hacer nada.

## Progresión en la web (nivel, racha, retos y pase)

La web ya no es "la versión reducida": tiene el mismo sistema de niveles
que el iPhone, con los mismos números y las mismas claves, porque es
**una sola cuenta**. Quien use solo la web (Android, el iPad del colegio)
ve exactamente lo mismo.

| Archivo | Gemelo en iOS |
|---|---|
| `web/progression.js` | `ProgressionEngine` + `SeasonPass` + `DailyChallenges` |
| `web/player.js` | `ProgressionRepository` + `DailyChallengeService` |
| `web/progression.test.mjs` | `HabitiumTests/ProgressionEngineTests` |

Se prueba con `node --test web/progression.test.mjs` (23 pruebas, sin
instalar nada).

### Los tres puntos donde esto se rompe en silencio

**1. Los retos del día tienen que coincidir con los del iPhone.** Se
sortean con un generador sembrado con la fecha, así que hay que
reproducir el sorteo de Swift *exactamente*. El detalle que casi se cuela:
cuando solo hay una opción posible, Swift **igual consume un número** del
generador (su bucle es un `repeat…while`). Saltarse esa tirada —que es lo
natural— desviaría la secuencia a partir de ahí y cada dispositivo
mostraría retos distintos, sin ningún error visible. Comprobado cruzando
la versión JS con una transcripción independiente del Swift: **120/120
días coinciden**, y hay una prueba que fija el resultado de dos fechas
concretas para que no se mueva.

**2. Las claves anti-repetición llevan los identificadores en
MAYÚSCULAS.** En Swift, interpolar un UUID da mayúsculas; en JavaScript y
en Postgres son minúsculas. Si la web escribiera la clave en minúsculas,
`habit:a1b2…:2026-09-04` y `habit:A1B2…:2026-09-04` serían dos claves
distintas para el mismo hábito del mismo día: los dos dispositivos
premiarían por su cuenta y saldría XP duplicado. De ahí `idKey()` en
`app.js`.

**3. El total se recalcula desde los eventos, no se confía en el
contador.** `player_profiles` es una fila única con "gana el más
reciente", y para un contador eso pierde datos: si ganas XP en el móvil y
la web sube después un perfil suyo, el contador del móvil desaparece. Los
`xp_events` sí convergen (filas independientes con clave única en
Postgres), así que `player.reconcile()` vuelve a sumarlos antes de pintar.

### Un fallo real que encontró la prueba en navegador

Al arrancar, la web llama a `showApp()` **dos veces** (una por
`onAuthStateChange` y otra por `getSession`, que es como funciona
Supabase). Las dos carreras leían "el login de hoy aún no está premiado"
y las dos escribían: **20 XP en vez de 10**. Arreglado poniendo las tres
operaciones que escriben (`award`, `registerDailyLogin`, `reconcile`) en
una cola de una en una (`enSerie` en `player.js`).

Se encontró ejecutando la web de verdad en Chromium con un doble de
Supabase en memoria, no leyendo el código. La primera versión del doble
devolvía tablas vacías al hacer *pull*, lo que borraba los datos locales
y daba un falso 0 — el doble tuvo que guardar de verdad para que la
prueba dijera algo.

### Qué más trae

- **Registro de peso en la web** (`Nutrición`). Faltaba, y sin él el reto
  "Registra tu peso" era imposible para quien solo usa la web.
- **Color de acento elegible** en `Progreso`, desbloqueable por el pase,
  igual que en el iPhone. Redefine `--green`, que es el color principal
  de toda la web.
- **Movimiento**: entrada escalonada de tarjetas, anillos y barras que se
  llenan al aparecer, aviso de XP y celebración con confeti. Todo se
  desactiva entero con "Reducir movimiento".

## Movimiento en iOS (`Core/DesignSystem/Motion.swift`)

Dos reglas: nada dura más de medio segundo (una animación bonita la
primera vez es un peaje la número cincuenta, y esto se abre a diario), y
todo se salta si el iPhone tiene "Reducir movimiento" activado.

- `.appearIn(índice)` — entrada escalonada; el retardo se corta a la
  sexta tarjeta o la última parecería lentitud.
- `CountingInt` — números que cuentan desde 0. `.contentTransition(.numericText())`
  no vale aquí: anima el cambio de un número a otro, así que de 0 a 720
  daría un solo salto.
- `RingProgress` y `ProgressBar` se llenan al aparecer en vez de salir
  ya llenos.

## Fondo elegible (iPhone y web)

El color de fondo lo elige cada persona en **Ajustes → Fondo**. Seis
opciones, las mismas en las dos plataformas:

| | Pantalla | Tarjeta | Esquema |
|---|---|---|---|
| **Automático** | sigue al iPhone / al navegador | — | del sistema |
| **Claro** | `#F2F2F7` | `#FFFFFF` | claro |
| **Crema** | `#FBFAF7` | `#FFFFFF` | claro |
| **Vainilla** | `#FFF8E9` | `#FFFDF6` | claro |
| **Grafito** | `#17181C` | `#24262B` | oscuro |
| **Noche** | `#0B0D10` | `#16171C` | oscuro |

Por qué existe esto: al maquetar tres direcciones de diseño distintas
("neón oscuro", "pop", "editorial"), lo que de verdad cambiaba entre
ellas era el fondo. En vez de imponer una a todo el mundo, se elige. El
resto del diseño —los colores de cada área, los radios, los tamaños— no
cambia, así que sigue siendo la misma app y no seis.

**Dos reglas que no se pueden saltar al añadir un fondo nuevo** (hay
tests que las comprueban, `HabitiumTests/BackgroundThemeTests.swift`):

1. Fondo oscuro → la tarjeta se separa con un **borde tenue** y sin
   sombra. Una sombra negra sobre fondo negro no se ve, y sin nada que
   las separe la pantalla queda como una mancha plana.
2. Fondo claro → al revés: sombra y nada de borde.

Detalles de implementación que no son obvios:

- **iOS** — `BackgroundTheme` + `AppearanceStore` (`@Observable`, en
  `UserDefaults`). El `preferredColorScheme` se aplica **una sola vez**
  en `RootView`, y con eso acompañan el texto, la barra de pestañas y
  los menús. Las listas (`Nutrición`, `Finanzas`) necesitan además
  `.scrollContentBackground(.hidden)`, o pintan su gris del sistema
  encima y el fondo elegido no se ve en esas dos pantallas.
- **Web** — variables CSS bajo `[data-bg="…"]`. El bloque
  `@media (prefers-color-scheme: dark)` está acotado a
  `[data-bg="system"]`: sin eso, elegir "Claro" con el móvil en modo
  oscuro no serviría de nada porque el `@media` seguiría ganando. Un
  script mínimo en el `<head>` de `index.html` pone el atributo antes
  del primer pintado — es el único script en línea de la página, y es
  para evitar el fogonazo blanco de quien tenga "Noche".
- El fondo **no viaja por la sincronización**: es una preferencia de
  cada dispositivo, y es razonable querer el iPhone en oscuro y la web
  en claro. Los temas de *acento* del pase de temporada son otra cosa y
  siguen desbloqueándose por nivel; el fondo es gratis desde el minuto
  uno, porque condicionar la comodidad de leer a jugar al pase sería
  cobrarle la vista a quien solo quiere usar la app.

Lo que **no** se tiñe, a propósito: las hojas de meter datos (añadir
comida, gasto, tarea…) se quedan con el gris del sistema. Ahí lo que
importa es el formulario, no el color. Ajustes sí se tiñe, porque es la
pantalla donde estás eligiendo y ver el cambio bajo el dedo es media
explicación.

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
