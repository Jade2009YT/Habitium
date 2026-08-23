//
//  HabitiumWidgetsBundle.swift
//  HabitiumWidgets
//
//  Entry point for the widget extension — registers all four Habitium
//  widgets (nutrition, finance, calendar, medicación).
//

import WidgetKit
import SwiftUI

@main
struct HabitiumWidgetsBundle: WidgetBundle {
    var body: some Widget {
        NutritionWidget()
        FinanceWidget()
        CalendarWidget()
        MedicationWidget()
    }
}
