//
//  DailyChallengeTests.swift
//  HabitiumTests
//
//  Los retos se sortean con un generador sembrado con la fecha, y toda
//  la mecánica depende de que ese sorteo sea REPRODUCIBLE: si el mismo
//  día diera retos distintos en cada llamada, el progreso se perdería al
//  reabrir la app y el iPhone y la web enseñarían cosas diferentes.
//  Es justo el tipo de fallo que no se ve mirando el código.
//

import XCTest
@testable import Habitium

final class DailyChallengeTests: XCTestCase {

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day))!
    }

    // MARK: - Reproducibilidad

    func testSameDayGivesSameChallenges() {
        let day = date(2026, 9, 3)
        let first = DailyChallengeEngine.challenges(for: day)
        let second = DailyChallengeEngine.challenges(for: day)

        XCTAssertEqual(first.map(\.id), second.map(\.id))
        XCTAssertEqual(first.map(\.goal), second.map(\.goal))
    }

    func testSameDayIsStableRegardlessOfTimeOfDay() {
        let morning = Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: date(2026, 9, 3))!
        let night = Calendar.current.date(bySettingHour: 23, minute: 30, second: 0, of: date(2026, 9, 3))!

        XCTAssertEqual(
            DailyChallengeEngine.challenges(for: morning).map(\.id),
            DailyChallengeEngine.challenges(for: night).map(\.id),
            "Los retos no pueden cambiar a lo largo del mismo día"
        )
    }

    /// Si dos días seguidos dieran siempre lo mismo, dejarían de ser un
    /// aliciente. No exigimos que TODOS los días difieran (con 7 tipos y
    /// 3 huecos, coincidir de vez en cuando es normal), pero sí que haya
    /// variedad real a lo largo de un mes.
    func testChallengesVaryAcrossTheMonth() {
        let combinations = Set((1...28).map { day in
            DailyChallengeEngine.challenges(for: date(2026, 9, day))
                .map(\.id)
                .joined(separator: "+")
        })
        XCTAssertGreaterThan(combinations.count, 8, "Muy poca variedad de retos en un mes")
    }

    // MARK: - Forma de los retos

    func testAlwaysReturnsThreeDistinctChallenges() {
        for day in 1...31 {
            let challenges = DailyChallengeEngine.challenges(for: date(2026, 1, day))
            XCTAssertEqual(challenges.count, 3, "Día \(day)")
            XCTAssertEqual(Set(challenges.map(\.id)).count, 3, "Retos repetidos el día \(day)")
        }
    }

    func testGoalsAreAlwaysReachable() {
        for day in 1...31 {
            for challenge in DailyChallengeEngine.challenges(for: date(2026, 5, day)) {
                XCTAssertGreaterThan(challenge.goal, 0)
                XCTAssertTrue(
                    challenge.kind.goalOptions.contains(challenge.goal),
                    "El objetivo \(challenge.goal) no está entre los previstos para \(challenge.kind)"
                )
            }
        }
    }

    // MARK: - Progreso

    func testCompletionAndFraction() {
        var challenge = DailyChallenge(kind: .habits, goal: 3, progress: 0)
        XCTAssertFalse(challenge.isComplete)
        XCTAssertEqual(challenge.fraction, 0, accuracy: 0.001)

        challenge.progress = 2
        XCTAssertFalse(challenge.isComplete)
        XCTAssertEqual(challenge.fraction, 2.0 / 3.0, accuracy: 0.001)

        challenge.progress = 3
        XCTAssertTrue(challenge.isComplete)
        XCTAssertEqual(challenge.fraction, 1, accuracy: 0.001)

        // Pasarse no debe desbordar la barra.
        challenge.progress = 9
        XCTAssertTrue(challenge.isComplete)
        XCTAssertEqual(challenge.fraction, 1, accuracy: 0.001)
    }

    // MARK: - Generador

    func testSeededGeneratorIsDeterministic() {
        var a = SeededGenerator(seed: 20260903)
        var b = SeededGenerator(seed: 20260903)
        let first = (0..<5).map { _ in a.next() }
        let second = (0..<5).map { _ in b.next() }
        XCTAssertEqual(first, second)
    }

    func testDifferentSeedsDiverge() {
        var a = SeededGenerator(seed: 20260903)
        var b = SeededGenerator(seed: 20260904)
        XCTAssertNotEqual(a.next(), b.next())
    }
}
