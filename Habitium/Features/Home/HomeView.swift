//
//  HomeView.swift
//  Habitium
//
//  Unified dashboard: remaining calories today, next 3 events/tasks, and
//  available budget — with quick links into the relevant tab.
//

import SwiftUI

struct HomeView: View {
    @Environment(AppDependencyContainer.self) private var container
    @State private var viewModel: HomeViewModel?
    @State private var showingSettings = false
    @Binding var selectedTab: AppTab

    var body: some View {
        NavigationStack {
            ScrollView {
                if let viewModel {
                    VStack(spacing: Theme.Layout.sectionSpacing) {
                        if !viewModel.focusTasks.isEmpty {
                            focusCard(viewModel)
                        }
                        medicationCard(viewModel)
                        caloriesCard(viewModel)
                        upcomingCard(viewModel)
                        budgetCard(viewModel)
                    }
                    .padding()
                }
            }
            .navigationTitle("Habitium")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                    }
                }
            }
            .sheet(isPresented: $showingSettings, onDismiss: { viewModel?.refresh() }) {
                SettingsView()
            }
            .onAppear {
                if viewModel == nil {
                    viewModel = HomeViewModel(container: container)
                } else {
                    viewModel?.refresh()
                }
            }
        }
    }

    private func focusCard(_ viewModel: HomeViewModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Foco de hoy", systemImage: "star.fill")
                .font(.headline)
                .foregroundStyle(.yellow)

            ForEach(viewModel.focusTasks) { task in
                Button {
                    viewModel.toggleFocusTask(task)
                } label: {
                    HStack {
                        Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(task.isCompleted ? Theme.Colors.planner : .secondary)
                        Text(task.title)
                            .strikethrough(task.isCompleted)
                            .foregroundStyle(task.isCompleted ? .secondary : .primary)
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private func medicationCard(_ viewModel: HomeViewModel) -> some View {
        NavigationLink {
            MedicationView()
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                Label("Medicación", systemImage: "pills.fill")
                    .font(.headline)
                    .foregroundStyle(.purple)

                if viewModel.pendingMedicationDoses.isEmpty {
                    Text("Sin tomas pendientes ahora mismo.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    // Read-only preview — tap the whole card to open
                    // Medicación and mark doses taken/skipped there.
                    // (A nested Button here wouldn't receive its own taps:
                    // the NavigationLink label swallows the gesture.)
                    ForEach(viewModel.pendingMedicationDoses.prefix(3)) { dose in
                        HStack {
                            Image(systemName: "pills.fill")
                                .foregroundStyle(.purple)
                            Text(dose.medicationName).font(.subheadline)
                            Spacer()
                            Text(dose.scheduledDate.formatted(date: .omitted, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle()
        }
        .buttonStyle(.plain)
    }

    private func caloriesCard(_ viewModel: HomeViewModel) -> some View {
        Button {
            selectedTab = .nutrition
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Label("Calorías restantes hoy", systemImage: "flame.fill")
                    .font(.headline)
                    .foregroundStyle(Theme.Colors.nutrition)

                Text("\(Int(viewModel.nutritionProgress.remainingCalories)) kcal")
                    .font(.system(size: 34, weight: .bold, design: .rounded))

                ProgressView(value: viewModel.nutritionProgress.progress)
                    .tint(Theme.Colors.nutrition)

                Text("\(Int(viewModel.nutritionProgress.consumedCalories)) / \(Int(viewModel.nutritionProgress.goalCalories)) kcal consumidas")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle()
        }
        .buttonStyle(.plain)
    }

    private func upcomingCard(_ viewModel: HomeViewModel) -> some View {
        Button {
            selectedTab = .planner
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                Label("Próximos eventos y tareas", systemImage: "calendar")
                    .font(.headline)
                    .foregroundStyle(Theme.Colors.planner)

                if viewModel.upcomingItems.isEmpty {
                    Text("Nada por ahora. ¡Todo al día!")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.upcomingItems) { item in
                        HStack {
                            Image(systemName: item.isTask ? "checklist" : "calendar.circle.fill")
                                .foregroundStyle(Theme.Colors.planner)
                            VStack(alignment: .leading) {
                                Text(item.title).font(.subheadline)
                                Text(item.date.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle()
        }
        .buttonStyle(.plain)
    }

    private func budgetCard(_ viewModel: HomeViewModel) -> some View {
        Button {
            selectedTab = .finance
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Label("Disponible para gastar", systemImage: "banknote.fill")
                    .font(.headline)
                    .foregroundStyle(Theme.Colors.finance)

                Text(viewModel.financeOverview.availableToSpend, format: .currency(code: viewModel.financeOverview.currencyCode))
                    .font(.system(size: 34, weight: .bold, design: .rounded))

                ProgressView(value: viewModel.financeOverview.spentProgress)
                    .tint(viewModel.financeOverview.isOverBudget ? Theme.Colors.danger : Theme.Colors.finance)

                Text("Presupuesto mensual: \(viewModel.financeOverview.monthlyBudget, format: .currency(code: viewModel.financeOverview.currencyCode))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle()
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    HomeView(selectedTab: .constant(.home))
        .environment(AppDependencyContainer(modelContext: PersistenceController.preview().container.mainContext))
}
