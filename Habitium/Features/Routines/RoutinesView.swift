//
//  RoutinesView.swift
//  Habitium
//
//  Las rutinas encadenadas: "a las 7:15 me levanto, luego me ducho…".
//
//  Todo el cálculo está en RoutineSchedule y probado aparte; aquí solo se
//  pinta y se guarda. Lo único con enjundia de este archivo es que CADA
//  cambio —marcar un paso, mover la hora, añadir o quitar un paso—
//  reprograma las notificaciones ENTERAS de esa rutina, porque marcar un
//  paso mueve en cascada todos los que vienen detrás.
//

import SwiftData
import SwiftUI

struct RoutinesView: View {
    @Environment(\.modelContext) private var context

    @Query(sort: [SortDescriptor(\Routine.sortOrder), SortDescriptor(\Routine.startMinutes)])
    private var routines: [Routine]
    @Query private var steps: [RoutineStep]
    @Query private var logs: [RoutineLog]

    /// Se refresca solo cada minuto. Sin esto, "en 10 min" se quedaría
    /// congelado en lo que ponía al abrir la pantalla.
    @State private var now = Date.now
    private let tick = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    @State private var editing: Routine?

    var body: some View {
        NavigationStack {
            Group {
                if routines.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(routines) { routine in
                            Section {
                                ForEach(RoutineSchedule.entries(for: routine, steps: steps, logs: logs, now: now)) { entry in
                                    stepRow(routine: routine, entry: entry)
                                }
                            } header: {
                                header(for: routine)
                            } footer: {
                                Text(RoutineSchedule.summary(routine, steps: steps, logs: logs, now: now))
                                    .font(.footnote.weight(.semibold))
                            }
                        }
                    }
                }
            }
            .navigationTitle("Rutinas")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Rutina de mañana", systemImage: "sun.max") {
                            create(from: RoutineSchedule.morning)
                        }
                        Button("Antes de dormir", systemImage: "moon.stars") {
                            create(from: RoutineSchedule.night)
                        }
                        Divider()
                        Button("Rutina vacía", systemImage: "plus") { createEmpty() }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(item: $editing) { routine in
                RoutineEditor(routine: routine, steps: steps, logs: logs)
            }
            .onReceive(tick) { now = $0 }
            .task {
                NotificationScheduler.shared.requestAuthorizationIfNeeded()
                await rescheduleAll()
            }
        }
    }

    // MARK: - Piezas

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Sin rutinas todavía", systemImage: "repeat")
        } description: {
            Text("Una rutina es una cadena: te levantas, te duchas, te lavas los dientes, desayunas. Pones la hora de inicio y cuánto dura cada paso, y Habitium te va avisando. Si un día vas rápido o te quedas dormido, los avisos se mueven contigo.")
        } actions: {
            Button("Empezar con una de mañana") { create(from: RoutineSchedule.morning) }
                .buttonStyle(.borderedProminent)
            Button("Una de antes de dormir") { create(from: RoutineSchedule.night) }
        }
    }

    private func header(for routine: Routine) -> some View {
        let progress = RoutineSchedule.progress(routine, steps: steps, logs: logs, on: now)
        let streak = RoutineSchedule.streak(routine, steps: steps, logs: logs, today: now)

        return HStack(spacing: 8) {
            Text(routine.icon)
            Text(routine.name).font(.subheadline.bold())
            if streak > 0 {
                Text("🔥 \(streak)")
                    .font(.caption.bold())
                    .foregroundStyle(Theme.Colors.streak)
            }
            Spacer()
            Text("\(progress.done)/\(progress.total)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Button {
                editing = routine
            } label: {
                Image(systemName: "slider.horizontal.3")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .textCase(nil)          // sin esto, iOS grita el nombre en MAYÚSCULAS
        .opacity(RoutineSchedule.occurs(routine, on: now) ? 1 : 0.5)
    }

    private func stepRow(routine: Routine, entry: RoutineSchedule.Entry) -> some View {
        HStack(spacing: 12) {
            Button {
                toggle(routine: routine, entry: entry)
            } label: {
                Image(systemName: entry.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(entry.isDone ? Theme.Colors.nutrition : .secondary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)

            Text(entry.step.icon).font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.step.title)
                    .strikethrough(entry.isDone)
                    .foregroundStyle(entry.isDone ? .secondary : .primary)
                Text(subtitle(for: entry))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            if entry.isNow {
                Text("ahora")
                    .font(.caption2.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Theme.Colors.nutrition, in: Capsule())
                    .foregroundStyle(.white)
            }
        }
        .listRowBackground(entry.isCurrent && !entry.isDone ? Theme.Colors.nutrition.opacity(0.07) : nil)
        .animation(Motion.value, value: entry.isDone)
    }

    private func subtitle(for entry: RoutineSchedule.Entry) -> String {
        let hhmm = entry.time.formatted(date: .omitted, time: .shortened)
        if entry.isDone { return "hecho a las \(hhmm)" }
        // "recalculado" avisa de que esa hora no sale de la plantilla sino
        // de lo que ha pasado hoy. Sin decirlo, ver 7:37 donde la rutina
        // pone 7:40 parece un error de la app.
        let recalc = entry.isPlanned ? "" : " · recalculado"
        return "\(hhmm)\(recalc) · \(entry.step.durationMinutes) min"
    }

    // MARK: - Acciones

    private func toggle(routine: Routine, entry: RoutineSchedule.Entry) {
        if entry.isDone {
            // Se quitan TODAS las marcas de hoy de ese paso. Si se borrara
            // solo una, una marca duplicada de otro dispositivo lo dejaría
            // marcado y parecería que el botón no hace nada.
            let calendar = Calendar.current
            for log in logs where log.stepID == entry.step.id
                && calendar.isDate(log.date, inSameDayAs: now) {
                context.delete(log)
            }
        } else {
            context.insert(RoutineLog(routineID: routine.id, stepID: entry.step.id, date: .now))
        }
        try? context.save()

        Task { await reschedule(routine) }
    }

    private func create(from template: RoutineSchedule.Template) {
        let routine = Routine(
            name: template.name,
            icon: template.icon,
            startMinutes: template.startMinutes,
            daysOfWeek: template.daysOfWeek,
            sortOrder: routines.count
        )
        context.insert(routine)
        for (index, step) in template.steps.enumerated() {
            context.insert(RoutineStep(
                routineID: routine.id,
                title: step.title,
                icon: step.icon,
                durationMinutes: step.minutes,
                sortOrder: index
            ))
        }
        try? context.save()
        NotificationScheduler.shared.requestAuthorizationIfNeeded()
        Task { await reschedule(routine) }
    }

    private func createEmpty() {
        let routine = Routine(name: "Nueva rutina", icon: "🔁", sortOrder: routines.count)
        context.insert(routine)
        try? context.save()
        // Se abre sola: una rutina sin pasos no sirve de nada, así que lo
        // siguiente que hay que hacer es añadirlos.
        editing = routine
    }

    private func reschedule(_ routine: Routine) async {
        let ids = await NotificationScheduler.shared.rescheduleRoutine(routine, steps: steps, logs: logs)
        routine.notificationIdentifiers = ids
        try? context.save()
    }

    private func rescheduleAll() async {
        for routine in routines { await reschedule(routine) }
    }
}

// MARK: - Editor

/// Los ajustes de una rutina: hora, días, pasos y el interruptor de
/// avisos. Va en una hoja aparte porque es lo que se toca una vez al mes,
/// no cuatro veces cada mañana.
private struct RoutineEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Bindable var routine: Routine
    let steps: [RoutineStep]
    let logs: [RoutineLog]

    @State private var newTitle = ""
    @State private var newIcon = ""
    @State private var newMinutes = 10

    private var mySteps: [RoutineStep] { RoutineSchedule.steps(of: routine, from: steps) }

    /// La hora como Date, para el DatePicker, que no sabe de minutos desde
    /// medianoche.
    private var startBinding: Binding<Date> {
        Binding(
            get: {
                Calendar.current.startOfDay(for: .now)
                    .addingTimeInterval(TimeInterval(routine.startMinutes * 60))
            },
            set: { nuevo in
                let c = Calendar.current.dateComponents([.hour, .minute], from: nuevo)
                routine.startMinutes = (c.hour ?? 0) * 60 + (c.minute ?? 0)
                routine.updatedAt = .now
                save()
            }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nombre", text: $routine.name)
                    TextField("Icono", text: $routine.icon)
                    DatePicker("Empieza a las", selection: startBinding, displayedComponents: .hourAndMinute)
                } footer: {
                    Text("Duración total: \(RoutineSchedule.totalMinutes(routine, steps: steps)) minutos.")
                }

                Section("Días") {
                    dayPicker
                }

                Section {
                    Toggle("Avisarme de cada paso", isOn: $routine.notificationsEnabled)
                } footer: {
                    Text("Los avisos llegan aunque tengas el móvil bloqueado y Habitium cerrada. Se programan con \(NotificationScheduler.routineDaysAhead) días de antelación y se recalculan solos cada vez que marcas un paso.")
                }

                Section("Pasos") {
                    ForEach(mySteps) { step in
                        HStack {
                            Text(step.icon)
                            Text(step.title)
                            Spacer()
                            Text("\(step.durationMinutes) min")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onDelete(perform: deleteSteps)
                    .onMove(perform: moveSteps)

                    HStack {
                        TextField("Icono", text: $newIcon).frame(width: 44)
                        TextField("Nuevo paso", text: $newTitle)
                        Stepper("\(newMinutes) min", value: $newMinutes, in: 1...240, step: 5)
                            .fixedSize()
                        Button("Añadir", action: addStep)
                            .disabled(newTitle.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }

                Section {
                    Button("Eliminar la rutina", role: .destructive, action: deleteRoutine)
                }
            }
            .navigationTitle(routine.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") { dismiss() }
                }
                ToolbarItem(placement: .topBarLeading) { EditButton() }
            }
        }
    }

    private var dayPicker: some View {
        HStack(spacing: 6) {
            ForEach(Array(["L", "M", "X", "J", "V", "S", "D"].enumerated()), id: \.offset) { index, letra in
                let day = index + 1
                let on = routine.daysOfWeek.contains(day)
                Button {
                    if on { routine.daysOfWeek.removeAll { $0 == day } }
                    else { routine.daysOfWeek = (routine.daysOfWeek + [day]).sorted() }
                    routine.updatedAt = .now
                    save()
                } label: {
                    Text(letra)
                        .font(.footnote.bold())
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background(on ? Theme.Colors.nutrition : Color.secondary.opacity(0.12),
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .foregroundStyle(on ? .white : .secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Acciones

    private func addStep() {
        let titulo = newTitle.trimmingCharacters(in: .whitespaces)
        guard !titulo.isEmpty else { return }
        context.insert(RoutineStep(
            routineID: routine.id,
            title: titulo,
            icon: newIcon.isEmpty ? "✅" : newIcon,
            durationMinutes: newMinutes,
            sortOrder: mySteps.count
        ))
        newTitle = ""
        newIcon = ""
        save()
    }

    private func deleteSteps(at offsets: IndexSet) {
        let lista = mySteps
        for index in offsets {
            // Las marcas del paso también, o quedarían huérfanas contando
            // para el progreso de una rutina que ya no las tiene.
            let step = lista[index]
            for log in logs where log.stepID == step.id { context.delete(log) }
            context.delete(step)
        }
        renumber()
    }

    private func moveSteps(from source: IndexSet, to destination: Int) {
        var lista = mySteps
        lista.move(fromOffsets: source, toOffset: destination)
        for (index, step) in lista.enumerated() {
            step.sortOrder = index
            step.updatedAt = .now
        }
        save()
    }

    private func renumber() {
        for (index, step) in mySteps.enumerated() where step.sortOrder != index {
            step.sortOrder = index
            step.updatedAt = .now
        }
        save()
    }

    private func deleteRoutine() {
        let id = routine.id
        for step in mySteps { context.delete(step) }
        for log in logs where log.routineID == id { context.delete(log) }
        context.delete(routine)
        try? context.save()
        Task { await NotificationScheduler.shared.cancelRoutine(id) }
        dismiss()
    }

    private func save() {
        try? context.save()
        Task {
            let ids = await NotificationScheduler.shared.rescheduleRoutine(routine, steps: steps, logs: logs)
            routine.notificationIdentifiers = ids
            try? context.save()
        }
    }
}

#Preview {
    RoutinesView()
        .modelContainer(PersistenceController.preview().container)
}
