//
//  ExpenseParserTests.swift
//  HabitiumTests
//
//  Los mismos casos que web/finanzas-ia.test.mjs, a propósito.
//
//  ExpenseParser (Swift) e interpretarGasto (JavaScript) son dos copias
//  de la misma lógica, y eso solo se sostiene si se prueban igual: si
//  escribes "4,20 bocadillo" en el atajo del iPhone y en el campo rápido
//  de la web, el gasto tiene que salir idéntico. Cualquier caso nuevo
//  que se añada aquí va también allí, y al revés.
//

import Testing
@testable import Habitium

struct ExpenseParserTests {

    @Test("Coma decimal, que es como se escribe en España")
    func comaDecimal() {
        let r = ExpenseParser.parse("4,20 bocadillo")
        #expect(r?.importe == 4.2)
        #expect(r?.categoria == .food)
        #expect(r?.nota == "bocadillo")
    }

    @Test("Punto decimal también")
    func puntoDecimal() {
        #expect(ExpenseParser.parse("12.50 cine")?.importe == 12.5)
    }

    @Test("El símbolo del euro no estorba, esté donde esté")
    func simboloEuro() {
        #expect(ExpenseParser.parse("3,5€ bus")?.importe == 3.5)
        #expect(ExpenseParser.parse("15 euros zapatillas")?.importe == 15)
        #expect(ExpenseParser.parse("€8 kebab")?.importe == 8)
    }

    @Test("Se coge el PRIMER número, no el último")
    func primerNumero() {
        // "4,20 bocadillo para 2" es un gasto de 4,20, no de 2.
        #expect(ExpenseParser.parse("4,20 bocadillo para 2")?.importe == 4.2)
    }

    @Test("Adivina la categoría por palabras que se usan de verdad")
    func categorias() {
        #expect(ExpenseParser.parse("45 mercadona")?.categoria == .food)
        #expect(ExpenseParser.parse("2,40 metro")?.categoria == .transport)
        #expect(ExpenseParser.parse("9,99 spotify")?.categoria == .leisure)
        #expect(ExpenseParser.parse("30 farmacia")?.categoria == .health)
        #expect(ExpenseParser.parse("25 zapatillas")?.categoria == .shopping)
    }

    @Test("Si no la adivina, cae en 'otro' en vez de fallar")
    func categoriaDesconocida() {
        #expect(ExpenseParser.parse("17 no sé qué era esto")?.categoria == .other)
    }

    @Test("Sin número no se apunta nada, en vez de apuntar cero")
    func sinImporte() {
        #expect(ExpenseParser.parse("bocadillo") == nil)
        #expect(ExpenseParser.parse("") == nil)
        #expect(ExpenseParser.parse("   ") == nil)
        #expect(ExpenseParser.parse("0 nada") == nil)
    }

    @Test("Una nota kilométrica se corta antes de llegar a la base")
    func notaLarga() {
        // El servidor tiene un CHECK de 2000 caracteres en
        // transactions.note, pero el corte a 120 es el de la interfaz:
        // una nota más larga que eso no se lee en una fila de lista.
        let largo = "5 " + String(repeating: "a", count: 500)
        #expect((ExpenseParser.parse(largo)?.nota.count ?? 999) <= 120)
    }

    @Test("Sin nota, el gasto se apunta igual")
    func soloImporte() {
        let r = ExpenseParser.parse("7")
        #expect(r?.importe == 7)
        #expect(r?.nota == "")
        #expect(r?.categoria == .other)
    }
}
