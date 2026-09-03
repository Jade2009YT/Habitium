//
//  DayTimelineView.swift
//  Habitium
//
//  Hour-by-hour visual day timeline — the feature that makes Structured
//  feel so much calmer than a plain to-do list. Events are laid out at
//  their real vertical position/height; tasks (which don't have a fixed
//  duration) stay in the checklist below, in DayDetailView.
//

import SwiftUI

struct DayTimelineView: View {
    let events: [PlannerEvent]
    var onDelete: (PlannerEvent) -> Void = { _ in }

    private let startHour = 6
    private let endHour = 23
    private let hourHeight: CGFloat = 34
    private let labelWidth: CGFloat = 40

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                VStack(spacing: 0) {
                    ForEach(startHour...endHour, id: \.self) { hour in
                        HStack(alignment: .top, spacing: 6) {
                            Text(hourLabel(hour))
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .frame(width: labelWidth, alignment: .trailing)
                            Rectangle().fill(Color(.separator)).frame(height: 1)
                        }
                        .frame(height: hourHeight, alignment: .top)
                    }
                }

                ForEach(events) { event in
                    eventBlock(event, availableWidth: geo.size.width - labelWidth - 10)
                        .offset(x: labelWidth + 8, y: yOffset(for: event.startDate))
                        .contextMenu {
                            Button(role: .destructive) { onDelete(event) } label: {
                                Label("Eliminar", systemImage: "trash")
                            }
                        }
                }
            }
        }
        .frame(height: CGFloat(endHour - startHour + 1) * hourHeight)
    }

    private func eventBlock(_ event: PlannerEvent, availableWidth: CGFloat) -> some View {
        let height = max(20, durationInHours(event) * hourHeight - 3)
        return VStack(alignment: .leading, spacing: 1) {
            Text(event.title).font(.caption.bold()).lineLimit(1)
            Text(event.startDate.formatted(date: .omitted, time: .shortened)).font(.caption2)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(width: max(0, availableWidth), height: height, alignment: .topLeading)
        .background(Theme.Colors.planner.opacity(0.16))
        .foregroundStyle(Theme.Colors.planner)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.Colors.planner.opacity(0.35), lineWidth: 1))
    }

    private func yOffset(for date: Date) -> CGFloat {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        let hour = Double(components.hour ?? startHour)
        let minute = Double(components.minute ?? 0)
        let hoursFromStart = max(0, hour - Double(startHour)) + minute / 60
        return CGFloat(hoursFromStart) * hourHeight
    }

    private func durationInHours(_ event: PlannerEvent) -> Double {
        max(0.4, event.endDate.timeIntervalSince(event.startDate) / 3600)
    }

    private func hourLabel(_ hour: Int) -> String {
        String(format: "%02d:00", hour)
    }
}

#Preview {
    DayTimelineView(events: [
        PlannerEvent(title: "Gimnasio", startDate: Calendar.current.date(bySettingHour: 16, minute: 30, second: 0, of: .now) ?? .now),
        PlannerEvent(title: "Llamada equipo", startDate: Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: .now) ?? .now, endDate: Calendar.current.date(bySettingHour: 11, minute: 0, second: 0, of: .now))
    ])
    .padding()
}
