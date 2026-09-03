//
//  Celebration.swift
//  Habitium
//
//  El momento de subir de nivel y el aviso de "+15 XP".
//
//  Esto es lo que faltaba para que la progresión se sintiera: antes se
//  ganaban puntos en silencio y solo se veían entrando a Progreso, o sea
//  cuando el momento ya había pasado. Un número que sube sin que nadie lo
//  celebre no engancha a nadie.
//
//  El confeti está dibujado a mano con Canvas en vez de con una librería:
//  son treinta rectángulos girando, no merece una dependencia, y así se
//  controla que dure lo justo y no moleste.
//

import SwiftUI

// MARK: - Confeti

struct ConfettiView: View {
    let color: Color
    @State private var isAnimating = false

    private struct Piece: Identifiable {
        let id = UUID()
        let x: Double            // 0-1, posición horizontal de salida
        let delay: Double
        let rotation: Double
        let scale: Double
        let hue: Double          // desplazamiento sobre el color base
    }

    // Se generan una vez, no en cada repintado: si se regeneraran, el
    // confeti "saltaría" a posiciones nuevas a mitad de la animación.
    private let pieces: [Piece] = (0..<34).map { _ in
        Piece(
            x: Double.random(in: 0...1),
            delay: Double.random(in: 0...0.45),
            rotation: Double.random(in: -220...220),
            scale: Double.random(in: 0.55...1.25),
            hue: Double.random(in: -0.12...0.12)
        )
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(pieces) { piece in
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(color.opacity(0.9))
                        .hueRotation(.degrees(piece.hue * 360))
                        .frame(width: 7 * piece.scale, height: 12 * piece.scale)
                        .rotationEffect(.degrees(isAnimating ? piece.rotation : 0))
                        .position(
                            x: geometry.size.width * piece.x,
                            y: isAnimating ? geometry.size.height + 40 : -40
                        )
                        .opacity(isAnimating ? 0 : 1)
                        .animation(
                            .easeIn(duration: 1.9).delay(piece.delay),
                            value: isAnimating
                        )
                }
            }
        }
        .allowsHitTesting(false)
        .onAppear { isAnimating = true }
    }
}

// MARK: - Subida de nivel

/// La pantalla que aparece al subir de nivel o desbloquear algo del pase.
/// Se cierra sola a los 3 segundos, pero también al tocar: forzar a
/// esperar una animación es lo que hace que la gente odie las
/// celebraciones de las apps.
struct LevelUpOverlay: View {
    let award: XPAward
    let accent: Color
    let unlockedRewards: [SeasonTier]
    let onDismiss: () -> Void

    @State private var appeared = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            ConfettiView(color: accent)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                ZStack {
                    Circle()
                        .fill(accent.opacity(0.22))
                        .frame(width: 132, height: 132)
                        .scaleEffect(appeared ? 1.15 : 0.8)
                    Circle()
                        .fill(Theme.Colors.gradient(accent))
                        .frame(width: 104, height: 104)
                    VStack(spacing: -3) {
                        Text("\(award.newLevel)")
                            .font(.system(size: 42, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                        Text("NIVEL")
                            .font(.caption2.weight(.bold))
                            .kerning(1.5)
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }
                .scaleEffect(appeared ? 1 : 0.4)
                .rotationEffect(.degrees(appeared ? 0 : -25))

                VStack(spacing: 6) {
                    Text(award.didLevelUp ? "¡Has subido de nivel!" : "¡Recompensa desbloqueada!")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                    Text(ProgressionEngine.title(forLevel: award.newLevel))
                        .font(.headline)
                        .foregroundStyle(accent)
                }

                if !unlockedRewards.isEmpty {
                    VStack(spacing: 8) {
                        ForEach(unlockedRewards) { tier in
                            HStack(spacing: 9) {
                                Image(systemName: tier.symbolName)
                                    .foregroundStyle(accent)
                                Text(tier.rewardName)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.white)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(.white.opacity(0.12), in: Capsule())
                        }
                    }
                }

                Text("Toca para continuar")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.top, 4)
            }
            .padding(32)
            .opacity(appeared ? 1 : 0)
        }
        .onAppear {
            Haptics.celebrate()
            withAnimation(.spring(response: 0.55, dampingFraction: 0.62)) {
                appeared = true
            }
            // Se cierra sola por si el usuario deja el móvil en la mesa.
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { onDismiss() }
        }
    }
}

// MARK: - Aviso de XP

/// La pastilla "+15 XP" que baja desde arriba al ganar puntos.
struct XPToast: View {
    let award: XPAward
    let accent: Color

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: award.source.symbolName)
                .font(.subheadline.weight(.bold))
            Text("+\(award.amount) XP")
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
            Text(award.source.displayName)
                .font(.caption)
                .opacity(0.85)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 15)
        .padding(.vertical, 10)
        .background(Theme.Colors.gradient(accent), in: Capsule())
        .shadow(color: accent.opacity(0.4), radius: 12, y: 4)
    }
}

// MARK: - Modificador raíz

/// Se pone UNA vez en la raíz de la app. Escucha ProgressionEvents y
/// enseña los avisos y la celebración por encima de lo que haya.
struct ProgressionFeedback: ViewModifier {
    @State private var events = ProgressionEvents.shared
    @State private var visibleToast: XPAward?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let toast = visibleToast {
                    XPToast(award: toast, accent: accent)
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .overlay {
                if let levelUp = events.pendingLevelUp {
                    LevelUpOverlay(
                        award: levelUp,
                        accent: accent,
                        unlockedRewards: SeasonPass.tiers.filter { levelUp.unlockedTiers.contains($0.id) },
                        onDismiss: { events.clearLevelUp() }
                    )
                    .transition(.opacity)
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.75), value: visibleToast?.amount)
            .animation(.easeInOut(duration: 0.25), value: events.pendingLevelUp?.newLevel)
            .onChange(of: events.queue.count) { _, _ in
                showNextToastIfIdle()
            }
    }

    private var accent: Color {
        AccentThemeStore.current.color
    }

    /// De uno en uno: dos pastillas solapadas serían ilegibles, y marcar
    /// varios hábitos seguidos genera varias concesiones a la vez.
    private func showNextToastIfIdle() {
        guard visibleToast == nil, let next = events.consumeNext() else { return }
        visibleToast = next
        Haptics.tap()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.7) {
            visibleToast = nil
            // Encadena con el siguiente si se acumularon.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                showNextToastIfIdle()
            }
        }
    }
}

extension View {
    func progressionFeedback() -> some View {
        modifier(ProgressionFeedback())
    }
}
