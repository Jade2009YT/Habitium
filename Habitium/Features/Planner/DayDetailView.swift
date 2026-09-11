//
//  DayDetailView.swift
//  Habitium
//
//  El día seleccionado: sus eventos, sus tareas y la nota.
//
//  Dos decisiones de diseño que van juntas. La primera: la papelera de
//  cada tarea desaparece y eliminar pasa a ser "mantener pulsado", como
//  en el resto de la app — tres botones por fila (marcar, destacar,
//  borrar) hacían que la fila pareciera un panel de control, y el de
//  borrar estaba pegado al de destacar, que es un vecino peligroso.
//
//  La segunda: la estrella solo se pinta llena cuando la tarea es foco
//  del día. Antes se veía siempre, gris, y no había forma de saber si eso
//  significaba "no es foco" o "no se puede marcar".
//

import SwiftUI

struct DayDetailView: View {
    var viewModel: PlannerViewModel
    @State private var showingAddTask = false
    @State private var showingAddEvent = false

    private var pendientes: Int {
        viewModel.tasksForDay.filter { !$0.isCompleted }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Layout.rowSpacing) {
            CardHeader(
                title: viewModel.selectedDate.formatted(.dateTime.weekday(.wide).day().month(.wide)),
                symbol: "calendar.day.timeline.left",
                color: Theme.Colors.planner
            ) {
                Menu {
                    Button("Nueva tarea", systemImage: "checklist") { showingAddTask = true }
                    Button("Nuevo evento", systemImage: "calendar.badge.plus") { showingAddEvent = true }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Theme.Colors.planner)
                }
            }

            if viewModel.eventsForDay.isEmpty && viewModel.tasksForDay.isEmpty {
                EmptyHint(symbol: "calendar", message: "Nada para este día. Añade algo con el + o escríbelo arriba.")
            } else {
                if !viewModel.eventsForDay.isEmpty {
                    DayTimelineView(events: viewModel.eventsForDay) { event in
                        viewModel.deleteEvent(event)
                    }
                }

                if !viewModel.tasksForDay.isEmpty {
                    if !viewModel.eventsForDay.isEmpty { Divider() }

                    HStack(spacing: 6) {
                        Text("Tareas")
                            .font(Theme.Fonts.cardTitle)
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                            .kerning(0.4)
                        Spacer(minLength: 8)
                        Text(pendientes == 0 ? "todas hechas" : "\(pendientes) pendiente\(pendientes == 1 ? "" : "s")")
                            .font(.caption2)
                            .foregroundStyle(pendientes == 0 ? Theme.Colors.nutrition : .tertiary)
                    }

                    ForEach(Array(viewModel.tasksForDay.enumerated()), id: \.element.id) { index, task in
                        if index > 0 { Divider() }
                        taskRow(task)
                    }

                    Text("Mantén pulsada una tarea para eliminarla.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Divider()
            noteSection
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
        .sheet(isPresented: $showingAddTask) {
            AddTaskSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $showingAddEvent) {
            AddEventSheet(viewModel: viewModel)
        }
    }

    private func taskRow(_ task: PlannerTask) -> some View {
        HStack(spacing: 11) {
            Button {
                viewModel.toggleTask(task)
            } label: {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(task.isCompleted ? Theme.Colors.planner : .secondary)
            }
            .buttonStyle(.plain)

            Text(task.title)
                .font(Theme.Fonts.rowTitle)
                .strikethrough(task.isCompleted)
                .foregroundStyle(task.isCompleted ? .secondary : .primary)

            Spacer(minLength: 8)

            Button {
                viewModel.toggleFocus(task)
            } label: {
                Image(systemName: task.isFocus ? "star.fill" : "star")
                    .font(.caption)
                    .foregroundStyle(task.isFocus ? Theme.Colors.streak : .tertiary)
            }
            .buttonStyle(.plain)
        }
        .contextMenu {
            Button {
                viewModel.toggleFocus(task)
            } label: {
                Label(task.isFocus ? "Quitar del foco" : "Marcar como foco del día", systemImage: "star")
            }
            Button(role: .destructive) {
                viewModel.deleteTask(task)
            } label: {
                Label("Eliminar", systemImage: "trash")
            }
        }
    }

    private var noteSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                IconBadge(symbol: "note.text", color: Theme.Colors.planner, size: 24)
                Text("Nota del día")
                    .font(Theme.Fonts.cardTitle)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .kerning(0.4)
            }
            TextField("Escribe una nota…", text: Bindable(viewModel).noteText, axis: .vertical)
                .font(.subheadline)
                .lineLimit(2...4)
                .padding(10)
                .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .onSubmit { viewModel.saveNote() }
                .onChange(of: viewModel.noteText) { _, _ in viewModel.saveNote() }
        }
    }
}
