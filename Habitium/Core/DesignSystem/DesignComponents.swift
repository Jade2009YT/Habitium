//
//  DesignComponents.swift
//  Habitium
//
//  Las piezas visuales que se repiten por toda la app. Existen para que
//  una fila de hábito y una fila de medicación se vean hermanas sin tener
//  que acordarse de repetir los mismos paddings y tamaños en cada
//  pantalla — y para que cambiar el aspecto de todas sea editar un sitio.
//

import SwiftUI

// MARK: - Cabecera de tarjeta

/// El icono en pastilla de color + título que abre cada tarjeta. El
/// `trailing` opcional es para el contador de la derecha ("3/5 hoy").
struct CardHeader<Trailing: View>: View {
    let title: String
    let symbol: String
    let color: Color
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 10) {
            IconBadge(symbol: symbol, color: color)
            Text(title)
                .font(Theme.Fonts.cardTitle)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .kerning(0.4)
            Spacer(minLength: 8)
            trailing
        }
    }
}

extension CardHeader where Trailing == EmptyView {
    init(title: String, symbol: String, color: Color) {
        self.init(title: title, symbol: symbol, color: color) { EmptyView() }
    }
}

/// Icono sobre un fondo del mismo color al 15% — el elemento que más
/// identidad da a la app, y lo que hace que cada área se reconozca de un
/// vistazo sin leer el título.
struct IconBadge: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 30

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.46, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
    }
}

// MARK: - Anillo de progreso

/// Anillo para la tarjeta de calorías. Se pasa de 1.0 a propósito cuando
/// hay exceso: el anillo se completa y cambia a rojo, en vez de quedarse
/// clavado al 100% sin avisar de que te has pasado.
struct RingProgress: View {
    let progress: Double
    let color: Color
    var lineWidth: CGFloat = 12
    var size: CGFloat = 128

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Lo que se dibuja ahora mismo. Empieza en 0 y sube hasta `clamped`
    /// al aparecer: un anillo que ya está lleno cuando abres la pantalla
    /// no dice nada, uno que se llena delante de ti sí.
    @State private var shown: Double = 0

    private var clamped: Double { min(max(progress, 0), 1) }
    private var isOver: Bool { progress > 1.0 }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color(.tertiarySystemFill), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: shown)
                .stroke(
                    isOver ? Theme.Colors.danger : color,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
        .onAppear { fill(to: clamped, duration: 0.85) }
        .onChange(of: clamped) { _, new in fill(to: new, duration: 0.5) }
    }

    private func fill(to target: Double, duration: Double) {
        guard !reduceMotion else {
            shown = target
            return
        }
        withAnimation(.easeOut(duration: duration)) { shown = target }
    }
}

// MARK: - Barra de progreso

/// Sustituye a ProgressView: permite altura propia y color de exceso, dos
/// cosas que la nativa no deja controlar.
struct ProgressBar: View {
    let value: Double
    let color: Color
    var height: CGFloat = 7

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: Double = 0

    private var clamped: Double { min(max(value, 0), 1) }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color(.tertiarySystemFill))
                Capsule()
                    .fill(value > 1.0 ? Theme.Colors.danger : color)
                    .frame(width: geometry.size.width * shown)
            }
        }
        .frame(height: height)
        .onAppear { fill(to: clamped, duration: 0.6) }
        .onChange(of: clamped) { _, new in fill(to: new, duration: 0.35) }
    }

    private func fill(to target: Double, duration: Double) {
        guard !reduceMotion else {
            shown = target
            return
        }
        withAnimation(.easeOut(duration: duration)) { shown = target }
    }
}

// MARK: - Racha

/// La llama con el número de días. Es el elemento que engancha, así que
/// se muestra igual en Inicio y en la pantalla de Hábitos.
struct StreakBadge: View {
    let days: Int

    var body: some View {
        Label("\(days)", systemImage: "flame.fill")
            .font(.caption2.weight(.bold))
            .foregroundStyle(Theme.Colors.streak)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Theme.Colors.streak.opacity(0.14), in: Capsule())
    }
}

// MARK: - Estado vacío

/// Un vacío nunca debe ser una tarjeta en blanco: dice qué falta y, si
/// procede, cómo llenarlo.
struct EmptyHint: View {
    let symbol: String
    let message: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(.tertiary)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Flecha de "esto navega"

/// El chevron de las tarjetas que llevan a otra pantalla. Sin él no hay
/// forma de distinguir una tarjeta pulsable de una informativa.
struct DisclosureChevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.tertiary)
    }
}
