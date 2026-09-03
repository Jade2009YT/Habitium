//
//  Haptics.swift
//  Habitium
//
//  Vibración al tocar cosas. Suena a detalle tonto y es de lo que más
//  cambia la sensación de una app: marcar un hábito sin respuesta física
//  se siente a formulario; con un golpecito se siente a que ha pasado
//  algo.
//
//  Regla que se sigue en toda la app: la intensidad acompaña a la
//  importancia. Marcar algo es un toque ligero; subir de nivel es una
//  celebración. Si todo vibrara igual de fuerte, dejaría de significar
//  nada y solo molestaría.
//

import UIKit

enum Haptics {

    /// Marcar un hábito, completar una tarea, tocar una pestaña.
    static func tap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// Algo se ha completado del todo: todos los hábitos del día, un reto.
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// Subida de nivel o recompensa desbloqueada. El doble golpe hace que
    /// se note distinto de un simple "hecho".
    static func celebrate() {
        let generator = UIImpactFeedbackGenerator(style: .heavy)
        generator.impactOccurred()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
    }

    /// Algo no se ha podido hacer (p. ej. el cuarto foco del día).
    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
}
