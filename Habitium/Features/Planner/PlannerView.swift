//
//  PlannerView.swift
//  Habitium
//
//  Calendario: alta rápida escribiendo, el mes, y el detalle del día
//  seleccionado. Las tres piezas entran escalonadas como en el resto de
//  la app.
//

import SwiftUI

struct PlannerView: View {
    @Environment(AppDependencyContainer.self) private var container
    @State private var viewModel: PlannerViewModel?

    var body: some View {
        NavigationStack {
            ScrollView {
                if let viewModel {
                    VStack(spacing: Theme.Layout.sectionSpacing) {
                        QuickAddBar { text in
                            viewModel.addQuickEvent(from: text)
                        }
                        .appearIn(0)

                        MonthCalendarView(
                            visibleMonth: Bindable(viewModel).visibleMonth,
                            selectedDate: Bindable(viewModel).selectedDate,
                            daysWithItems: viewModel.daysWithItems
                        )
                        .appearIn(1)

                        DayDetailView(viewModel: viewModel)
                            .appearIn(2)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 24)
                } else {
                    ProgressView().padding(.top, 60)
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
