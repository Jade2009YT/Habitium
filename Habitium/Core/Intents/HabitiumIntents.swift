//
//  HabitiumIntents.swift
//  Habitium
//
//  Lo que Habitium sabe hacer desde fuera de Habitium: Atajos, Siri,
//  Spotlight, el botón de Acción y los widgets de la pantalla de bloqueo.
//
//  ── Por qué esto existe: el gasto de Apple Pay ─────────────────────
//
//  La idea era "que cuando pague con Apple Pay se abra la app para
//  apuntar el gasto". Hay que ser claro sobre lo que se puede y lo que
//  no, porque es fácil prometer de más:
//
//  · NINGUNA app de terceros puede leer tus pagos. No hay API para eso.
//    El importe, el comercio y la tarjeta no salen de Wallet, ni en iOS
//    ni en Android. Eso no es una limitación de Habitium.
//  · La automatización de Atajos con disparador "Transacción" SÍ da el
//    importe, pero solo funciona con Apple Card y Apple Cash, que en
//    España no existen.
//  · Lo que SÍ funciona aquí: una automatización personal de Atajos
//    disparada "Al cerrar la app Wallet". Cuando pagas con el doble clic
//    del botón lateral, se abre Wallet; al terminar, se cierra — y ahí
//    salta el atajo. No trae el importe (nadie puede), pero te lo
//    pregunta en el momento justo, que es cuando te acuerdas.
//
//  Así que el trabajo de este archivo es que apuntar el gasto cueste UN
//  gesto: una acción de Atajos que acepta texto libre ("4,20 bocadillo")
//  y lo guarda. El cómo montar la automatización está en el README.
//
//  El texto se interpreta con las mismas reglas que la web
//  (web/finanzas-ia.js → interpretarGasto), y a propósito SIN IA: en la
//  cola del súper con mala cobertura, un atajo que depende de que
//  conteste un servidor falla justo cuando hace falta.
//

import AppIntents
import Foundation
import SwiftData

// MARK: - Apuntar un gasto

struct AddExpenseIntent: AppIntent {
    static var title: LocalizedStringResource = "Apuntar un gasto"
    static var description = IntentDescription(
        "Apunta un gasto en Habitium escribiéndolo tal cual: «4,20 bocadillo».",
        categoryName: "Finanzas"
    )

    /// No abre la app: el sentido de esto es apuntar el gasto y seguir a
    /// lo tuyo. Abrir Habitium para escribir cuatro euros es justo lo que
    /// hace que nadie apunte nada.
    static var openAppWhenRun: Bool = false

    @Parameter(
        title: "Gasto",
        description: "El importe y, si quieres, en qué. Por ejemplo: 4,20 bocadillo.",
        requestValueDialog: "¿Cuánto te has gastado?"
    )
    var texto: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let gasto = ExpenseParser.parse(texto) else {
            return .result(dialog: "No he encontrado el importe. Prueba con algo como «4,20 bocadillo».")
        }

        let contexto = PersistenceController.shared.container.mainContext
        contexto.insert(Transaction(
            amount: gasto.importe,
            type: .expense,
            category: gasto.categoria,
            note: gasto.nota.isEmpty ? nil : gasto.nota,
            date: .now
        ))
        try? contexto.save()

        let cuanto = gasto.importe.formatted(.currency(code: "EUR"))
        return .result(dialog: gasto.nota.isEmpty
            ? "Apuntado: \(cuanto)."
            : "Apuntado: \(cuanto) en \(gasto.nota).")
    }
}

// MARK: - Marcar el paso de una rutina

struct NextRoutineStepIntent: AppIntent {
    static var title: LocalizedStringResource = "Marcar el siguiente paso de mi rutina"
    static var description = IntentDescription(
        "Marca el paso que tienes en marcha ahora mismo, sin abrir la app.",
        categoryName: "Rutinas"
    )
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let contexto = PersistenceController.shared.container.mainContext
        let rutinas = (try? contexto.fetch(FetchDescriptor<Routine>())) ?? []
        let pasos = (try? contexto.fetch(FetchDescriptor<RoutineStep>())) ?? []
        let marcas = (try? contexto.fetch(FetchDescriptor<RoutineLog>())) ?? []

        // La rutina cuyo paso en marcha esté MÁS CERCA de ahora. Con dos
        // rutinas (mañana y noche) las dos tienen un "siguiente paso"
        // todo el día; la buena es la que toca de verdad.
        let candidatos = rutinas
            .filter { $0.isActive && RoutineSchedule.occurs($0, on: .now) }
            .compactMap { rutina -> (Routine, RoutineSchedule.Entry)? in
                let filas = RoutineSchedule.entries(for: rutina, steps: pasos, logs: marcas)
                guard let actual = filas.first(where: { $0.isCurrent }) else { return nil }
                return (rutina, actual)
            }
            .min { abs($0.1.time.timeIntervalSinceNow) < abs($1.1.time.timeIntervalSinceNow) }

        guard let (rutina, entrada) = candidatos else {
            return .result(dialog: "No tienes ningún paso pendiente ahora mismo.")
        }

        contexto.insert(RoutineLog(routineID: rutina.id, stepID: entrada.step.id, date: .now))
        try? contexto.save()

        // Marcar mueve en cascada todos los pasos siguientes, así que hay
        // que reprogramar los avisos enteros de esa rutina.
        let nuevas = (try? contexto.fetch(FetchDescriptor<RoutineLog>())) ?? []
        let ids = await NotificationScheduler.shared.rescheduleRoutine(rutina, steps: pasos, logs: nuevas)
        rutina.notificationIdentifiers = ids
        try? contexto.save()

        let restantes = RoutineSchedule.entries(for: rutina, steps: pasos, logs: nuevas)
            .filter { !$0.isDone }

