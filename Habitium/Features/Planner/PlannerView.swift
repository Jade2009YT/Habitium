//
//  PlannerView.swift
//  Habitium
//
//  Calendario y Recordatorios tab: monthly calendar + selected day's
//  tasks/events/note, backed by local notifications for reminders.
//

import SwiftUI

struct PlannerView: View {
    @Environment(AppDependencyContainer.self) private var container
    @State private var viewModel: PlannerViewModel?

    var body: some View {
        NavigationStack {
            Group {
                if let viewModel {
                    ScrollView {
                        VStack(spacing: Theme.Layout.sectionSpacing) {
                            QuickAddBar { text in
                                viewModel.addQuickEvent(from: text)
                            }
                            MonthCalendarView(
                                visibleMonth: Bindable(viewModel).visibleMonth,
                                selectedDate: Bindable(viewModel).selectedDate,
                                daysWithItems: viewModel.daysWithItems
                            )
                            DayDetailView(viewModel: viewModel)
                        }
                        .padding()
                    }
                } else {
                    ProgressView()
                }
            }
            .themedBackground()
            .navigationTitle("Calendario")
            .onAppear {
                if viewModel == nil {
                    viewModel = PlannerViewModel(container: container)
                }
            }
        }
    }
}

#Preview {
    PlannerView()
        .environment(AppDependencyContainer(modelContext: PersistenceController.preview().container.mainContext))
}
