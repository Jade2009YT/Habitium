//
//  NaturalLanguageQuickAdd.swift
//  Habitium
//
//  Free-text → event parsing, the single feature that makes Fantastical
//  feel magic ("Gimnasio mañana 18:00" becomes a real event). Uses
//  Foundation's on-device NSDataDetector — no network call, no AI cost,
//  works offline.
//

import Foundation

enum NaturalLanguageQuickAdd {
    struct ParsedEvent {
        var title: String
        var date: Date
    }

    /// Extracts the first date/time mention from `text` and returns the
    /// remaining words as the event title. Falls back to 9:00 AM on
    /// `defaultDate` if no date/time phrase is found, so quick-add always
    /// produces something usable instead of silently failing.
    static func parse(_ text: String, defaultDate: Date = .now) -> ParsedEvent {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ParsedEvent(title: "Nuevo evento", date: nineAM(on: defaultDate))
        }

        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else {
            return ParsedEvent(title: trimmed, date: nineAM(on: defaultDate))
        }

        let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        guard let match = detector.firstMatch(in: trimmed, range: range),
              let matchRange = Range(match.range, in: trimmed),
              let date = match.date else {
            return ParsedEvent(title: trimmed, date: nineAM(on: defaultDate))
        }

        var title = trimmed
        title.removeSubrange(matchRange)
        title = title.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ",-·")))
        if title.isEmpty { title = "Nuevo evento" }

        return ParsedEvent(title: title, date: date)
    }

    private static func nineAM(on date: Date) -> Date {
        Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: date) ?? date
    }
}
