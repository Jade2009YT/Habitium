//
//  RoutineSchedule.swift
//  Habitium
//
//  El cálculo del horario de una rutina encadenada. Sin SwiftUI, sin
//  SwiftData por medio y sin `Date.now` escondido dentro: todo entra por
//  parámetro para poder probarlo (HabitiumTests/RoutineScheduleTests).
//
//  Es el gemelo exacto de web/routines.js. Que existan dos copias no es
//  un descuido: iOS calcula en Swift y la web en JavaScript, pero LA
//  MISMA CUENTA tiene que ver lo mismo en los dos sitios, así que las dos
//  siguen la misma regla y los dos juegos de pruebas usan los mismos
//  casos. Si alguna vez hay que cambiar la regla, se cambia en los dos.
//
//  La regla, en una frase: **el reloj lo pone el último paso marcado.**
//
//    · Los pasos ya marcados enseñan la hora REAL a la que se marcaron.
//    · Los que quedan se encadenan a partir del último marcado, no de la
//      hora teórica.
//    · Si no hay ninguno marcado, se encadenan desde la hora de inicio de
//      la rutina — que es lo que hace que el primer aviso suene.
//

import Foundation

enum RoutineSchedule {

    /// Cuánto cerca tiene que estar un paso para que valga decir "ahora".
    /// Un cuarto de hora a cada lado: lo justo para que sirva de aviso sin
    /// que la rutina de noche se pase el día diciendo que le toca.
    static let nowWindowMinutes = 15

    /// Pasado esto, un paso sin marcar ya no es "vas tarde", es "hoy no ha
    /// salido". Decir "vas 392 minutos tarde" a las dos de la tarde no
    /// ayuda a nadie.
    static let abandonedAfterMinutes = 120

    /// Una fila del horario: el paso, a qué hora toca y en qué estado está.
    struct Entry: Identifiable, Equatable {
        var id: UUID { step.id }
        let step: RoutineStep
        let time: Date
        let isDone: Bool
        /// El primer paso sin marcar. Solo uno puede serlo.
        let isCurrent: Bool
        /// `isCurrent` Y con su momento cerca de verdad. NO es lo mismo:
        /// el primer paso sin marcar de la rutina de noche también lo es
        /// a las dos de la tarde, y etiquetarlo "ahora" sería mentira.
        let isNow: Bool
        /// `true` si la hora sale de la plantilla; `false` si sale de lo
        /// que ha pasado hoy de verdad (es decir, se ha recalculado).
        let isPlanned: Bool

        static func == (a: Entry, b: Entry) -> Bool {
            a.step.id == b.step.id && a.time == b.time && a.isDone == b.isDone
        }
    }

    // MARK: - Piezas sueltas

    /// Lunes = 1 … domingo = 7, como ISO. `Calendar.component(.weekday:)`
    /// devuelve domingo = 1, que es la fuente de la mitad de los errores
    /// de calendario.
    static func isoWeekday(of date: Date, calendar: Calendar = .current) -> Int {
        let apple = calendar.component(.weekday, from: date)   // dom = 1 … sáb = 7
        return apple == 1 ? 7 : apple - 1
    }

    /// ¿Toca hoy? Una lista de días vacía significa "todos".
    static func occurs(_ routine: Routine, on date: Date, calendar: Calendar = .current) -> Bool {
        routine.daysOfWeek.isEmpty || routine.daysOfWeek.contains(isoWeekday(of: date, calendar: calendar))
    }

    /// El instante en que arranca la rutina en un día dado.
    ///
    /// Se parte de medianoche y se SUMAN minutos, en vez de pedirle al
    /// calendario una hora concreta. Suena a lo mismo y no lo es: el día
    /// que cambia la hora, las 2:30 pueden no existir (marzo) o existir dos
    /// veces (octubre), y `date(bySettingHour:)` tiene que inventarse una.
    static func start(of routine: Routine, on date: Date, calendar: Calendar = .current) -> Date {
        let midnight = calendar.startOfDay(for: date)
        return midnight.addingTimeInterval(TimeInterval(routine.startMinutes * 60))
    }

