//
//  ProgressionEngineTests.swift
//  HabitiumTests
//
//  La curva de niveles es la pieza del sistema de progresión más fácil de
//  equivocar y la única que se puede probar sola: no toca SwiftData, ni
//  red, ni interfaz. Un error aquí (un nivel que se salta, una barra que
//  nunca se llena) se nota enseguida al usar la app pero es muy molesto
//  de diagnosticar sin estas pruebas.
//

import XCTest
@testable import Habitium

final class ProgressionEngineTests: XCTestCase {

    // MARK: - Coste de cada nivel

    func testXPToAdvanceGrowsLinearly() {
        XCTAssertEqual(ProgressionEngine.xpToAdvance(fromLevel: 1), 100)
        XCTAssertEqual(ProgressionEngine.xpToAdvance(fromLevel: 2), 150)
        XCTAssertEqual(ProgressionEngine.xpToAdvance(fromLevel: 3), 200)
    }

    func testTotalXPRequiredAccumulates() {
        XCTAssertEqual(ProgressionEngine.totalXPRequired(forLevel: 1), 0)
        XCTAssertEqual(ProgressionEngine.totalXPRequired(forLevel: 2), 100)
        XCTAssertEqual(ProgressionEngine.totalXPRequired(forLevel: 3), 250)  // 100 + 150
        XCTAssertEqual(ProgressionEngine.totalXPRequired(forLevel: 4), 450)  // + 200
    }

    // MARK: - Nivel a partir de la experiencia

    func testLevelStartsAtOne() {
        XCTAssertEqual(ProgressionEngine.level(forTotalXP: 0), 1)
        XCTAssertEqual(ProgressionEngine.level(forTotalXP: 99), 1)
    }

    func testLevelUpHappensExactlyAtThreshold() {
        XCTAssertEqual(ProgressionEngine.level(forTotalXP: 100), 2)
        XCTAssertEqual(ProgressionEngine.level(forTotalXP: 249), 2)
        XCTAssertEqual(ProgressionEngine.level(forTotalXP: 250), 3)
    }

    /// El nivel calculado y el umbral acumulado tienen que decir lo
    /// mismo: si se desincronizan, la barra se llena pero el número no
    /// sube (o al revés).
    func testLevelAndThresholdAgreeAcrossRange() {
        for xp in stride(from: 0, through: 20_000, by: 37) {
            let level = ProgressionEngine.level(forTotalXP: xp)
            XCTAssertLessThanOrEqual(
                ProgressionEngine.totalXPRequired(forLevel: level), xp,
                "El nivel \(level) exige más XP de la que tiene el jugador (\(xp))"
            )
            XCTAssertGreaterThan(
                ProgressionEngine.totalXPRequired(forLevel: level + 1), xp,
                "Con \(xp) XP debería haber alcanzado ya el nivel \(level + 1)"
            )
        }
    }

    // MARK: - Progreso dentro del nivel

    func testProgressIsZeroRightAfterLevelUp() {
        XCTAssertEqual(ProgressionEngine.progressWithinLevel(totalXP: 100), 0, accuracy: 0.0001)
        XCTAssertEqual(ProgressionEngine.progressWithinLevel(totalXP: 250), 0, accuracy: 0.0001)
    }

    func testProgressReachesHalfway() {
        // Nivel 2 empieza en 100 y cuesta 150: la mitad son 175.
        XCTAssertEqual(ProgressionEngine.progressWithinLevel(totalXP: 175), 0.5, accuracy: 0.0001)
    }

    func testProgressStaysInBounds() {
        for xp in stride(from: 0, through: 10_000, by: 13) {
            let progress = ProgressionEngine.progressWithinLevel(totalXP: xp)
            XCTAssertGreaterThanOrEqual(progress, 0)
            XCTAssertLessThanOrEqual(progress, 1)
        }
    }

    // MARK: - Lo que falta para subir

    func testRemainingXPMatchesTheGap() {
        XCTAssertEqual(ProgressionEngine.xpRemainingToNextLevel(totalXP: 0), 100)
        XCTAssertEqual(ProgressionEngine.xpRemainingToNextLevel(totalXP: 99), 1)
        XCTAssertEqual(ProgressionEngine.xpRemainingToNextLevel(totalXP: 100), 150)
    }

    /// Nunca debe anunciar "0 XP para el siguiente nivel" sin haber
    /// subido: sería una barra llena que no avanza.
    func testRemainingXPIsNeverZero() {
        for xp in stride(from: 0, through: 10_000, by: 7) {
            XCTAssertGreaterThan(ProgressionEngine.xpRemainingToNextLevel(totalXP: xp), 0)
        }
    }

    // MARK: - Pase de temporada

    func testUnlockedTiersGrowWithSeasonXP() {
        XCTAssertTrue(SeasonPass.unlockedTiers(seasonXP: 0).isEmpty)
        XCTAssertEqual(SeasonPass.unlockedTiers(seasonXP: 50).count, 1)
        XCTAssertEqual(SeasonPass.unlockedTiers(seasonXP: 200).count, 2)
    }

    func testNextTierIsNilWhenPassIsComplete() {
        XCTAssertNotNil(SeasonPass.nextTier(seasonXP: 0))
        XCTAssertNil(SeasonPass.nextTier(seasonXP: SeasonPass.maxXP))
    }

    func testTierProgressStaysInBounds() {
        for xp in stride(from: 0, through: SeasonPass.maxXP + 500, by: 17) {
            let progress = SeasonPass.progressToNextTier(seasonXP: xp)
            XCTAssertGreaterThanOrEqual(progress, 0)
            XCTAssertLessThanOrEqual(progress, 1)
        }
    }

    /// El tema clásico tiene que estar disponible desde el minuto uno:
    /// si no, un usuario nuevo se quedaría sin ningún acento.
    func testClassicAccentIsAlwaysAvailable() {
        XCTAssertEqual(SeasonPass.availableAccents(unlockedRewardIDs: []), [.classic])
        XCTAssertTrue(SeasonPass.availableAccents(unlockedRewardIDs: ["t2"]).contains(.ocean))
    }

    // MARK: - Temporadas

    func testSeasonIDIsYearAndMonth() {
        var components = DateComponents()
        components.year = 2026
        components.month = 9
        components.day = 15
        let date = Calendar.current.date(from: components)!
        XCTAssertEqual(PlayerProfile.currentSeasonID(for: date), "2026-09")
    }
}
