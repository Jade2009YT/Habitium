//
//  Theme.swift
//  Habitium
//
//  Los tokens de diseño compartidos: color, tipografía, espaciado y
//  elevación. Todo lo visual sale de aquí para que las siete pantallas
//  parezcan una app y no siete, y para poder retocar el aspecto entero
//  desde un único sitio.
//
//  Cada área tiene su color, y es el MISMO en la app, en los widgets, en
//  el Watch y en la web (web/styles.css) — verde nutrición, azul agenda,
//  naranja finanzas, morado hábitos, rosa medicación. Cuando el usuario
//  ve naranja, sabe que está en dinero, sin leer nada.
//

import SwiftUI

enum Theme {

    // MARK: - Color

    enum Colors {
        // Tonos propios en vez de Color.green/.blue del sistema: los de
        // Apple son muy saturados y, puestos en fila, hacen que la
        // pantalla parezca un semáforo.
        static let nutrition = Color(red: 0.09, green: 0.64, blue: 0.29)
        static let planner = Color(red: 0.15, green: 0.39, blue: 0.92)
        static let finance = Color(red: 0.92, green: 0.35, blue: 0.05)
        static let habits = Color(red: 0.49, green: 0.23, blue: 0.93)
        static let medication = Color(red: 0.86, green: 0.15, blue: 0.47)
        static let danger = Color(red: 0.86, green: 0.15, blue: 0.15)
        static let streak = Color(red: 0.96, green: 0.55, blue: 0.10)

        // Los fondos del sistema. Son el punto de partida y lo que se
        // ve con el tema "Automático"; el fondo elegido en Ajustes los
        // sustituye (ver BackgroundTheme). Se siguen usando donde hace
        // falta un color fijo fuera del árbol de vistas.
        static let cardBackground = Color(.secondarySystemGroupedBackground)
        static let screenBackground = Color(.systemGroupedBackground)

        /// Degradado suave para la cabecera de una tarjeta destacada.
        static func gradient(_ color: Color) -> LinearGradient {
            LinearGradient(
                colors: [color, color.opacity(0.72)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    // MARK: - Tipografía

    enum Fonts {
        /// Cifra grande de una tarjeta (calorías restantes, saldo…).
        static let metric = Font.system(size: 34, weight: .bold, design: .rounded)
        static let metricSmall = Font.system(size: 24, weight: .bold, design: .rounded)
        /// Título de sección dentro de una tarjeta.
        static let cardTitle = Font.system(size: 13, weight: .semibold)
        static let rowTitle = Font.system(size: 15, weight: .semibold)
    }

    // MARK: - Medidas

    enum Layout {
        static let cornerRadius: CGFloat = 20
        static let cardPadding: CGFloat = 18
        static let sectionSpacing: CGFloat = 16
        static let rowSpacing: CGFloat = 12
    }
}

// MARK: - Tarjeta

/// Contenedor base de todas las tarjetas. La sombra es muy suave a
/// propósito: separa la tarjeta del fondo sin que parezca que flota.
///
/// Con un fondo oscuro esa sombra no se ve —negro sobre negro—, así que
/// ahí la tarjeta se despega con un borde tenue. Es el mismo componente:
/// quien elige el fondo no tiene que saber nada de esto.
struct CardBackground: ViewModifier {
    @Environment(AppearanceStore.self) private var appearance: AppearanceStore?
    var padding: CGFloat = Theme.Layout.cardPadding

    private var theme: BackgroundTheme { appearance?.background ?? .system }
    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.Layout.cornerRadius, style: .continuous)
    }

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(theme.cardColor)
            .clipShape(shape)
            .overlay {
                if let border = theme.cardBorder {
                    shape.strokeBorder(border, lineWidth: 1)
                }
            }
            .shadow(color: .black.opacity(theme.cardShadowOpacity), radius: 8, x: 0, y: 2)
    }
}

extension View {
    func cardStyle(padding: CGFloat = Theme.Layout.cardPadding) -> some View {
        modifier(CardBackground(padding: padding))
    }

    /// Encoge ligeramente la tarjeta al pulsarla. Sin esto, una tarjeta
    /// que navega no da ninguna señal de ser pulsable.
    func pressable() -> some View {
        buttonStyle(PressableCardButtonStyle())
    }
}

struct PressableCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
