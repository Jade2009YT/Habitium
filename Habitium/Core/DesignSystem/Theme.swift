//
//  Theme.swift
//  Habitium
//
//  Small shared design tokens so the four feature modules look like one
//  app instead of four. Intentionally minimal — expand as the UI grows.
//

import SwiftUI

enum Theme {
    enum Colors {
        static let nutrition = Color.green
        static let planner = Color.blue
        static let finance = Color.orange
        static let danger = Color.red
        static let cardBackground = Color(.secondarySystemBackground)
    }

    enum Layout {
        static let cornerRadius: CGFloat = 16
        static let cardPadding: CGFloat = 16
        static let sectionSpacing: CGFloat = 20
    }
}

/// Reusable "card" container used across Home/Nutrition/Planner/Finance.
struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(Theme.Layout.cardPadding)
            .background(Theme.Colors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Layout.cornerRadius, style: .continuous))
    }
}

extension View {
    func cardStyle() -> some View {
        modifier(CardBackground())
    }
}
