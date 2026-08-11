//
//  FoodTrackerView.swift
//  Habitium
//
//  Nutrition e IA tab: today's calorie/macro summary plus the list of
//  logged meals, with a button to add a new one (photo/text/manual).
//

import SwiftUI

struct FoodTrackerView: View {
    @Environment(AppDependencyContainer.self) private var container
    @Environment(DeepLinkCoordinator.self) private var deepLinkCoordinator
    @State private var viewModel: FoodTrackerViewModel?
    @State private var showingAddMeal = false

    var body: some View {
        NavigationStack {
            Group {
                if let viewModel {
                    List {
                        Section {
                            CalorieProgressView(progress: viewModel.progress)
                                .listRowInsets(EdgeInsets())
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)

                            if viewModel.loggingStreak > 0 {
                                Label("\(viewModel.loggingStreak) días seguidos registrando", systemImage: "flame.fill")
                                    .font(.caption.bold())
                                    .foregroundStyle(Theme.Colors.nutrition)
                                    .listRowBackground(Color.clear)
                            }

                            WeightTrendCard(entries: viewModel.weightEntries) { kg in
                                viewModel.logWeight(kg: kg)
                            }
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)

                            if let suggestion = viewModel.adaptiveSuggestion {
                                AdaptiveGoalCard(suggestion: suggestion) {
                                    viewModel.applyAdaptiveSuggestion()
                                }
                                .listRowInsets(EdgeInsets())
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                            }
                        }

                        if !viewModel.recentEntries.isEmpty {
                            Section("Repetir comida") {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 10) {
                                        ForEach(viewModel.recentEntries) { entry in
                                            Button {
                                                viewModel.repeatEntry(entry)
                                            } label: {
                                                VStack(alignment: .leading, spacing: 4) {
                                                    Text(entry.name).font(.caption.bold()).lineLimit(1)
                                                    Text("\(Int(entry.calories)) kcal").font(.caption2).foregroundStyle(.secondary)
                                                }
                                                .padding(10)
                                                .frame(width: 130, alignment: .leading)
                                                .background(Theme.Colors.cardBackground)
                                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                            }
                        }

                        Section("Comidas de hoy") {
                            if viewModel.todayEntries.isEmpty {
                                Text("Aún no has registrado ninguna comida hoy.")
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(viewModel.todayEntries) { entry in
                                    mealRow(entry)
                                        .swipeActions {
                                            Button(role: .destructive) {
                                                viewModel.deleteEntry(entry)
                                            } label: {
                                                Label("Eliminar", systemImage: "trash")
                                            }
                                        }
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                } else {
                    ProgressView()
                }
            }
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

    private func mealRow(_ entry: FoodEntry) -> some View {
        HStack {
            Image(systemName: (MealType(rawValue: entry.mealType) ?? .snack).symbolName)
                .foregroundStyle(Theme.Colors.nutrition)
            VStack(alignment: .leading) {
                Text(entry.name).font(.subheadline.bold())
                Text("\(Int(entry.calories)) kcal · P\(Int(entry.proteinGrams)) C\(Int(entry.carbsGrams)) G\(Int(entry.fatGrams))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

#Preview {
    FoodTrackerView()
        .environment(AppDependencyContainer(modelContext: PersistenceController.preview().container.mainContext))
        .environment(DeepLinkCoordinator())
}
