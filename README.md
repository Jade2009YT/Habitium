# Habitium

Aplicación nativa para iOS enfocada en el cuidado personal integral: nutrición
(con IA), calendario/recordatorios, y finanzas personales — todo en un
dashboard unificado, con soporte para Widgets de iOS. Pensada para uso
personal y 100% local (sin backend, sin sincronización en la nube), pero con
una arquitectura limpia y modular que permite publicarla en la App Store más
adelante.

## Stack

- **UI**: Swift + SwiftUI
- **Arquitectura**: MVVM + Clean Architecture (Models → Repositories →
  UseCases → ViewModels → Views)
- **Persistencia**: SwiftData, 100% local, almacenado en un contenedor de
  App Group para que la app y los widgets compartan datos
- **Widgets**: WidgetKit, con 3 widgets (nutrición, finanzas, calendario)
  interactivos vía App Intents, para pantalla de inicio y pantalla de bloqueo
- **IA**: OpenAI (GPT-4o Vision) o Claude (Anthropic), seleccionable por el
  usuario, para analizar fotos/texto de comidas
- **Login**: Sign in with Apple — sin backend, sin contraseñas que proteger
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

1. Selecciona tu Team en **Signing & Capabilities** para los targets
   `Habitium` y `HabitiumWidgetsExtension`.
2. Confirma que el **App Group** `group.com.habitium.app` (o el que hayas
   puesto en `APP_GROUP_ID`) está habilitado en ambos targets — XcodeGen ya
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

## Inicio de sesión (Sign in with Apple)

Habitium pide iniciar sesión con Apple antes de mostrar la app
(`Core/Auth/`). Se eligió esto en vez de un sistema de email/contraseña a
medida porque, para lo que necesita esta app, resuelve todo sin montar ni
pagar ningún servidor:

- **Apple verifica la identidad** (Face ID/Touch ID + tu Apple ID) — no hay
  contraseñas ni emails que Habitium tenga que proteger o filtrar por error.
- **Cero coste, cero mantenimiento.** No hay backend que tú tengas que
  pagar, actualizar o asegurar.
- **No hace falta para que las compras funcionen en varios dispositivos** —
  eso ya lo resuelve StoreKit solo (ver la siguiente sección). Este login es
  puramente de identidad: guarda tu nombre/email (solo la primera vez que
  Apple te los cede) en `UserSettings`, y el identificador estable de Apple
  en el Keychain (`Core/Auth/KeychainStore.swift`), nunca en texto plano.
- **"Cerrar sesión"** (en Ajustes) no borra ningún dato — solo te vuelve a
  pedir el login. Todo tu contenido sigue en el dispositivo.
- Si revocas el permiso desde **Ajustes del iPhone → tu nombre → Sign in
  with Apple**, Habitium lo detecta en el siguiente arranque
  (`credentialState(forUserID:)`) y te saca la sesión automáticamente.

Requiere que actives la capability **Sign in with Apple** en el target
`Habitium` con tu Team — XcodeGen ya genera el entitlement
(`com.apple.developer.applesignin`), pero Xcode necesita tu cuenta de
desarrollador conectada para firmarlo.

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
│   └── WatchConnectivityBridge.swift # Sincroniza los 4 snapshots iPhone → Watch
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
│   ├── Models/                      # @Model de SwiftData (capa de datos)
│   ├── Repositories/                # Protocolo + implementación SwiftData
│   ├── UseCases/                    # Lógica de negocio (capa de dominio)
│   ├── Features/                    # Un folder por pestaña (MVVM)
│   │   ├── Auth/                     # LoginView, AppLockView
│   │   ├── Home/                     # Dashboard unificado
│   │   ├── Nutrition/                # FoodTrackerView + IA (cámara/galería/texto/código)
│   │   ├── Planner/                  # Calendario, tareas, notas
│   │   ├── Finance/                  # Ingresos/gastos, presupuesto
│   │   ├── Medication/                # Recordatorios y tomas de medicación
│   │   └── Settings/                 # Metas, cuenta, seguridad, IA, notificaciones, moneda
│   └── Resources/Assets.xcassets
├── HabitiumWidgets/                # Extensión de WidgetKit (iOS)
│   ├── HabitiumWidgetsBundle.swift  # @main WidgetBundle
│   ├── NutritionWidget.swift
│   ├── FinanceWidget.swift
│   ├── CalendarWidget.swift
│   └── MedicationWidget.swift
├── HabitiumWatch/                  # App de watchOS (v1, solo lectura)
│   ├── HabitiumWatchApp.swift       # @main
│   ├── WatchSummaryView.swift       # Única pantalla — resumen de las 4 áreas
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

## Apple Watch (v1 — solo lectura)

Solo Apple Watch: "cualquier reloj digital" no es viable con Swift/SwiftUI —
Garmin, Wear OS, etc. son sistemas operativos distintos, con SDKs propios;
sería un proyecto aparte por completo (igual que pasaba con Google Play).

Lo que hay montado en `HabitiumWatch/` (target watchOS independiente,
`project.yml`) y `SharedWatch/`:

- Una pantalla única y glanceable: calorías restantes, próxima toma de
  medicación, próximo evento, saldo disponible — el resumen de Inicio, pero
  en la muñeca.
- **Sincronización unidireccional iPhone → Watch** vía `WatchConnectivity`
  (`SharedWatch/WatchConnectivityBridge.swift`), no App Groups — el iPhone y
  el Watch son dispositivos físicos distintos con almacenamiento separado,
  así que un App Group no comparte nada entre ellos por sí solo. Cada vez
  que un repositorio escribe algo, además de refrescar los widgets, empuja
  los cuatro snapshots al reloj con `updateApplicationContext` ("el último
  gana", ideal para datos de un vistazo, no necesita que ninguna app esté
  en primer plano).

**Qué falta a propósito (v2, más delicado):**
- **Interactuar desde el reloj** (marcar una toma como hecha, completar una
  tarea) — necesita sincronización en las dos direcciones, con manejo de
  conflictos si ambos dispositivos cambian algo casi a la vez. Nada de eso
  está montado todavía.
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
- Sincronización opcional entre dispositivos propios (seguiría siendo
  100% tuyo, sin backend de terceros) — hoy cada instalación es independiente.

## Otros próximos pasos sugeridos

- Sustituir los placeholders de `AppIcon`/`AccentColor` por assets reales.
- Añadir Live Activities para el registro de comidas en curso.
- Exportar/importar datos (backup manual, ya que todo es local).
- Tests de UI con `XCUITest` para los flujos principales.
