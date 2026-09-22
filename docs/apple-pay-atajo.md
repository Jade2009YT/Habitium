# Apuntar el gasto justo después de pagar con Apple Pay

La idea era: *"que cuando detecte que he pagado con Apple Pay se abra la
app para añadir lo que me he gastado"*. Esto explica qué parte se puede
hacer, cuál no, y cómo montar la que sí.

## Lo que NO se puede, y por qué no es culpa de Habitium

**Ninguna app de terceros puede leer tus pagos de Apple Pay.** No existe
una API para eso: el importe, el comercio y la tarjeta no salen de
Wallet, ni en iOS ni en Android. Apple no lo permite a nadie, y es una
decisión suya de privacidad, no una limitación de esta app.

Hay una excepción que no te sirve: la automatización de Atajos con
disparador **"Transacción"** sí da el importe, pero solo funciona con
**Apple Card** y **Apple Cash**, que no existen en España.

Cualquier app que te diga que "detecta tus pagos" está haciendo una de
estas tres cosas: leer las notificaciones de tu banco (necesita permisos
de accesibilidad y es un agujero de seguridad), conectarse a tu banco por
open banking (otro proyecto, con su coste), o mentirte.

## Lo que SÍ se puede: la automatización de Wallet

Cuando pagas con el doble clic del botón lateral, iOS **abre Wallet**; al
terminar el pago, **la cierra**. Y Atajos sabe dispararse cuando una app
se cierra.

Así que la automatización no adivina el importe —nadie puede— pero te lo
**pregunta en el momento exacto en que acabas de pagar**, que es cuando
te acuerdas. Escribes "4,20 bocadillo" y ya está apuntado, sin abrir
Habitium.

### Cómo montarla (cinco minutos, una vez)

1. Abre **Atajos** → pestaña **Automatización** → **+**.
2. Baja hasta **App** y tócala.
3. En **App**, elige **Wallet**. En cuándo, marca **Se cierra** y
   desmarca *Se abre*.
4. Marca **Ejecutar inmediatamente** y desactiva *Notificar al ejecutar*.
   Sin esto te saldría una notificación que hay que tocar, y entonces ya
   no son cinco segundos.
5. **Siguiente** → **Nuevo atajo en blanco**.
6. Añade la acción **Pedir entrada**. Pregunta: `¿Cuánto has gastado?`.
   En *Tipo de entrada* deja **Texto** (no Número: así puedes escribir
   "4,20 bocadillo" de una vez).
7. Añade la acción **Apuntar un gasto** (sale buscando "Habitium") y
   pásale la *Entrada proporcionada*.
8. Listo.

A partir de ahí: pagas con Apple Pay → te sale un campo → escribes el
importe → hecho.

### Si no quieres que te pregunte cada vez

Cámbiala a dispararse **al abrir Habitium**, o quita la automatización y
usa el atajo a mano desde:

- **Siri**: *"Oye Siri, apunta un gasto en Habitium"*.
- **Pantalla de bloqueo**: mantén pulsado → Personalizar → añade el
  widget de Atajos con "Apuntar gasto".
- **Botón de Acción** (iPhone 15 Pro en adelante): Ajustes → Botón de
  Acción → Atajo → Apuntar gasto. Es un botón físico y un campo: lo más
  rápido que hay.
- **Centro de Control** (iOS 18+): añade el atajo como control.

## Lo que entiende el campo

Se escribe tal cual, como lo dirías:

| Escribes | Apunta |
|---|---|
| `4,20 bocadillo` | 4,20 € · Comida · "bocadillo" |
| `12.50 cine` | 12,50 € · Ocio · "cine" |
| `3,5€ bus` | 3,50 € · Transporte · "bus" |
| `45 mercadona` | 45,00 € · Comida · "mercadona" |
| `7` | 7,00 € · Otro |
| `bocadillo` | nada — te avisa de que falta el importe |

Coge **el primer número**, así que `4,20 bocadillo para 2` son 4,20 € y
no 2 €. Y adivina la categoría por la palabra; si no la acierta, la
pone en "Otro" y la cambias de un toque en la app.

**Funciona sin internet y sin IA**, a propósito: en la cola del súper con
mala cobertura, un atajo que depende de que conteste un servidor falla
justo cuando hace falta. La IA, si la tienes configurada, solo afina la
categoría después — el gasto ya está guardado.

## Los otros dos atajos

Habitium expone tres acciones a Atajos y a Siri:

- **Apuntar un gasto** — lo de arriba.
- **Marcar el siguiente paso de mi rutina** — para la rutina de la mañana:
  te duchas, dices *"Oye Siri, siguiente paso en Habitium"* y sigues.
  Marca el paso que toca ahora y recalcula los avisos de los que quedan.
- **¿Cuánto me queda este mes?** — el presupuesto que te queda y a cuánto
  sale por día.

## Y en Android

La automatización de Wallet no tiene equivalente: Google Wallet no
expone nada parecido. Lo que sí funciona es el campo rápido de la web
(**Finanzas → "Rápido: 4,20 bocadillo"**), que entiende exactamente lo
mismo. Con Habitium añadida a la pantalla de inicio, son dos toques.
