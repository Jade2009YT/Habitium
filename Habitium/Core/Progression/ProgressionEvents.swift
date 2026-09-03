//
//  ProgressionEvents.swift
//  Habitium
//
//  El puente entre "se ha concedido experiencia" (que ocurre en el fondo
//  de un repositorio) y "el usuario lo ve" (que ocurre en la raíz de la
//  interfaz).
//
//  Por qué hace falta: los repositorios conceden XP desde muy abajo —
//  HabitRepository.toggleCompleted, MedicationRepository.markDoseTaken —
//  y no tienen ni deben tener acceso a la vista. Sin este canal, ganar
//  puntos era completamente invisible: solo se notaba entrando a la
//  pantalla de Progreso, que es justo cuando ya has perdido el momento.
//  Y el momento es lo único que hace que ganar puntos se sienta bien.
//

import Foundation
import Observation

@MainActor
@Observable
final class ProgressionEvents {

    static let shared = ProgressionEvents()
    private init() {}

    /// Concesiones aún por enseñar. La vista raíz las va sacando y
    /// mostrando de una en una.
    private(set) var queue: [XPAward] = []

    /// La subida de nivel pendiente de celebrar, si la hay. Se guarda
    /// aparte de la cola porque su celebración es a pantalla completa y
    /// debe ganar a cualquier aviso pequeño que esté en curso.
    private(set) var pendingLevelUp: XPAward?

    func post(_ award: XPAward?) {
        guard let award else { return }
        if award.didLevelUp || !award.unlockedTiers.isEmpty {
            pendingLevelUp = award
        } else {
            queue.append(award)
        }
    }

    func consumeNext() -> XPAward? {
        queue.isEmpty ? nil : queue.removeFirst()
    }

    func clearLevelUp() {
        pendingLevelUp = nil
    }
}