    static func steps(of routine: Routine, from all: [RoutineStep]) -> [RoutineStep] {
        all.filter { $0.routineID == routine.id }
            .sorted { ($0.sortOrder, $0.id.uuidString) < ($1.sortOrder, $1.id.uuidString) }
    }

    /// Los pasos marcados ese día → instante en que se marcaron.
    ///
    /// Si un paso aparece dos veces (dos dispositivos sincronizando) vale
    /// el PRIMERO: es el que refleja cuándo se hizo de verdad.
    static func completions(
        of routine: Routine,
        from logs: [RoutineLog],
        on date: Date,
        calendar: Calendar = .current
    ) -> [UUID: Date] {
        var map: [UUID: Date] = [:]
        for log in logs where log.routineID == routine.id {
            guard calendar.isDate(log.date, inSameDayAs: date) else { continue }
            if let previous = map[log.stepID], previous <= log.date { continue }
            map[log.stepID] = log.date
        }
        return map
    }

    // MARK: - El cálculo

    static func entries(
        for routine: Routine,
        steps allSteps: [RoutineStep],
        logs: [RoutineLog],
        now: Date = .now,
        on date: Date? = nil,
        calendar: Calendar = .current
    ) -> [Entry] {
        let day = date ?? now
        let ordered = steps(of: routine, from: allSteps)
        let done = completions(of: routine, from: logs, on: day, calendar: calendar)

        var clock = start(of: routine, on: day, calendar: calendar)
        var anyMarked = false
        var pendingSeen = false
        var result: [Entry] = []

        for step in ordered {
            if let at = done[step.id] {
                // Un paso hecho manda sobre el reloj: lo que venga después
                // se cuenta desde que se marcó DE VERDAD, no desde lo
                // previsto.
                anyMarked = true
                clock = at.addingTimeInterval(TimeInterval(step.durationMinutes * 60))
                result.append(Entry(step: step, time: at, isDone: true,
                                    isCurrent: false, isNow: false, isPlanned: false))
                continue
            }

            let time = clock
            clock = clock.addingTimeInterval(TimeInterval(step.durationMinutes * 60))

            let isCurrent = !pendingSeen
            pendingSeen = true
            let isNow = isCurrent && abs(time.timeIntervalSince(now)) <= Double(nowWindowMinutes * 60)

            result.append(Entry(step: step, time: time, isDone: false,
                                isCurrent: isCurrent, isNow: isNow, isPlanned: !anyMarked))
        }

        return result
    }

    // MARK: - Estado

    /// Una rutina SIN pasos no cuenta como completa: si contara, saldría
    /// premiada nada más crearla.
    static func isComplete(
        _ routine: Routine, steps allSteps: [RoutineStep], logs: [RoutineLog],
        on date: Date = .now, calendar: Calendar = .current
    ) -> Bool {
        let ordered = steps(of: routine, from: allSteps)
        guard !ordered.isEmpty else { return false }
        let done = completions(of: routine, from: logs, on: date, calendar: calendar)
        return ordered.allSatisfy { done[$0.id] != nil }
    }

    static func progress(
        _ routine: Routine, steps allSteps: [RoutineStep], logs: [RoutineLog],
        on date: Date = .now, calendar: Calendar = .current
    ) -> (done: Int, total: Int) {
        let ordered = steps(of: routine, from: allSteps)
        let marked = completions(of: routine, from: logs, on: date, calendar: calendar)
        return (ordered.filter { marked[$0.id] != nil }.count, ordered.count)
    }

