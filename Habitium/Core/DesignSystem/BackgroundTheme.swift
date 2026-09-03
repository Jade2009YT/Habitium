//
//  BackgroundTheme.swift
//  Habitium
//
//  El color de fondo de la app, a elección de quien la usa.
//
//  Por qué esto y no una sola dirección de diseño: al maquetar tres
//  estilos (oscuro con neón, colores planos tipo pegatina, y editorial
//  claro) lo que realmente cambiaba entre ellos era el fondo. En vez de
//  elegir uno por todo el mundo, el fondo se elige y la app se adapta.
//  El resto del diseño —tarjetas, radios, colores de cada área— no
//  cambia: sigue siendo la misma app, no seis apps distintas.
//
//  Cada fondo trae CUATRO cosas, no una: el color de pantalla, el de las
//  tarjetas, si el texto va en claro u oscuro, y cómo se separa una
//  tarjeta del fondo. Ese último detalle es el que se suele olvidar: una
//  sombra sobre fondo casi negro no se ve, así que en los fondos oscuros
//  la tarjeta se separa con un borde tenue en vez de con sombra. Sin eso,
//  el modo oscuro queda como una mancha plana.
//

import SwiftUI

enum BackgroundTheme: String, CaseIterable, Identifiable {
    /// Sigue al iPhone: claro de día, oscuro de noche. Es el de por
    /// defecto porque es el que nunca sorprende a nadie.
    case system
    case light
    case cream
    case vanilla
    case graphite
    case night

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "Automático"
        case .light: return "Claro"
        case .cream: return "Crema"
        case .vanilla: return "Vainilla"
        case .graphite: return "Grafito"
        case .night: return "Noche"
        }
    }

    var subtitle: String {
        switch self {
        case .system: return "Sigue al iPhone"
        case .light: return "Siempre claro"
        case .cream: return "Blanco cálido"
        case .vanilla: return "Crema con un punto amarillo"
        case .graphite: return "Oscuro suave"
        case .night: return "Casi negro"
        }
    }

    /// El fondo de la pantalla.
    var screenColor: Color {
        switch self {
        case .system: return Color(.systemGroupedBackground)
        case .light: return Color(red: 0.95, green: 0.95, blue: 0.97)
        case .cream: return Color(red: 0.98, green: 0.98, blue: 0.97)
        case .vanilla: return Color(red: 1.00, green: 0.97, blue: 0.91)
        case .graphite: return Color(red: 0.09, green: 0.09, blue: 0.11)
        case .night: return Color(red: 0.04, green: 0.05, blue: 0.06)
        }
    }

    /// El fondo de las tarjetas. Siempre un paso por delante del de la
    /// pantalla —más claro en los temas claros, más claro también en los
    /// oscuros— para que la tarjeta se lea como algo que está encima.
    var cardColor: Color {
        switch self {
        case .system: return Color(.secondarySystemGroupedBackground)
        case .light: return .white
        case .cream: return .white
        case .vanilla: return Color(red: 1.00, green: 0.99, blue: 0.96)
        case .graphite: return Color(red: 0.14, green: 0.15, blue: 0.17)
        case .night: return Color(red: 0.09, green: 0.09, blue: 0.11)
        }
    }

    /// Qué esquema de color forzar. `nil` = el del sistema.
    ///
    /// Esto es lo que hace que el texto, la barra de pestañas y los
    /// menús acompañen al fondo. Elegir "Noche" y que la barra de abajo
    /// siguiera blanca sería peor que no poder elegir.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light, .cream, .vanilla: return .light
        case .graphite, .night: return .dark
        }
    }

    var isDark: Bool {
        switch self {
        case .graphite, .night: return true
        default: return false
        }
    }

    /// Sombra bajo las tarjetas. En oscuro no se ve nada, así que es 0.
    var cardShadowOpacity: Double { isDark ? 0 : 0.05 }

    /// Borde de la tarjeta, solo en los fondos oscuros: sustituye a la
    /// sombra como forma de despegarla del fondo.
    var cardBorder: Color? {
        isDark ? Color.white.opacity(0.07) : nil
    }
}

