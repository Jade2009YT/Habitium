#!/usr/bin/env bash
#
# Deja Habitium en la forma que SÍ se puede firmar con una cuenta de
# Apple gratuita.
#
# Apple reserva tres permisos a las cuentas del programa de
# desarrolladores (99 €/año), y el proyecto usa los tres:
#
#   · App Groups   → que el widget y el reloj vean tus datos
#   · HealthKit    → leer del Apple Watch las calorías y los entrenos
#   · Sign in with Apple → el botón de entrar con tu Apple ID
#
# Sin ellos, el widget y el reloj no tienen forma de leer nada, así que
# este guion quita los tres permisos y también esos dos objetivos: dejar
# un widget que no puede funcionar solo sirve para que la compilación
# falle por algo que no se puede arreglar.
#
# La app se queda entera: hábitos, rutinas, nutrición, finanzas, agenda,
# estudios, el buzón de ideas y la sincronización con Supabase. Lo único
# que se va es el widget, el reloj, los datos de Salud y el botón de
# Apple (queda entrar con correo y contraseña, que es lo que usa la web).
#
# Deja una copia en project.yml.con-cuenta-de-pago. Para volver atrás:
#
#     mv project.yml.con-cuenta-de-pago project.yml && xcodegen generate

set -euo pipefail

cd "$(dirname "$0")/.."

if [ ! -f project.yml ]; then
  echo "✗ No encuentro project.yml. Ejecútalo desde la carpeta del proyecto."
  exit 1
fi

if [ -f project.yml.con-cuenta-de-pago ]; then
  echo "⚠️  Ya existe project.yml.con-cuenta-de-pago: esto ya se ejecutó antes."
  echo "   Si quieres empezar de cero:"
  echo "     mv project.yml.con-cuenta-de-pago project.yml"
  exit 1
fi

cp project.yml project.yml.con-cuenta-de-pago

python3 - << 'PY'
import re
import sys

lineas = open("project.yml", encoding="utf-8").read().split("\n")

def sangria(linea):
    return len(linea) - len(linea.lstrip())

def quitar_bloque(lineas, patron, nivel):
    """Quita una clave y todo lo que cuelga de ella.

    Lo de 'todo lo que cuelga' se decide por la sangría, que es como
    funciona YAML: el bloque acaba en la primera línea con contenido que
    esté igual de metida o menos. Los comentarios pegados justo encima se
    van también — si no, quedarían explicando algo que ya no existe.
    """
    salida, i, quitadas = [], 0, 0
    while i < len(lineas):
        if re.match(patron, lineas[i]) and sangria(lineas[i]) == nivel:
            # Los comentarios de justo encima se van con el bloque.
            while salida and salida[-1].strip().startswith("#"):
                salida.pop()
            i += 1
            while i < len(lineas):
                l = lineas[i]
                if l.strip() and not l.strip().startswith("#") and sangria(l) <= nivel:
                    break
                if l.strip() and sangria(l) <= nivel:
                    break
                i += 1
            quitadas += 1
            continue
        salida.append(lineas[i])
        i += 1
    return salida, quitadas

hechas = []

# ── 1. Los dos objetivos que no pueden funcionar sin App Groups ───────
for nombre in ("HabitiumWidgetsExtension", "HabitiumWatch"):
    lineas, n = quitar_bloque(lineas, rf"^  {nombre}:", 2)
    if n:
        hechas.append(f"objetivo {nombre}")

# ── 2. Lo que la app dependía de ellos ────────────────────────────────
fuera = []
i = 0
while i < len(lineas):
    l = lineas[i]
    if re.match(r"^\s*- target: (HabitiumWidgetsExtension|HabitiumWatch)\s*$", l):
        i += 1
        # Se lleva por delante el "embed: true" que va debajo.
        if i < len(lineas) and "embed:" in lineas[i]:
            i += 1
        hechas.append("dependencia del objetivo quitado")
        continue
    fuera.append(l)
    i += 1
lineas = fuera

# ── 3. Y de la lista de lo que se compila ─────────────────────────────
lineas = [
    l for l in lineas
    if not re.match(r"^\s*(HabitiumWidgetsExtension|HabitiumWatch): all\s*$", l)
]

# ── 4. Los tres permisos ──────────────────────────────────────────────
#
# Se quita el bloque `entitlements` entero del objetivo Habitium y no
# solo las líneas de los permisos: si se dejaran `path` y un `properties`
# vacío, XcodeGen escribiría un archivo de permisos sin nada dentro, que
# es peor que no tenerlo.
lineas, n = quitar_bloque(lineas, r"^    entitlements:", 4)
if n:
    hechas.append(f"bloque de permisos ({n})")

texto = "\n".join(lineas)

# Comprobación: si algo de esto sigue ahí, la compilación va a fallar por
# firma y el guion no habría servido de nada.
restos = [p for p in (
    "HabitiumWidgetsExtension", "HabitiumWatch",
    "application-groups", "applesignin", "healthkit",
) if p in texto]

if restos:
    print("✗ Han quedado restos:", ", ".join(restos))
    print("  No se ha cambiado nada. Recupera con:")
    print("    mv project.yml.con-cuenta-de-pago project.yml")
    sys.exit(1)

open("project.yml", "w", encoding="utf-8").write(texto)

print("Quitado:")
for h in sorted(set(hechas)):
    print("  ·", h)
PY

echo ""
echo "✓ project.yml listo para una cuenta gratuita."
echo "  Copia de seguridad en project.yml.con-cuenta-de-pago"
echo ""
echo "Ahora:"
echo "  xcodegen generate"
echo "  open Habitium.xcodeproj"
