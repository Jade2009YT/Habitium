//
//  MonthCalendarView.swift
//  Habitium
//
//  Simple month grid: tap a day to select it, dot indicator for days that
//  have a task or event.
//

import SwiftUI

struct MonthCalendarView: View {
    @Binding var visibleMonth: Date
    @Binding var selectedDate: Date
    let daysWithItems: Set<Date>

    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible()), count: 7)

    var body: some View {
        VStack(spacing: 12) {
            header

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                ForEach(daysInMonthGrid, id: \.self) { date in
                    if let date {
                        dayCell(date)
                    } else {
                        Color.clear.frame(height: 36)
                    }
                }
            }
        }
        .cardStyle()
    }

    /// Las flechas van en pastilla y no como iconos sueltos: un chevron
    /// suelto en medio de una tarjeta no parece pulsable, y cambiar de
    /// mes es la única acción de este control.
    private var header: some View {
        HStack(spacing: 10) {
            monthButton(symbol: "chevron.left", delta: -1)

            Spacer(minLength: 0)

            VStack(spacing: 0) {
                Text(visibleMonth.formatted(.dateTime.month(.wide)))
                    .font(.headline)
                Text(visibleMonth.formatted(.dateTime.year()))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            monthButton(symbol: "chevron.right", delta: 1)
        }
    }

    private func monthButton(symbol: String, delta: Int) -> some View {
        Button {
            shiftMonth(by: delta)
        } label: {
            Image(systemName: symbol)
                .font(.footnote.weight(.bold))
                .foregroundStyle(Theme.Colors.planner)
                .frame(width: 30, height: 30)
                .background(
                    Theme.Colors.planner.opacity(0.15),
                    in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                )
        }
        .buttonStyle(.plain)
    }

    private func dayCell(_ date: Date) -> some View {
        let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)
        let isToday = calendar.isDateInToday(date)
        let hasItems = daysWithItems.contains(calendar.startOfDay(for: date))

        return Button {
            selectedDate = date
        } label: {
            VStack(spacing: 3) {
                Text("\(calendar.component(.day, from: date))")
                    .font(.subheadline.weight(isSelected || isToday ? .semibold : .regular))
                    .frame(width: 32, height: 32)
                    .background {
                        if isSelected {
                            Circle().fill(Theme.Colors.planner)
                        } else if isToday {
                            // Hoy sin seleccionar: aro, no relleno. Con dos
                            // círculos llenos no se sabría cuál está elegido.
                            Circle().strokeBorder(Theme.Colors.planner, lineWidth: 1.5)
                        }
                    }
                    .foregroundStyle(isSelected ? .white : (isToday ? Theme.Colors.planner : .primary))

                Circle()
                    .fill(hasItems ? (isSelected ? Theme.Colors.planner : Theme.Colors.planner.opacity(0.55)) : .clear)
                    .frame(width: 4, height: 4)
            }
        }
        .buttonStyle(.plain)
    }

    private func shiftMonth(by value: Int) {
        guard let newMonth = calendar.date(byAdding: .month, value: value, to: visibleMonth) else { return }
        withAnimation(Motion.entrance) { visibleMonth = newMonth }
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.shortWeekdaySymbols
        let firstWeekday = calendar.firstWeekday - 1
        return Array(symbols[firstWeekday...] + symbols[..<firstWeekday])
    }

    /// Returns 42 slots (6 weeks) for the visible month, with nils for the
    /// leading/trailing blanks so the grid stays a fixed 7-column layout.
    private var daysInMonthGrid: [Date?] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: visibleMonth) else { return [] }
        let firstDay = monthInterval.start
        let weekdayOfFirst = calendar.component(.weekday, from: firstDay)
        let leadingBlanks = (weekdayOfFirst - calendar.firstWeekday + 7) % 7

        var days: [Date?] = Array(repeating: nil, count: leadingBlanks)
        var current = firstDay
        while current < monthInterval.end {
            days.append(current)
            current = calendar.date(byAdding: .day, value: 1, to: current) ?? monthInterval.end
        }
        while days.count % 7 != 0 {
            days.append(nil)
        }
        return days
    }
}

#Preview {
    MonthCalendarView(visibleMonth: .constant(.now), selectedDate: .constant(.now), daysWithItems: [Calendar.current.startOfDay(for: .now)])
        .padding()
}
