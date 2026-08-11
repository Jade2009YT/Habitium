//
//  DayDetailView.swift
//  Habitium
//
//  Shows the selected day's tasks, events and note, with quick actions to
//  add a new task/event and to toggle/delete existing ones.
//

import SwiftUI

struct DayDetailView: View {
    var viewModel: PlannerViewModel
    @State private var showingAddTask = false
    @State private var showingAddEvent = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Layout.sectionSpacing) {
            HStack {
                Text(viewModel.selectedDate.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .font(.headline)
                Spacer()
                Menu {
                    Button("Nueva tarea", systemImage: "checklist") { showingAddTask = true }
                    Button("Nuevo evento", systemImage: "calendar.badge.plus") { showingAddEvent = true }
                } label: {
                    Image(systemName: "plus.circle.fill")
                }
            }

            if viewModel.eventsForDay.isEmpty && viewModel.tasksForDay.isEmpty {
                Text("No hay eventos ni tareas para este día.")
                    .foregroundStyle(.secondary)
            } else {
                if !viewModel.eventsForDay.isEmpty {
                    DayTimelineView(events: viewModel.eventsForDay) { event in
                        viewModel.deleteEvent(event)
                    }
                }
                if !viewModel.tasksForDay.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(viewModel.tasksForDay) { task in
                            taskRow(task)
                        }
                    }
                }
            }

            noteSection
        }
        .cardStyle()
        .sheet(isPresented: $showingAddTask) {
            AddTaskSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $showingAddEvent) {
            AddEventSheet(viewModel: viewModel)
        }
    }

    private func taskRow(_ task: PlannerTask) -> some View {
        HStack {
            Button {
                viewModel.toggleTask(task)
            } label: {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(task.isCompleted ? Theme.Colors.planner : .secondary)
            }
            .buttonStyle(.plain)

            Text(task.title)
                .strikethrough(task.isCompleted)
                .foregroundStyle(task.isCompleted ? .secondary : .primary)
            Spacer()
            Button(role: .destructive) {
                viewModel.deleteTask(task)
            } label: {
                Image(systemName: "trash").foregroundStyle(.secondary)
            }
        }
    }

    private var noteSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Nota del día").font(.subheadline.bold())
            TextField("Escribe una nota…", text: Bindable(viewModel).noteText, axis: .vertical)
                .lineLimit(2...4)
                .textFieldStyle(.roundedBorder)
                .onSubmit { viewModel.saveNote() }
                .onChange(of: viewModel.noteText) { _, _ in viewModel.saveNote() }
        }
    }
}
