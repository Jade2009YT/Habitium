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
    @Environment(LocalAccessManager.self) private var localAccess
    @Environment(AppLockManager.self) private var lockManager
    @Environment(AppearanceStore.self) private var appearance
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: SettingsViewModel?
    @State private var selectedAccent: AccentTheme = AccentThemeStore.current
    @State private var apiKeyField: String = ""
    @State private var savedKeyConfirmation = false
    @State private var keychainFailed = false
    @State private var watchPermissionState: WatchPermissionState = .idle

    enum WatchPermissionState { case idle, asking, granted, denied }

    var body: some View {
        NavigationStack {
            Group {
                if let viewModel {
                    Form {
                        accountSection
                        backgroundSection
                        appearanceSection
                        securitySection
                        goalsSection(viewModel)
                        adaptiveGoalSection(viewModel)
                        aiSection(viewModel)
                        watchSection(viewModel)
                        notificationsSection(viewModel)
                        currencySection(viewModel)
                        subscriptionSection
                    }
                    // Ajustes sí se tiñe con el fondo elegido: es la
                    // pantalla donde lo estás eligiendo, y ver el cambio
                    // debajo de tu dedo es media explicación. Las hojas
                    // de meter datos (añadir comida, gasto…) se quedan
                    // con el gris del sistema a propósito: ahí lo que
                    // importa es el formulario, no el color.
                    .scrollContentBackground(.hidden)
                } else {
                    ProgressView()
                }
            }
            .themedBackground()
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
                apiKeyField = AIKeyStore.userKey(for: viewModel?.preferredAIProvider ?? .openAI) ?? ""
            }
        }
    }

    /// El color de fondo de la app.
    ///
    /// Va PRIMERO y sin candados, al revés que los temas de acento de
    /// abajo. Es deliberado: el fondo es lo que decide si la app te
    /// resulta cómoda de mirar, y condicionar eso a jugar al pase sería
    /// cobrarle la comodidad a quien solo quiere usar la app. Lo que se
    /// gana con el pase son los acentos, que son un capricho.
    private var backgroundSection: some View {
        Section {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 12)], spacing: 14) {
                ForEach(BackgroundTheme.allCases) { theme in
                    Button {
                        guard appearance.background != theme else { return }
                        withAnimation(.easeInOut(duration: 0.25)) {
                            appearance.background = theme
                        }
                        Haptics.tap()
                    } label: {
                        BackgroundSwatch(theme: theme, isSelected: appearance.background == theme)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 6)

            Text(appearance.background.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text("Fondo")
        } footer: {
            Text("Cambia al instante. Es una preferencia de este dispositivo, así que puedes tener el iPhone en oscuro y la web en claro.")
        }
    }

    /// Los temas que se ganan en el pase de temporada. Los que aún no
    /// tienes se ven bloqueados en vez de esconderse: saber qué hay más
    /// adelante es justo lo que hace que apetezca seguir.
    private var appearanceSection: some View {
        let unlocked = container.progressionRepository.profile().unlockedRewardIDs
        let available = SeasonPass.availableAccents(unlockedRewardIDs: unlocked)

        return Section {
            ForEach(AccentTheme.allCases) { theme in
                let isAvailable = available.contains(theme)
                Button {
                    guard isAvailable else { return }
                    AccentThemeStore.set(theme)
                    selectedAccent = theme
                } label: {
                    HStack(spacing: 12) {
                        Circle()
                            .fill(theme.color)
                            .frame(width: 22, height: 22)
                            .opacity(isAvailable ? 1 : 0.3)
                        Text(theme.displayName)
                            .foregroundStyle(isAvailable ? .primary : .secondary)
                        Spacer()
                        if !isAvailable {
                            Image(systemName: "lock.fill")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        } else if selectedAccent == theme {
                            Image(systemName: "checkmark")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(theme.color)
                        }
                    }
                }
                .disabled(!isAvailable)
            }
        } header: {
            Text("Aspecto")
        } footer: {
            Text("Los temas se desbloquean subiendo de nivel en el pase de temporada.")
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
            Button(localAccess.isUsingLocalOnly ? "Crear cuenta o iniciar sesión" : "Cerrar sesión", role: localAccess.isUsingLocalOnly ? nil : .destructive) {
                Task {
                    authManager.signOut()
                    await emailAuth.signOut()
                    localAccess.exitLocalOnly()
                    dismiss()
                }
            }
        } header: {
            Text("Cuenta")
        } footer: {
            Text(localAccess.isUsingLocalOnly
                 ? "Estás usando Habitium sin cuenta: todo se guarda solo en este iPhone. Crear una cuenta de email te permitiría tener los mismos datos en otros dispositivos. Nada de lo que ya has guardado se pierde."
                 : "Tus datos siguen en este iPhone al cerrar sesión — solo se te pedirá volver a entrar.")
        }
    }

    private var accountDisplayName: String {
        if let displayName = container.currentUserSettings().displayName, !displayName.isEmpty {
            return displayName
        }
        if case .signedIn(let email) = emailAuth.state, !email.isEmpty {
            return email
        }
        if let email = container.currentUserSettings().email, !email.isEmpty {
            return email
        }
        return localAccess.isUsingLocalOnly ? "Habitium en local" : "Tu cuenta"
    }

    private var accountMethodDescription: String {
        if emailAuth.isSignedIn { return "Correo y contraseña" }
        if authManager.isSignedIn { return "Sign in with Apple" }
        if localAccess.isUsingLocalOnly { return "Sin cuenta · solo en este iPhone" }
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

    /// Proveedor de IA y la clave de cada uno.
    ///
    /// Antes la clave solo podía venir del archivo de compilación, o sea
    /// de quien construye la app. Eso dejaba sin análisis de comidas a
    /// cualquiera que se la instale — y sin manera de arreglarlo desde
    /// dentro. Ahora cada uno pone la suya y se guarda en el Llavero.
    private func aiSection(_ viewModel: SettingsViewModel) -> some View {
        let provider = viewModel.preferredAIProvider
        let source = AIKeyStore.source(for: provider)

        return Section {
            Picker("Servicio", selection: Bindable(viewModel).preferredAIProvider) {
                ForEach(AIProviderKind.allCases) { provider in
                    Text(provider.displayName).tag(provider)
                }
            }
            .onChange(of: viewModel.preferredAIProvider) { _, _ in
                viewModel.savePreferences()
                apiKeyField = AIKeyStore.userKey(for: viewModel.preferredAIProvider) ?? ""
                savedKeyConfirmation = false
            }

            HStack {
                Image(systemName: source == .none ? "exclamationmark.triangle.fill" : "checkmark.seal.fill")
                    .foregroundStyle(source == .none ? Theme.Colors.danger : Theme.Colors.nutrition)
                Text(source.explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            SecureField("Pega aquí tu clave", text: $apiKeyField)
                .textContentType(.password)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onSubmit { saveAPIKey(for: provider) }

            HStack {
                Button(savedKeyConfirmation ? "Guardada ✓" : "Guardar clave") {
                    saveAPIKey(for: provider)
                }
                .disabled(apiKeyField.trimmingCharacters(in: .whitespaces).isEmpty)

                Spacer()

                if AIKeyStore.userKey(for: provider) != nil {
                    Button("Quitar", role: .destructive) {
                        AIKeyStore.setUserKey(nil, for: provider)
                        apiKeyField = ""
                        savedKeyConfirmation = false
                        Haptics.tap()
                    }
                }
            }

            if keychainFailed {
                Label("El Llavero rechazó guardarla. Desbloquea el iPhone e inténtalo otra vez.", systemImage: "xmark.octagon.fill")
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.danger)
            }

            if let url = AIKeyStore.helpURL(for: provider) {
                Link("¿De dónde saco la clave?", destination: url)
                    .font(.caption)
            }
        } header: {
            Text("Análisis de comidas por foto")
        } footer: {
            Text("Tu clave se guarda cifrada en este iPhone y NO se sincroniza: ponla en cada dispositivo donde la quieras. No viaja a la nube a propósito — una clave en una base de datos acaba en una copia de seguridad, y la factura la pagarías tú.")
        }
    }

    private func saveAPIKey(for provider: AIProviderKind) {
        let guardada = AIKeyStore.setUserKey(apiKeyField, for: provider)
        savedKeyConfirmation = guardada
        keychainFailed = !guardada
        if guardada { Haptics.success() } else { Haptics.warning() }
    }

    /// Apple Watch.
    ///
    /// El interruptor no es decorativo: al encenderlo pide de verdad los
    /// permisos que hacen falta (HealthKit y notificaciones), porque un
    /// "sí" que no pide nada deja la función apagada sin decirlo. Y solo
    /// se enseña en iPhone, no en iPad.
    private func watchSection(_ viewModel: SettingsViewModel) -> some View {
        Section {
            Toggle("Tengo un Apple Watch", isOn: Bindable(viewModel).appleWatchEnabled)
                .onChange(of: viewModel.appleWatchEnabled) { _, isOn in
                    viewModel.savePreferences()
                    guard isOn else { return }
                    Task { await requestWatchPermissions() }
                }

            if viewModel.appleWatchEnabled {
                switch watchPermissionState {
                case .idle:
                    EmptyView()
                case .asking:
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("Pidiendo permisos…").font(.caption).foregroundStyle(.secondary)
                    }
                case .granted:
                    Label("Permisos concedidos. Ya puede leer tus datos del Watch.", systemImage: "checkmark.seal.fill")
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.nutrition)
                case .denied:
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Faltan permisos", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(Theme.Colors.danger)
                        Text("Ve a Ajustes del iPhone → Salud → Acceso de apps → Habitium y actívalos. Desde aquí ya no se puede volver a preguntar: iOS solo deja pedirlo una vez.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("Apple Watch")
        } footer: {
            Text("Con el Watch, las calorías gastadas y los entrenamientos salen de tus pulsaciones y tu movimiento reales, en vez de estimarse. La IA sigue haciendo falta para reconocer la comida de una foto: son dos cosas distintas que se complementan.")
        }
    }

    private func requestWatchPermissions() async {
        watchPermissionState = .asking
        let concedido = await WatchHealthAccess.requestPermissions()
        watchPermissionState = concedido ? .granted : .denied
        if concedido { Haptics.success() } else { Haptics.warning() }
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
        .environment(LocalAccessManager())
        .environment(AppLockManager())
}
