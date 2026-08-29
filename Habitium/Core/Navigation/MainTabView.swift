//
//  MainTabView.swift
//  Habitium
//
//  Root navigation: a TabView with the Home dashboard plus the three
//  feature modules (Nutrition, Planner, Finance).
//

import SwiftUI

enum AppTab: Hashable {
    case home
    case nutrition
    case planner
    case finance
}

struct MainTabView: View {
    @State private var selectedTab: AppTab = .home
    @Environment(DeepLinkCoordinator.self) private var deepLinkCoordinator

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView(selectedTab: $selectedTab)
                .tabItem { Label("Inicio", systemImage: "house.fill") }
                .tag(AppTab.home)

            FoodTrackerView()
                .tabItem { Label("Nutrición", systemImage: "fork.knife.circle.fill") }
                .tag(AppTab.nutrition)

            PlannerView()
                .tabItem { Label("Calendario", systemImage: "calendar") }
                .tag(AppTab.planner)

            FinanceView()
                .tabItem { Label("Finanzas", systemImage: "chart.pie.fill") }
                .tag(AppTab.finance)
        }
        // El verde de la marca en la pestaña activa, en vez del azul por
        // defecto de iOS — es lo primero que se ve y lo que hace que la
        // app parezca suya y no una plantilla.
        .tint(Theme.Colors.nutrition)
        .onChange(of: deepLinkCoordinator.pendingLink) { _, newValue in
            switch newValue {
            case .scanFood: selectedTab = .nutrition
            case .addExpense: selectedTab = .finance
            case nil: break
            }
        }
    }
}

#Preview {
    MainTabView()
        .environment(AppDependencyContainer(modelContext: PersistenceController.preview().container.mainContext))
        .environment(DeepLinkCoordinator())
}
