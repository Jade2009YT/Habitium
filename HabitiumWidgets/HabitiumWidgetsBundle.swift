//
//  HabitiumWidgetsBundle.swift
//  HabitiumWidgets
//
//  Entry point for the widget extension — registers all three Habitium
//  widgets (nutrition, finance, calendar).
//

import WidgetKit
import SwiftUI

@main
struct HabitiumWidgetsBundle: WidgetBundle {
    var body: some Widget {
        NutritionWidget()
        FinanceWidget()
        CalendarWidget()
    }
}
