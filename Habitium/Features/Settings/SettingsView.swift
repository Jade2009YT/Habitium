//
//  SettingsView.swift
//  Habitium
//
//  Reachable from HomeView's toolbar (gear icon). Not a 5th tab on
//  purpose — the nav spec is 4 feature tabs + Home dashboard.
//

import SwiftUI

struct SettingsView: View {
    @Environment(AppDependencyContainer.self) private var container
    @Environment(AppleSignInManager.self) private var authManager
    @Environment(SupabaseAuthManager.self) private var emailAuth
    @Environment(AppLockManager.self) private var lockManager
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: SettingsViewModel?

    var body: some View {
        NavigationStack {
            Group {
                if let viewModel {
                    Form {
                        accountSection
                        securitySection
                        goalsSection(viewModel)
                        adaptiveGoalSection(viewModel)
                        aiSection(viewModel)
                        notificationsSection(viewModel)
                        currencySection(viewModel)
                        subscriptionSection
                    }
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Ajustes")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") { dismiss() }
                }
            }
            .onAppear {
                if viewModel == nil {
                    viewModel = SettingsViewModel(container: container)
                }
            }
        }
    }

    private var accountSection: some View {
        Section {
            HStack {
                Image(systemName: "person.crop.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading) {
                    Text(accountDisplayName)
                        .font(.subheadline.bold())
                    Text(accountMethodDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            Button("Cerrar sesión", role: .destructive) {
                Task {
                    authManager.signOut()
                    await emailAuth.signOut()
                    dismiss()
                }
            }
        } header: {
            Text("Cuenta")
        } footer: {
            Text("Tus datos siguen en este iPhone al cerrar sesión — solo se te pedirá volver a entrar.")
        }
    }

    private var accountDisplayName: String {
        if let displayName = container.currentUserSettings().displayName, !displayName.isEmpty {
            return displayName
        }
        if case .signedIn(let email) = emailAuth.state, !email.isEmpty {
            return email
        }
        return container.currentUserSettings().email ?? "Tu cuenta"
    }

    private var accountMethodDescription: String {
        if emailAuth.isSignedIn { return "Correo y contraseña" }
        if authManager.isSignedIn { return "Sign in with Apple" }
        return ""
    }

    private var securitySection: some View {
        Section {
            Toggle("Bloqueo con \(lockManager.biometryDescription)", isOn: Bindable(lockManager).isEnabled)
        } header: {
            Text("Seguridad")
        } footer: {
            Text("Con esto activado, Habitium te pide \(lockManager.biometryDescription) cada vez que abres la app o vuelves de segundo plano — además de haber iniciado sesión. Tus fotos de comida y el resto de datos también se guardan cifrados en el dispositivo.")
        }
    }

    private func goalsSection(_ viewModel: SettingsViewModel) -> some View {
        Section("Metas nutricionales diarias") {
            LabeledContent("Calorías") {
                TextField("kcal", value: Bindable(viewModel).dailyCalorieGoal, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
            }
            LabeledContent("Proteína (g)") {
                TextField("g", value: Bindable(viewModel).proteinGoalGrams, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
            }
            LabeledContent("Carbohidratos (g)") {
                TextField("g", value: Bindable(viewModel).carbsGoalGrams, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
            }
            LabeledContent("Grasas (g)") {
                TextField("g", value: Bindable(viewModel).fatGoalGrams, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
            }
            Button("Guardar metas") { viewModel.saveGoals() }
        }
    }

    private func adaptiveGoalSection(_ viewModel: SettingsViewModel) -> some View {
        Section {
            Toggle("Meta adaptativa", isOn: Bindable(viewModel).adaptiveGoalEnabled)
                .onChange(of: viewModel.adaptiveGoalEnabled) { _, _ in viewModel.saveAdaptiveGoalSettings() }
            if viewModel.adaptiveGoalEnabled {
                LabeledContent("Ritmo semanal (kg)") {
                    TextField("-0.25", text: Bindable(viewModel).weeklyRateKgText)
                        .keyboardType(.numbersAndPunctuation)
                        .multilineTextAlignment(.trailing)
                        .onSubmit { viewModel.saveAdaptiveGoalSettings() }
                }
            }
        } header: {
            Text("Objetivo adaptativo")
        } footer: {
            Text("Negativo para perder peso, positivo para ganar, 0 para mantener. Habitium comparará tu peso real con lo que registras y te sugerirá ajustar la meta de calorías — necesitas al menos 10 días con pesajes y comidas registradas.")
        }
    }

    private func aiSection(_ viewModel: SettingsViewModel) -> some View {
        Section {
            Picker("Proveedor de IA", selection: Bindable(viewModel).preferredAIProvider) {
                ForEach(AIProviderKind.allCases) { provider in
                    Text(provider.displayName).tag(provider)
                }
            }
            .onChange(of: viewModel.preferredAIProvider) { _, _ in viewModel.savePreferences() }
        } header: {
            Text("Análisis de comidas")
        } footer: {
            Text("Requiere la API key correspondiente en Configuration/Secrets.xcconfig.")
        }
    }

    private func notificationsSection(_ viewModel: SettingsViewModel) -> some View {
        Section("Notificaciones") {
            Toggle("Recordatorio diario de comidas", isOn: Bindable(viewModel).mealReminderNotificationsEnabled)
                .onChange(of: viewModel.mealReminderNotificationsEnabled) { _, _ in viewModel.savePreferences() }

            if viewModel.mealReminderNotificationsEnabled {
                DatePicker(
                    "Hora del recordatorio",
                    selection: Binding(
                        get: {
                            Calendar.current.date(bySettingHour: viewModel.mealReminderHour, minute: viewModel.mealReminderMinute, second: 0, of: .now) ?? .now
                        },
                        set: { newDate in
                            let components = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                            viewModel.mealReminderHour = components.hour ?? 19
                            viewModel.mealReminderMinute = components.minute ?? 0
                            viewModel.savePreferences()
                        }
                    ),
                    displayedComponents: .hourAndMinute
                )
            }

            Toggle("Notificaciones de eventos", isOn: Bindable(viewModel).eventNotificationsEnabled)
                .onChange(of: viewModel.eventNotificationsEnabled) { _, _ in viewModel.savePreferences() }
        }
    }

    private func currencySection(_ viewModel: SettingsViewModel) -> some View {
        Section("Finanzas") {
            Picker("Moneda", selection: Bindable(viewModel).currencyCode) {
                Text("EUR (€)").tag("EUR")
                Text("USD ($)").tag("USD")
                Text("MXN ($)").tag("MXN")
                Text("GBP (£)").tag("GBP")
            }
            .onChange(of: viewModel.currencyCode) { _, _ in viewModel.saveCurrency() }
        }
    }

    private var subscriptionSection: some View {
        Section {
            SubscriptionStatusRow(subscriptionManager: container.subscriptionManager)
        } header: {
            Text("Habitium Pro")
        } footer: {
            Text("Uso personal: la app está completamente desbloqueada sin suscripción. Esta sección solo importa si algún día publicas Habitium y activas un producto real en App Store Connect.")
        }
    }
}

private struct SubscriptionStatusRow: View {
    var subscriptionManager: SubscriptionManager

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: subscriptionManager.isProActive ? "checkmark.seal.fill" : "seal")
                    .foregroundStyle(subscriptionManager.isProActive ? .green : .secondary)
                Text(statusText)
                Spacer()
            }

            if !subscriptionManager.isProActive {
                Button {
                    Task { await subscriptionManager.purchaseProMonthly() }
                } label: {
                    if subscriptionManager.isLoading {
                        ProgressView()
                    } else {
                        Text("Suscribirse — \(subscriptionManager.monthlyProduct?.displayPrice ?? "5,00 €")/mes")
                    }
                }
                .buttonStyle(.borderedProminent)

                Button {
                    Task { await subscriptionManager.purchaseLifetime() }
                } label: {
                    Text("Comprar de por vida — \(subscriptionManager.lifetimeProduct?.displayPrice ?? "100,00 €") (pago único)")
                }
                .buttonStyle(.bordered)
            }

            Button("Restaurar compras") {
                Task { await subscriptionManager.restorePurchases() }
            }
            .font(.caption)

            if let error = subscriptionManager.errorMessage {
                Text(error).font(.caption).foregroundStyle(Theme.Colors.danger)
            }
        }
    }

    private var statusText: String {
        if subscriptionManager.isLifetimeOwned { return "Pro activo — de por vida" }
        if subscriptionManager.isSubscriptionActive { return "Pro activo — mensual" }
        return "Sin suscripción activa"
    }
}

#Preview {
    SettingsView()
        .environment(AppDependencyContainer(modelContext: PersistenceController.preview().container.mainContext))
        .environment(AppleSignInManager())
        .environment(SupabaseAuthManager())
        .environment(AppLockManager())
}
