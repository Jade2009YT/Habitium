# Meter Habitium en el iPhone

Lo que hay que saber antes de empezar, para que no te pille de sorpresa:

**Esta app no se ha compilado nunca.** Está escrita entera pero ningún
compilador la ha visto todavía. Lo normal la primera vez es que Xcode
saque una lista de errores. No es que esté rota: es que 116 archivos de
Swift escritos sin Xcode delante siempre tienen erratas, y salen todas de
golpe en cuanto le das al play. **Cópialas y pásamelas** — con el texto
del error se arreglan rápido; adivinando, no.

Cuenta con dos ratos: uno para que compile y otro para tenerla en el
móvil.

---

## Antes de nada: lo que una cuenta gratuita no te deja

Si no pagas los 99 € al año del programa de desarrolladores de Apple,
hay tres cosas del proyecto que **no se pueden firmar**:

| Qué | Para qué sirve en Habitium | Sin pagar |
|---|---|---|
| **App Groups** | Que el widget y el reloj vean tus datos | No |
| **HealthKit** | Leer del Apple Watch las calorías y los entrenos | No |
| **Iniciar sesión con Apple** | El botón de entrar con tu Apple ID | No |

No es un fallo del proyecto ni algo que se pueda rodear: Apple reserva
esos permisos a las cuentas de pago.

Así que hay dos caminos. **Empieza por el primero**, aunque acabes
pagando: si algo falla, quieres que falle por una cosa y no por cinco a
la vez.

- **Camino corto** — la app y nada más. Sin widget, sin reloj, sin Salud
  y entrando con correo y contraseña. Funciona todo lo demás: hábitos,
  rutinas, nutrición, finanzas, agenda, estudios, el buzón de ideas y la
  sincronización con Supabase. Gratis.
- **Camino largo** — todo, pagando el programa de desarrolladores.

---

# Camino corto

## 1. Instala lo que hace falta

**Xcode**, desde la App Store. Son unos 15 GB y tarda un rato largo.
Ábrelo una vez cuando acabe: pide instalar unos componentes adicionales,
dale que sí.

Luego, en la Terminal:

```bash
# Homebrew, si no lo tienes ya
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# XcodeGen, que es lo que construye el proyecto a partir de project.yml
brew install xcodegen
```

## 2. Baja el código

```bash
git clone https://github.com/Jade2009YT/Habitium.git
cd Habitium
git checkout claude/habitium-ios-app-lpvnh0
```

## 3. Pon tus datos de Supabase

```bash
cp Configuration/Secrets.example.xcconfig Configuration/Secrets.xcconfig
open -e Configuration/Secrets.xcconfig
```

Rellena las tres últimas líneas con lo de tu proyecto de Supabase
(**Settings → API**):

```
SUPABASE_URL_SCHEME = https
SUPABASE_URL_HOST = abcdefgh.supabase.co
SUPABASE_ANON_KEY = eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
```

Tres cosas:

- El host va **sin** `https://` delante. El fichero lo lleva en la línea
  de arriba, partido en dos, porque en un `.xcconfig` las dos barras de
  `//` empiezan un comentario y se comería media URL.
- Usa la clave **anon / public** (o `sb_publishable_`). La
  `service_role` nunca.
- Pon **las mismas** que en `web/config.js`. Eso es lo único que hace
  que el iPhone y la web compartan cuenta y datos: no hay nada más que
  conectar.

Ese archivo está en `.gitignore`: es tuyo y no se sube.

## 4. Quita lo que no se puede firmar gratis

Con una cuenta gratuita hay que sacar del proyecto el widget, el reloj y
los tres permisos de arriba. Esto lo hace de una vez:

```bash
./scripts/sin-cuenta-de-pago.sh
```

Te dice qué ha quitado y deja una copia de `project.yml` por si luego
pagas y lo quieres volver a poner. Si prefieres hacerlo a mano, el guion
está comentado paso a paso.

## 5. Ponle un identificador tuyo

El identificador de la app tiene que ser único en todo el mundo, y
`com.habitium.app` es el del proyecto: si alguien lo usó antes, Xcode se
queja. Cámbialo por uno tuyo en `project.yml`:

```yaml
PRODUCT_BUNDLE_IDENTIFIER: com.alvaro.habitium
```

(Tu nombre, tus apellidos, lo que sea, mientras no lo use nadie.)

## 6. Genera el proyecto y ábrelo

```bash
xcodegen generate
open Habitium.xcodeproj
```

Si `xcodegen` da error aquí, **para y mándamelo**: significa que
`project.yml` tiene algo mal y no hay nada que hacer en Xcode hasta
arreglarlo.

La primera vez que abre, Xcode se baja la librería de Supabase. Tarda un
par de minutos y abajo del todo pone lo que está haciendo. Espera a que
acabe antes de tocar nada.

## 7. Firma

Arriba a la izquierda, en la lista de archivos, pulsa en **Habitium**
(lo de más arriba del todo, con el icono azul). Se abre la configuración
del proyecto. Pestaña **Signing & Capabilities**:

1. Marca **Automatically manage signing**.
2. En **Team**, elige tu Apple ID. Si no aparece: **Add an Account…** y
   entra con el tuyo de siempre. No hace falta pagar nada para esto.

Xcode se crea solo un certificado de desarrollo. Si el identificador da
problemas, cámbialo aquí mismo y prueba otro.

## 8. Compila

`Cmd + B`.

**Aquí es donde va a salir la lista de errores.** Es lo esperado. Para
copiarlos:

1. En la barra de la izquierda, pulsa el triángulo de aviso (⚠️) para ver
   la lista entera.
2. Pulsa el primero, `Cmd + A` para seleccionarlos todos y `Cmd + C`.
3. Pégamelos tal cual.

No hace falta que los entiendas ni que los filtres. Cuantos más de golpe,
mejor: muchos son el mismo fallo repetido y se arreglan a la vez.

## 9. Al iPhone

Cuando compile sin errores:

1. Conecta el iPhone por cable. La primera vez, en el móvil sale
   «¿Confiar en este ordenador?» → **Confiar**, y el código.
2. En el iPhone: **Ajustes → Privacidad y seguridad → Modo de
   desarrollador** → activar. Se reinicia el móvil.
3. En Xcode, arriba en el medio, donde pone el simulador, elige tu
   iPhone.
4. `Cmd + R`.

La primera vez la app se instala pero **no se abre**, y sale un aviso de
«desarrollador no fiable». Se arregla en el móvil:

**Ajustes → General → VPN y gestión de dispositivos** → tu Apple ID →
**Confiar**.

Ahora sí: ábrela desde la pantalla de inicio.

## 10. Lo de los siete días

Con cuenta gratuita, la app **caduca a la semana**. Deja de abrirse y hay
que conectar el móvil y darle a Run otra vez para renovarla. Los datos no
se pierden —están en Supabase y en el propio móvil—, pero es un incordio.

Es la razón principal para pagar los 99 €, más que los widgets.

---

# Camino largo (pagando)

Si te haces del programa de desarrolladores, no hagas el paso 4 y añade
esto entre el 7 y el 8:

1. En **Signing & Capabilities**, con el objetivo **Habitium** elegido,
   pulsa **+ Capability** y añade:
   - **App Groups** → **+** → `group.com.habitium.app` (o el que hayas
     puesto en `APP_GROUP_ID`).
   - **HealthKit**.
   - **Sign in with Apple**.
2. Repite el App Group en los otros dos objetivos, **HabitiumWidgets** y
   **HabitiumWatch**. Tiene que ser **exactamente el mismo texto** en los
   tres: si en uno hay una letra distinta, el widget se queda en blanco y
   no da ningún error que lo explique.

Y el reloj: `HabitiumWatch` es la parte más delicada del `project.yml` y
es la que más papeletas tiene de dar guerra. Si `xcodegen` o Xcode
protestan por ella, lo más rápido es borrar ese bloque de `project.yml`,
volver a generar, y añadir el objetivo a mano desde Xcode
(**File → New → Target → watchOS → App**) apuntando sus fuentes a
`HabitiumWatch/` y `Shared/`.

---

# Cuando algo no funciona

| Qué ves | Qué suele ser |
|---|---|
| `xcodegen: command not found` | Falta `brew install xcodegen`. |
| Xcode se queda «Resolving Package Versions» | Está bajando Supabase. Déjalo. Si pasan diez minutos: **File → Packages → Reset Package Caches**. |
| `No account for team` | Paso 7: falta elegir tu Apple ID en **Team**. |
| `Failed to register bundle identifier` | Ese identificador ya lo usa alguien. Paso 5: ponle otro. |
| `Provisioning profile doesn't support the App Groups capability` | Cuenta gratuita. Paso 4. |
| `com.apple.developer.healthkit is not available` | Lo mismo. Paso 4. |
| La app se instala y no abre | Falta confiar en el desarrollador, al final del paso 9. |
| Dejó de abrirse a la semana | Los siete días del paso 10. Conecta y dale a Run. |
| Compila pero al entrar no pasa nada | Supabase: revisa `Secrets.xcconfig` y que hayas aplicado `supabase/schema.sql`. |
| «Ese correo no está invitado» | El registro está en modo invitación. Mira `docs/synology-y-supabase.md`, paso 1.4. |
| Se cierra sola al abrir Nutrición o Progreso | Puede ser el código de Salud, que sigue en la app aunque el permiso no esté. Mándame lo que salga en la consola de Xcode. |

---

# Mientras tanto

No hace falta esperar a que compile para usar Habitium: **la web ya
funciona**, se instala en la pantalla de inicio y se ve igual. Está en
`docs/synology-y-supabase.md`.

La diferencia de verdad entre las dos, hoy, son los avisos: el iPhone
puede avisarte con la app cerrada y la web todavía no.