    /// Días seguidos terminando la rutina entera, contando hacia atrás.
    ///
    /// Los días que la rutina NO toca (el fin de semana en una rutina de
    /// L-V) se SALTAN, no la rompen. Castigarte el sábado por una rutina
    /// de días de colegio es el fallo que tienen la mitad de las apps de
    /// hábitos.
    ///
    /// Y hoy no cuenta en contra: si aún no la has terminado pero el día
    /// no ha acabado, la racha es la de ayer.
    static func streak(
        _ routine: Routine, steps allSteps: [RoutineStep], logs: [RoutineLog],
        today: Date = .now, calendar: Calendar = .current, maxDays: Int = 400
    ) -> Int {
        var days = 0
        var cursor = calendar.startOfDay(for: today)

        if occurs(routine, on: cursor, calendar: calendar),
           !isComplete(routine, steps: allSteps, logs: logs, on: cursor, calendar: calendar) {
            cursor = calendar.date(byAdding: .day, value: -1, to: cursor) ?? cursor
        }

        for _ in 0..<maxDays {
            if !occurs(routine, on: cursor, calendar: calendar) {
                cursor = calendar.date(byAdding: .day, value: -1, to: cursor) ?? cursor
                continue                       // día libre: ni suma ni rompe
            }
            guard isComplete(routine, steps: allSteps, logs: logs, on: cursor, calendar: calendar) else { break }
            days += 1
            cursor = calendar.date(byAdding: .day, value: -1, to: cursor) ?? cursor
        }
        return days
    }

    // MARK: - Texto

    static func timeText(_ minutes: Int) -> String {
        let m = max(0, minutes)
        return "\(m / 60 % 24):\(String(format: "%02d", m % 60))"
    }

    /// Lo único que la mayoría de la gente va a leer de la tarjeta.
    static func summary(
        _ routine: Routine, steps allSteps: [RoutineStep], logs: [RoutineLog],
        now: Date = .now, calendar: Calendar = .current
    ) -> String {
        guard occurs(routine, on: now, calendar: calendar) else { return "Hoy no toca" }

        let ordered = steps(of: routine, from: allSteps)
        guard !ordered.isEmpty else { return "Añade pasos para empezar" }
        if isComplete(routine, steps: allSteps, logs: logs, on: now, calendar: calendar) { return "Hecha ✓" }

        let list = entries(for: routine, steps: allSteps, logs: logs, now: now, calendar: calendar)
        guard let current = list.first(where: { $0.isCurrent }) else { return "Hecha ✓" }

        let minutes = Int((current.time.timeIntervalSince(now) / 60).rounded())

        // Un atraso de horas no es un atraso: es que hoy no ha salido.
        if minutes < -abandonedAfterMinutes {
            let p = progress(routine, steps: allSteps, logs: logs, on: now, calendar: calendar)
            return p.done == 0 ? "Hoy no ha salido" : "Se quedó en \(p.done) de \(p.total)"
        }

        if minutes > 60 { return "Empieza a las \(timeText(routine.startMinutes))" }
        if minutes > 1 { return "\(current.step.title), en \(minutes) min" }
        if minutes >= -1 { return "Ahora: \(current.step.title)" }
        return "\(current.step.title) — vas \(abs(minutes)) min tarde"
    }

    static func totalMinutes(_ routine: Routine, steps allSteps: [RoutineStep]) -> Int {
        steps(of: routine, from: allSteps).reduce(0) { $0 + $1.durationMinutes }
    }

    // MARK: - Plantillas
    //
    // Una rutina vacía no le dice nada a nadie: lo primero que se ofrece
    // es algo que ya funciona y se puede retocar.

    struct Template {
        let name: String
        let icon: String
        let startMinutes: Int
        let daysOfWeek: [Int]
        let steps: [(title: String, icon: String, minutes: Int)]
    }

    static let morning = Template(
        name: "Mañanas", icon: "☀️", startMinutes: 7 * 60 + 15, daysOfWeek: [1, 2, 3, 4, 5],
        steps: [
            ("Levantarme", "⏰", 10),
            ("Ducharme", "🚿", 15),
            ("Lavarme los dientes", "🪥", 5),
            ("Desayunar", "🥣", 20),
        ]
    )

    static let night = Template(
        name: "Antes de dormir", icon: "🌙", startMinutes: 22 * 60 + 30, daysOfWeek: [1, 2, 3, 4, 5, 6, 7],
        steps: [
            ("Dejar el móvil cargando lejos", "📵", 5),
            ("Lavarme los dientes", "🪥", 5),
            ("Preparar la mochila de mañana", "🎒", 10),
            ("Leer un rato", "📖", 20),
        ]
    )
}
