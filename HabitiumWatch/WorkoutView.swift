//
//  WorkoutView.swift
//  HabitiumWatch
//
//  Start a workout, see reps counted live from the wrist's own motion,
//  tap "Nueva serie" between sets, "Finalizar" sends everything logged
//  to the iPhone (WatchConnectivityBridge.sendLoggedWorkoutSets) to be
//  saved for real in Habitium's SwiftData store.
//

import SwiftUI

struct WorkoutView: View {
    @Environment(WatchConnectivityBridge.self) private var bridge
    @Environment(\.dismiss) private var dismiss

    @State private var sessionManager = WorkoutSessionManager()
    @State private var repCounter = RepCounter()
    @State private var exerciseName = "Ejercicio"
    @State private var loggedSets: [LoggedWorkoutSet] = []

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                switch sessionManager.state {
                case .idle, .error:
                    idleView
                case .requestingAuthorization:
                    ProgressView("Pidiendo permiso...")
                case .active:
                    activeView
                case .ended:
                    endedView
                }
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle("Entrenar")
    }

    private var idleView: some View {
        VStack(spacing: 10) {
            TextField("Ejercicio", text: $exerciseName)
            Button("Empezar entrenamiento") {
                sessionManager.start()
            }
            .buttonStyle(.borderedProminent)

            if case .error(let message) = sessionManager.state {
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
        .onChange(of: sessionManager.state) { _, newValue in
            if newValue == .active { repCounter.start() }
        }
    }

    private var activeView: some View {
        VStack(spacing: 10) {
            Text(exerciseName).font(.headline)

            Text("\(repCounter.repCount)")
                .font(.system(size: 56, weight: .bold, design: .rounded))
                .foregroundStyle(.purple)
            Text("repeticiones").font(.caption2).foregroundStyle(.secondary)

            Button("Nueva serie") {
                logCurrentSet()
            }
            .buttonStyle(.borderedProminent)
            .tint(.purple)
            .disabled(repCounter.repCount == 0)

            if !loggedSets.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(loggedSets) { set in
                        Text("Serie: \(set.reps) reps").font(.caption2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button("Finalizar", role: .destructive) {
                finish()
            }
            .font(.caption)
        }
    }

    private var endedView: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.largeTitle)
                .foregroundStyle(.green)
            Text("Entrenamiento enviado al iPhone").font(.caption).multilineTextAlignment(.center)
            Button("Cerrar") { dismiss() }
        }
    }

    private func logCurrentSet() {
        guard repCounter.repCount > 0 else { return }
        loggedSets.append(LoggedWorkoutSet(exerciseName: exerciseName, reps: repCounter.repCount, date: .now))
        repCounter.reset()
    }

    private func finish() {
        // Whatever's left uncommitted in the current set still counts.
        if repCounter.repCount > 0 { logCurrentSet() }
        repCounter.stop()
        sessionManager.end()
        if !loggedSets.isEmpty {
            bridge.sendLoggedWorkoutSets(loggedSets)
        }
    }
}

#Preview {
    NavigationStack {
        WorkoutView()
            .environment(WatchConnectivityBridge.shared)
    }
}
