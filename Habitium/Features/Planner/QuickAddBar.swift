//
//  QuickAddBar.swift
//  Habitium
//
//  Un campo de texto para crear un evento escribiéndolo en lenguaje
//  normal ("Gimnasio mañana 18:00"), estilo Fantastical.
//
//  Va arriba del todo del calendario porque es la vía rápida: crear algo
//  no debería obligar a abrir un formulario. La pista de debajo existe
//  porque un campo vacío no enseña lo que sabe entender — sin un ejemplo
//  delante, casi nadie prueba a escribir la hora en la misma frase.
//

import SwiftUI

struct QuickAddBar: View {
    var onSubmit: (String) -> Void
    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                IconBadge(symbol: "sparkles", color: Theme.Colors.planner, size: 28)

                TextField("Gimnasio mañana 18:00", text: $text)
                    .font(.subheadline)
                    .focused($isFocused)
                    .submitLabel(.done)
                    .onSubmit(submit)

                if !text.isEmpty {
                    Button(action: submit) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title3)
                            .foregroundStyle(Theme.Colors.planner)
                    }
                    .buttonStyle(.plain)
                    .transition(.scale.combined(with: .opacity))
                }
            }

            if !isFocused && text.isEmpty {
                Text("Escríbelo como lo dirías y se crea solo, con su hora.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .animation(Motion.entrance, value: text.isEmpty)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle(padding: 14)
    }

    private func submit() {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        onSubmit(text)
        text = ""
        isFocused = false
    }
}

#Preview {
    QuickAddBar { _ in }
        .padding()
}
