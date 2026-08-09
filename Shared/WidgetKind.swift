//
//  WidgetKind.swift
//  Habitium (shared between the app and widget extension targets)
//
//  Widget kind identifiers. The app uses these to target reloads via
//  WidgetCenter; the widget extension uses them as each WidgetConfiguration's
//  `kind`. Defined once so both sides can never drift apart.
//

enum WidgetKind {
    static let nutrition = "HabitiumNutritionWidget"
    static let finance = "HabitiumFinanceWidget"
    static let calendar = "HabitiumCalendarWidget"
}
