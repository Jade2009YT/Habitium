//
//  WidgetRefresher.swift
//  Habitium
//
//  Tiny wrapper around WidgetCenter so repositories can ask WidgetKit to
//  reload timelines right after they publish a fresh snapshot to
//  SharedDataStore, without importing WidgetKit everywhere.
//

import WidgetKit

enum WidgetRefresher {
    static func reloadNutritionWidget() {
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetKind.nutrition)
    }

    static func reloadFinanceWidget() {
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetKind.finance)
    }

    static func reloadCalendarWidget() {
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetKind.calendar)
    }

    static func reloadAll() {
        WidgetCenter.shared.reloadAllTimelines()
    }
}
