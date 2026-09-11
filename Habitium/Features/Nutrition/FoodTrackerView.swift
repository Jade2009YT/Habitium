//
//  FoodTrackerView.swift
//  Habitium
//
//  Nutrición: el resumen del día arriba, y debajo el peso, la sugerencia
//  de objetivo, las comidas repetibles y lo registrado hoy.
//
//  Va en tarjetas dentro de un ScrollView y no en un `List`, igual que
//  Inicio, Hábitos y Medicación. No es solo estética: con `List` cada
//  tarjeta iba metida en una fila con `listRowInsets(EdgeInsets())` y
//  `listRowBackground(.clear)` para disimular la fila, que es pelear
//  contra el control en vez de usarlo. Lo que se pierde son las
//  `swipeActions` —solo existen en List—, así que eliminar pasa a ser
//  "mantener pulsado", que es lo que ya hacían Hábitos y Medicación.
//

import SwiftUI

struct FoodTrackerView: View {
    @Environment(AppDependencyContainer.self) private var container
    @Environment(DeepLinkCoordinator.self) private var deepLinkCoordinator
    @State private var viewModel: FoodTrackerViewModel?
    @State private var showingAddMeal = false
    @State private var viewingPhotoEntry: FoodEntry?

    var body: some View {
        NavigationStack {
            ScrollView {
                if let viewModel {
                    VStack(spacing: Theme.Layout.sectionSpacing) {
                        CalorieProgressView(progress: viewModel.progress)
                            .appearIn(0)

                        if viewModel.loggingStreak > 0 {
                            streakCard(viewModel).appearIn(1)
                        }

                        if let suggestion = viewModel.adaptiveSuggestion {
                            AdaptiveGoalCard(suggestion: suggestion) {
                                viewModel.applyAdaptiveSuggestion()
                            }
                            .appearIn(2)
                        }

                        WeightTrendCard(entries: viewModel.weightEntries) { kg in
                            viewModel.logWeight(kg: kg)
                        }
                        .appearIn(3)

                        if !viewModel.recentEntries.isEmpty {
                            repeatCard(viewModel).appearIn(4)
                        }

                        mealsCard(viewModel).appearIn(5)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 24)
                } else {
                    ProgressView().padding(.top, 60)
                }
            }
            .themedBackground()
            .navigationTitle("Nutrición")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAddMeal = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                }
            }
            .sheet(isPresented: $showingAddMeal, onDismiss: { viewModel?.refresh() }) {
                if let viewModel {
                    AddMealView(viewModel: viewModel)
                }
            }
            .sheet(item: $viewingPhotoEntry) { entry in
                if let viewModel {
                    MealPhotoViewerSheet(entry: entry, viewModel: viewModel)
                }
            }
            .onAppear {
                if viewModel == nil {
                    viewModel = FoodTrackerViewModel(container: container)
                } else {
                    viewModel?.refresh()
                }
            }
            .onChange(of: deepLinkCoordinator.pendingLink) { _, newValue in
                guard newValue == .scanFood else { return }
                showingAddMeal = true
                deepLinkCoordinator.consume()
            }
        }
    }

    // MARK: - Racha de registro

    /// Tarjeta propia y no una línea suelta: la racha de registrar es lo
    /// que sostiene el hábito de apuntar la comida, que es la parte que
    /// todo el mundo abandona la segunda semana.
    private func streakCard(_ viewModel: FoodTrackerViewModel) -> some View {
        HStack(spacing: 12) {
            IconBadge(symbol: "flame.fill", color: Theme.Colors.streak)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(viewModel.loggingStreak) días seguidos registrando")
                    .font(Theme.Fonts.rowTitle)
                Text("No rompas la racha hoy.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    // MARK: - Repetir comida

    private func repeatCard(_ viewModel: FoodTrackerViewModel) -> some View {
        VStack(alignment: .leading, spacing: Theme.Layout.rowSpacing) {
            CardHeader(title: "Repetir comida", symbol: "arrow.counterclockwise", color: Theme.Colors.nutrition)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(viewModel.recentEntries) { entry in
                        Button {
                            viewModel.repeatEntry(entry)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.name)
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(1)
                                Text("\(Int(entry.calories)) kcal")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(10)
                            .frame(width: 132, alignment: .leading)
                            .background(
                                Theme.Colors.nutrition.opacity(0.10),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                // El scroll horizontal se sale del padding de la tarjeta
                // y vuelve a entrar: así las fichas se cortan en el borde
                // en vez de quedar con un margen muerto a la derecha.
                .padding(.horizontal, Theme.Layout.cardPadding)
            }
            .padding(.horizontal, -Theme.Layout.cardPadding)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    // MARK: - Comidas de hoy

    private func mealsCard(_ viewModel: FoodTrackerViewModel) -> some View {
        VStack(alignment: .leading, spacing: Theme.Layout.rowSpacing) {
            CardHeader(title: "Comidas de hoy", symbol: "fork.knife", color: Theme.Colors.nutrition) {
                if !viewModel.todayEntries.isEmpty {
                    Text("\(viewModel.todayEntries.count)")
                        .font(Theme.Fonts.rowTitle)
                        .foregroundStyle(.secondary)
                }
            }

            if viewModel.todayEntries.isEmpty {
                EmptyHint(symbol: "plus.circle", message: "Aún no has registrado nada hoy. Añade una comida con el +.")
            } else {
                ForEach(Array(viewModel.todayEntries.enumerated()), id: \.element.id) { index, entry in
                    if index > 0 { Divider() }
                    mealRow(entry, viewModel: viewModel)
                }

                Text("Mantén pulsada una comida para eliminarla.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private func mealRow(_ entry: FoodEntry, viewModel: FoodTrackerViewModel) -> some View {
        let meal = MealType(rawValue: entry.mealType) ?? .snack

        return HStack(spacing: 11) {
            IconBadge(symbol: meal.symbolName, color: Theme.Colors.nutrition, size: 26)

            VStack(alignment: .leading, spacing: 1) {
                Text(entry.name)
                    .font(Theme.Fonts.rowTitle)
                    .lineLimit(1)
                Text("P\(Int(entry.proteinGrams)) · C\(Int(entry.carbsGrams)) · G\(Int(entry.fatGrams))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if entry.imageData != nil {
                Button {
                    viewingPhotoEntry = entry
                } label: {
                    Image(systemName: "photo.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Text("\(Int(entry.calories))")
                .font(Theme.Fonts.rowTitle)
                .monospacedDigit()
            Text("kcal")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .contextMenu {
            Button(role: .destructive) {
                viewModel.deleteEntry(entry)
            } label: {
                Label("Eliminar", systemImage: "trash")
            }
        }
    }
}

#Preview {
    FoodTrackerView()
        .environment(AppDependencyContainer(modelContext: PersistenceController.preview().container.mainContext))
        .environment(DeepLinkCoordinator())
}
