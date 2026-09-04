//
//  Motion.swift
//  Habitium
//
//  El movimiento de la app, en un solo sitio.
//
//  La diferencia entre una app que parece viva y una que parece una hoja
//  de cálculo no está en tener más animaciones: está en que las cosas
//  LLEGUEN en vez de aparecer. Una pantalla en la que las tarjetas se
//  colocan una detrás de otra en un cuarto de segundo se lee como algo
//  que responde; la misma pantalla dibujada de golpe se lee como una
//  página.
//
//  Dos reglas que se siguen en todo el archivo:
//
//  1. Nada dura más de medio segundo. Una animación bonita la primera
//     vez es un peaje la número cincuenta, y esta app se abre a diario.
//  2. Todo se salta entero si el iPhone tiene activado "Reducir
//     movimiento" (Ajustes → Accesibilidad → Movimiento). Quien lo
//     activa no quiere animaciones más cortas: quiere que nada se mueva,
//     y en muchos casos es porque le marea de verdad.
//

import SwiftUI

enum Motion {
    /// La curva de todo lo que entra: sale rápido y frena al final, que
    /// es como se mueven las cosas con peso.
    static let entrance = Animation.easeOut(duration: 0.34)
    /// Para números y barras que cambian de valor con la app abierta.
    static let value = Animation.easeOut(duration: 0.5)
    /// Para lo que celebra algo. Rebota un poco a propósito.
    static let celebrate = Animation.spring(response: 0.42, dampingFraction: 0.62)

    /// El retardo de la tarjeta que hace `index`.
    ///
    /// Se corta a la sexta: con nueve tarjetas y 40 ms cada una, la
    /// última tardaría casi medio segundo en aparecer y se notaría como
    /// lentitud, no como elegancia.
    static func stagger(_ index: Int) -> Double {
        min(Double(index), 5) * 0.045
    }
}

/// Hace que una vista entre subiendo y con opacidad, con su retardo
/// según el orden en que está en la pantalla.
struct AppearTransition: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let index: Int

    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 10)
            .onAppear {
                guard !reduceMotion else {
                    shown = true
                    return
                }
                withAnimation(Motion.entrance.delay(Motion.stagger(index))) {
                    shown = true
                }
            }
    }
}

extension View {
    /// Entrada escalonada. `index` es la posición de la tarjeta en la
    /// pantalla, empezando por 0.
    func appearIn(_ index: Int) -> some View {
        modifier(AppearTransition(index: index))
    }
}

// MARK: - Números que cuentan

/// Un número que sube contando en vez de saltar de golpe.
///
/// Por qué no basta con `.contentTransition(.numericText())`: eso anima
/// el CAMBIO de un número a otro (2 → 3), pero de 0 a 720 kcal daría un
/// solo salto. Aquí el valor se interpola de verdad, así que se ve subir.
///
/// `animatableData` es lo que hace el trabajo: SwiftUI llama a este
/// modificador muchas veces con valores intermedios entre el anterior y
/// el nuevo, y cada uno pinta su número.
struct CountingNumber: View, Animatable {
    var value: Double
    var format: (Double) -> String
    var font: Font
    var color: Color

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        Text(format(value))
            .font(font)
            .foregroundStyle(color)
            // Sin esto, "9" y "10" tienen anchos distintos y el número
            // da un tirón lateral en cada paso de la cuenta.
            .monospacedDigit()
            .contentTransition(.identity)
    }
}

/// Un entero que cuenta hasta su valor al aparecer.
struct CountingInt: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let value: Int
    var font: Font = Theme.Fonts.metric
    var color: Color = .primary
    var suffix: String = ""

    @State private var shown: Double = 0

    var body: some View {
        CountingNumber(
            value: shown,
            format: { "\(Int($0.rounded()))\(suffix)" },
            font: font,
            color: color
        )
        .onAppear { animate(to: Double(value)) }
        .onChange(of: value) { _, new in animate(to: Double(new)) }
    }

    private func animate(to target: Double) {
        guard !reduceMotion else {
            shown = target
            return
        }
        withAnimation(.easeOut(duration: 0.7)) { shown = target }
    }
}