/// Dónde vive el fondo elegido.
///
/// Es `@Observable` y no un simple `UserDefaults.standard.string(...)`
/// como el tema de acento porque este SÍ tiene que repintar la app
/// entera en el momento en que se toca: si hubiera que cerrar y abrir
/// para ver el cambio, nadie lo tocaría dos veces.
///
/// Sigue siendo una preferencia de ESTE dispositivo y no viaja por la
/// sincronización, igual que el acento: es razonable querer la app en
/// claro en el iPhone y en oscuro en el iPad.
@MainActor
@Observable
final class AppearanceStore {
    private static let defaultsKey = "habitium.backgroundTheme"

    var background: BackgroundTheme {
        didSet {
            guard background != oldValue else { return }
            UserDefaults.standard.set(background.rawValue, forKey: Self.defaultsKey)
        }
    }

    init() {
        let stored = UserDefaults.standard.string(forKey: Self.defaultsKey)
        background = stored.flatMap(BackgroundTheme.init(rawValue:)) ?? .system
    }
}

// MARK: - Aplicar el fondo a una pantalla

/// Pinta el fondo del tema detrás de una pantalla.
///
/// Busca el `AppearanceStore` de forma OPCIONAL a propósito: así una
/// vista suelta (una preview, una pantalla montada fuera de la raíz)
/// se dibuja con el fondo del sistema en vez de reventar por no
/// encontrarlo en el entorno.
struct ThemedScreenBackground: ViewModifier {
    @Environment(AppearanceStore.self) private var appearance: AppearanceStore?

    func body(content: Content) -> some View {
        content.background {
            (appearance?.background ?? .system).screenColor.ignoresSafeArea()
        }
    }
}

// MARK: - Muestra para elegir

/// La miniatura de un fondo en Ajustes: la pantalla con una tarjeta
/// encima, que es exactamente lo que se va a ver.
///
/// Enseñar el color de verdad y no un círculo de color evita la duda de
/// "¿esto pinta el fondo o los botones?" — que es justo la confusión que
/// tendría cualquiera al ver dos listas de colores en la misma pantalla
/// de Ajustes (esta y la de temas de acento).
struct BackgroundSwatch: View {
    let theme: BackgroundTheme
    let isSelected: Bool

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
    }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                if theme == .system {
                    // Partido en dos: es la única forma de que se
                    // entienda de un vistazo que este cambia solo.
                    HStack(spacing: 0) {
                        BackgroundTheme.light.screenColor
                        BackgroundTheme.night.screenColor
                    }
                } else {
                    theme.screenColor
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(theme.cardColor)
                        .frame(height: 20)
                        .padding(.horizontal, 12)
                        .padding(.top, 16)
                }
            }
            .frame(height: 54)
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(
                    isSelected ? AccentThemeStore.current.color : Color.primary.opacity(0.12),
                    lineWidth: isSelected ? 2.5 : 1
                )
            }

            Text(theme.displayName)
                .font(.caption2.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? .primary : .secondary)
                .lineLimit(1)
        }
    }
}

/// El color de tarjeta del tema, suelto. Para los pocos elementos que
/// son "superficie" pero no una tarjeta entera: la barra de alta rápida
/// del calendario, las fichas de comidas recientes.
struct ThemedCardFill: ViewModifier {
    @Environment(AppearanceStore.self) private var appearance: AppearanceStore?

    func body(content: Content) -> some View {
        content.background((appearance?.background ?? .system).cardColor)
    }
}

extension View {
    /// El fondo de pantalla del tema elegido.
    func themedBackground() -> some View {
        modifier(ThemedScreenBackground())
    }

    /// El color de tarjeta del tema elegido, como fondo.
    func themedCardFill() -> some View {
        modifier(ThemedCardFill())
    }
}
