//
//  QuickAddBar.swift
//  Habitium
//
//  Single text field for Fantastical-style natural-language quick add.
//  Sits at the top of PlannerView so creating an event never requires
//  opening a form.
//

import SwiftUI

struct QuickAddBar: View {
    var onSubmit: (String) -> Void
    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .foregroundStyle(Theme.Colors.planner)
            TextField("Ej: Gimnasio mañana 18:00", text: $text)
                .focused($isFocused)
                .submitLabel(.done)
                .onSubmit(submit)
            if !text.isEmpty {
                Button(action: submit) {
                    Image(systemName: "arrow.up.circle.fill")
                        .foregroundStyle(Theme.Colors.planner)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Theme.Colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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