        if let siguiente = restantes.first {
            return .result(dialog: "\(entrada.step.title), hecho. Ahora toca \(siguiente.step.title).")
        }
        return .result(dialog: "\(entrada.step.title), hecho. Rutina terminada.")
    }
}

// MARK: - Cuánto me queda este mes

struct RemainingBudgetIntent: AppIntent {
    static var title: LocalizedStringResource = "¿Cuánto me queda este mes?"
    static var description = IntentDescription(
        "Dice lo que te queda de presupuesto y a cuánto sale por día.",
        categoryName: "Finanzas"
    )
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let contexto = PersistenceController.shared.container.mainContext
        let ajustes = (try? contexto.fetch(FetchDescriptor<BudgetSettings>()))?.first
        let limite = ajustes?.monthlyBudget ?? 0
        guard limite > 0 else {
            return .result(dialog: "Todavía no tienes un presupuesto puesto. Ábrelo en Habitium → Finanzas.")
        }

        let calendario = Calendar.current
        let inicio = calendario.dateInterval(of: .month, for: .now)?.start ?? .now
        let movimientos = (try? contexto.fetch(FetchDescriptor<Transaction>())) ?? []
        let gastado = movimientos
            .filter { $0.date >= inicio && $0.type == TransactionType.expense.rawValue }
            .reduce(0) { $0 + $1.amount }

        let queda = max(0, limite - gastado)
        let diasDelMes = calendario.range(of: .day, in: .month, for: .now)?.count ?? 30
        let diasQueQuedan = max(1, diasDelMes - calendario.component(.day, from: .now) + 1)
        let porDia = queda / Double(diasQueQuedan)

        return .result(dialog: """
            Te quedan \(queda.formatted(.currency(code: ajustes?.currencyCode ?? "EUR"))) \
            este mes: \(porDia.formatted(.currency(code: ajustes?.currencyCode ?? "EUR"))) al día.
            """)
    }
}

// MARK: - El catálogo que ve Atajos y Siri

struct HabitiumShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddExpenseIntent(),
            phrases: [
                "Apunta un gasto en \(.applicationName)",
                "Añade un gasto a \(.applicationName)",
                "Gasto en \(.applicationName)",
            ],
            shortTitle: "Apuntar gasto",
            systemImageName: "eurosign.circle"
        )
        AppShortcut(
            intent: NextRoutineStepIntent(),
            phrases: [
                "Siguiente paso en \(.applicationName)",
                "Marca mi paso en \(.applicationName)",
            ],
            shortTitle: "Siguiente paso",
            systemImageName: "checkmark.circle"
        )
        AppShortcut(
            intent: RemainingBudgetIntent(),
            phrases: [
                "Cuánto me queda en \(.applicationName)",
                "Presupuesto en \(.applicationName)",
            ],
            shortTitle: "Cuánto me queda",
            systemImageName: "chart.pie"
        )
    }
}

// MARK: - Interpretar "4,20 bocadillo"

/// La misma lógica que `interpretarGasto` en web/finanzas-ia.js, y con
/// las mismas pruebas (HabitiumTests/ExpenseParserTests). Que existan dos
/// copias no es un descuido: el atajo del iPhone y el campo rápido de la
/// web tienen que entender lo mismo, o el mismo texto daría dos gastos
/// distintos según dónde lo escribas.
enum ExpenseParser {

    struct Parsed: Equatable {
        let importe: Double
        let categoria: TransactionCategory
        let nota: String
    }

    /// Palabras que salen de verdad al apuntar un gasto. No pretende ser
    /// completa: lo que no acierte cae en "otro", que se corrige de un
    /// toque en la app.
    private static let pistas: [(TransactionCategory, [String])] = [
        (.food, ["bocadi", "desayun", "comid", "cena", "menú", "menu", "super", "mercadona",
                 "lidl", "carrefour", "restaurante", "bar", "café", "cafe", "pizza", "kebab", "hamburgues"]),
        (.transport, ["bus", "metro", "tren", "taxi", "uber", "cabify", "gasolina", "bici",
                      "patinete", "billete", "abono"]),
        (.leisure, ["cine", "concierto", "videojuego", "juego", "netflix", "spotify", "salir",
                    "fiesta", "discoteca", "bolera"]),
        (.health, ["farmacia", "médic", "medico", "dentista", "gimnasio", "gym"]),
        (.services, ["móvil", "movil", "teléfono", "telefono", "internet", "luz", "agua", "suscrip"]),
        (.shopping, ["ropa", "zapatil", "camiseta", "amazon", "regalo", "zara", "compra"]),
    ]

    static func parse(_ texto: String) -> Parsed? {
        let crudo = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !crudo.isEmpty else { return nil }

        // El PRIMER número, con coma o punto decimal. "4,20 bocadillo
        // para 2" es un gasto de 4,20, no de 2.
        guard let rango = crudo.range(of: #"\d+(?:[.,]\d{1,2})?"#, options: .regularExpression) else {
            return nil
        }
        let importe = Double(crudo[rango].replacingOccurrences(of: ",", with: ".")) ?? 0
        guard importe > 0 else { return nil }

        var resto = crudo
        resto.replaceSubrange(rango, with: " ")
        resto = resto.replacingOccurrences(
            of: #"(?:€|eur(?:os?)?|euros?)"#, with: " ",
            options: [.regularExpression, .caseInsensitive]
        )
        resto = resto.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")

        let minusculas = resto.lowercased()
        let categoria = pistas.first { _, palabras in
            palabras.contains { minusculas.contains($0) }
        }?.0 ?? .other

        return Parsed(importe: importe, categoria: categoria, nota: String(resto.prefix(120)))
    }
}
