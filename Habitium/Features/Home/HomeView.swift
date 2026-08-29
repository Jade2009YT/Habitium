//
//  HomeView.swift
//  Habitium
//
//  El panel del día: saludo, calorías restantes, foco de hoy, hábitos,
//  medicación, próximos eventos y presupuesto — cada uno con un atajo a
//  su pantalla.
//
//  Nota que se repite por todo el archivo y conviene no olvidar: las
//  tarjetas que navegan son NavigationLink/Button con contenido de SOLO
//  LECTURA. Un control interactivo anidado dentro de la etiqueta de un
//  NavigationLink no recibe sus propias pulsaciones — se las come la
//  etiqueta. Por eso aquí se muestra el estado y se interactúa en la
//  pantalla de destino. La única excepción es "Foco de hoy", que no
//  navega a ningún sitio y por eso sí puede llevar botones dentro.
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
                        greeting
                        caloriesCard(viewModel)

                        if !viewModel.focusTasks.isEmpty {
                            focusCard(viewModel)
                        }
                        if !viewModel.habitStatuses.isEmpty {
                            habitsCard(viewModel)
                        }
                        medicationCard(viewModel)
                        upcomingCard(viewModel)
                        budgetCard(viewModel)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 24)
                }
            }
            .background(Theme.Colors.screenBackground)
            .navigationTitle("Habitium")
            .navigationBarTitleDisplayMode(.inline)
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

    // MARK: - Saludo

    private var greeting: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .kerning(0.5)
            Text(greetingText)
                .font(.system(size: 26, weight: .bold, design: .rounded))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
    }

    private var greetingText: String {
        let name = container.currentUserSettings().displayName?
            .split(separator: " ").first.map(String.init)
        let hour = Calendar.current.component(.hour, from: .now)
        let salutation = switch hour {
        case 6..<13: "Buenos días"
        case 13..<21: "Buenas tardes"
        default: "Buenas noches"
        }
        return name.map { "\(salutation), \($0)" } ?? salutation
    }

    // MARK: - Calorías (tarjeta destacada, con anillo)

    private func caloriesCard(_ viewModel: HomeViewModel) -> some View {
        let progress = viewModel.nutritionProgress

        return Button {
            selectedTab = .nutrition
        } label: {
            VStack(spacing: 16) {
                CardHeader(title: "Nutrición de hoy", symbol: "flame.fill", color: Theme.Colors.nutrition) {
                    DisclosureChevron()
                }

                HStack(spacing: 20) {
                    ZStack {
                        // rawProgress, no progress: el limitado nunca
                        // pasaría de 1 y el anillo no se pondría rojo.
                        RingProgress(progress: progress.rawProgress, color: Theme.Colors.nutrition)
                        VStack(spacing: 0) {
                            Text("\(Int(progress.remainingCalories))")
                                .font(Theme.Fonts.metric)
                                .contentTransition(.numericText())
                            Text("kcal restantes")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        macroRow("Proteína", progress.consumedMacros.proteinGrams, progress.goalMacros.proteinGrams)
                        macroRow("Carbos", progress.consumedMacros.carbsGrams, progress.goalMacros.carbsGrams)
                        macroRow("Grasas", progress.consumedMacros.fatGrams, progress.goalMacros.fatGrams)
                    }
                }

                Text("\(Int(progress.consumedCalories)) de \(Int(progress.goalCalories)) kcal consumidas")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .cardStyle()
        }
        .pressable()
    }

    private func macroRow(_ name: String, _ got: Double, _ target: Double) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(name).font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(got))\(target > 0 ? "/\(Int(target))" : "") g")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            ProgressBar(
                value: target > 0 ? got / target : 0,
                color: Theme.Colors.nutrition,
                height: 5
            )
        }
    }

    // MARK: - Foco de hoy

    private func focusCard(_ viewModel: HomeViewModel) -> some View {
        VStack(alignment: .leading, spacing: Theme.Layout.rowSpacing) {
            CardHeader(title: "Foco de hoy", symbol: "star.fill", color: Theme.Colors.streak)

            // Esta tarjeta NO navega, así que aquí sí funcionan los
            // botones: puedes tachar una prioridad sin salir de Inicio.
            ForEach(viewModel.focusTasks) { task in
                Button {
                    viewModel.toggleFocusTask(task)
                } label: {
                    HStack(spacing: 11) {
                        Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(task.isCompleted ? Theme.Colors.streak : .secondary)
                        Text(task.title)
                            .font(Theme.Fonts.rowTitle)
                            .strikethrough(task.isCompleted)
                            .foregroundStyle(task.isCompleted ? .secondary : .primary)
                        Spacer(minLength: 0)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    // MARK: - Hábitos

    private func habitsCard(_ viewModel: HomeViewModel) -> some View {
        let met = viewModel.habitStatuses.filter(\.isGoalMetToday).count
        let total = viewModel.habitStatuses.count

        return NavigationLink {
            HabitsView()
        } label: {
            VStack(alignment: .leading, spacing: Theme.Layout.rowSpacing) {
                CardHeader(title: "Hábitos", symbol: "repeat.circle.fill", color: Theme.Colors.habits) {
                    Text("\(met)/\(total)")
                        .font(.subheadline.weight(.bold).monospacedDigit())
                        .foregroundStyle(Theme.Colors.habits)
                    DisclosureChevron()
                }

                ProgressBar(
                    value: total > 0 ? Double(met) / Double(total) : 0,
                    color: Theme.Colors.habits
                )

                ForEach(viewModel.habitStatuses.prefix(4)) { status in
                    HStack(spacing: 11) {
                        Image(systemName: status.isGoalMetToday ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(status.isGoalMetToday ? Theme.Colors.habits : .secondary)
                        Text(status.name).font(.subheadline)
                        Spacer(minLength: 0)
                        if status.streak > 0 {
                            StreakBadge(days: status.streak)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle()
        }
        .pressable()
    }

    // MARK: - Medicación

    private func medicationCard(_ viewModel: HomeViewModel) -> some View {
        NavigationLink {
            MedicationView()
        } label: {
            VStack(alignment: .leading, spacing: Theme.Layout.rowSpacing) {
                CardHeader(title: "Medicación", symbol: "pills.fill", color: Theme.Colors.medication) {
                    DisclosureChevron()
                }

                if viewModel.pendingMedicationDoses.isEmpty {
                    EmptyHint(symbol: "checkmark.circle", message: "Sin tomas pendientes ahora mismo.")
                } else {
                    ForEach(viewModel.pendingMedicationDoses.prefix(3)) { dose in
                        HStack(spacing: 11) {
                            Circle()
                                .fill(Theme.Colors.medication)
                                .frame(width: 7, height: 7)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(dose.medicationName).font(Theme.Fonts.rowTitle)
                                if let dosage = dose.dosage {
                                    Text(dosage).font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            Spacer(minLength: 0)
                            Text(dose.scheduledDate.formatted(date: .omitted, time: .shortened))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle()
        }
        .pressable()
    }

    // MARK: - Próximos

    private func upcomingCard(_ viewModel: HomeViewModel) -> some View {
        Button {
            selectedTab = .planner
        } label: {
            VStack(alignment: .leading, spacing: Theme.Layout.rowSpacing) {
                CardHeader(title: "Próximo", symbol: "calendar", color: Theme.Colors.planner) {
                    DisclosureChevron()
                }

                if viewModel.upcomingItems.isEmpty {
                    EmptyHint(symbol: "checkmark.circle", message: "Nada por ahora. ¡Todo al día!")
                } else {
                    ForEach(viewModel.upcomingItems) { item in
                        HStack(spacing: 11) {
                            Image(systemName: item.isTask ? "checklist" : "calendar.circle.fill")
                                .foregroundStyle(Theme.Colors.planner)
                                .frame(width: 20)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.title).font(Theme.Fonts.rowTitle)
                                Text(item.date.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle()
        }
        .pressable()
    }

    // MARK: - Presupuesto

    private func budgetCard(_ viewModel: HomeViewModel) -> some View {
        let finance = viewModel.financeOverview

        return Button {
            selectedTab = .finance
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                CardHeader(title: "Disponible este mes", symbol: "banknote.fill", color: Theme.Colors.finance) {
                    DisclosureChevron()
                }

                Text(finance.availableToSpend, format: .currency(code: finance.currencyCode))
                    .font(Theme.Fonts.metric)
                    .foregroundStyle(finance.isOverBudget ? Theme.Colors.danger : .primary)
                    .contentTransition(.numericText())

                ProgressBar(value: finance.rawSpentProgress, color: Theme.Colors.finance)

                Text("de \(finance.monthlyBudget, format: .currency(code: finance.currencyCode)) presupuestados")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle()
        }
        .pressable()
    }
}

#Preview {
    HomeView(selectedTab: .constant(.home))
        .environment(AppDependencyContainer(modelContext: PersistenceController.preview().container.mainContext))
}
