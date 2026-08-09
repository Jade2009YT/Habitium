//
//  AppGroup.swift
//  Habitium (shared between the app and widget extension targets)
//
//  Minimal, dependency-free accessor for the App Group identifier so both
//  targets can resolve it from their own Info.plist without one target
//  reaching into the other's code.
//

import Foundation

enum AppGroup {
    static var identifier: String {
        Bundle.main.object(forInfoDictionaryKey: "APP_GROUP_ID") as? String ?? "group.com.habitium.app"
    }
}
