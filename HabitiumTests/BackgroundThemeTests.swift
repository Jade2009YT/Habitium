//
//  BackgroundThemeTests.swift
//  HabitiumTests
//
//  Los fondos elegibles. Lo que se prueba aquí no son los colores —eso
//  se juzga con los ojos— sino las REGLAS que hacen que un fondo se vea
//  bien, que son las que se rompen sin querer al añadir uno nuevo:
//
//   · un fondo oscuro no puede llevar sombra bajo la tarjeta (negro
//     sobre negro no se ve) y sí tiene que llevar borde, o la tarjeta se
//     funde con el fondo y la pantalla queda como una mancha plana;
//   · un fondo claro es justo al revés;
//   · el nombre guardado tiene que poder volver a leerse, o al reabrir
//     la app el fondo elegido se pierde.
//
//  Es el tipo de fallo que no da error de compilación y que solo se ve
//  cuando ya lo tienes instalado en el móvil.
//

import SwiftUI
import XCTest
@testable import Habitium

final class BackgroundThemeTests: XCTestCase {

    // MARK: - Reglas de la tarjeta

    func testDarkThemesUseABorderInsteadOfAShadow() {
        for theme in BackgroundTheme.allCases where theme.isDark {
            XCTAssertEqual(
                theme.cardShadowOpacity, 0,
                "\(theme.rawValue): una sombra sobre fondo oscuro no se ve, sobra"
            )
            XCTAssertNotNil(
                theme.cardBorder,
                "\(theme.rawValue): sin borde, la tarjeta se funde con el fondo"
            )
        }
    }

    func testLightThemesUseAShadowInsteadOfABorder() {
        for theme in BackgroundTheme.allCases where !theme.isDark {
            XCTAssertGreaterThan(theme.cardShadowOpacity, 0, "\(theme.rawValue)")
            XCTAssertNil(
                theme.cardBorder,
                "\(theme.rawValue): en claro el borde sobra, la sombra ya separa"
            )
        }
    }

    // MARK: - Esquema de color

    func testOnlyTheAutomaticThemeLetsTheSystemDecide() {
        XCTAssertNil(BackgroundTheme.system.colorScheme)
        for theme in BackgroundTheme.allCases where theme != .system {
            XCTAssertNotNil(
                theme.colorScheme,
                "\(theme.rawValue): si no fija el esquema, el texto y la barra de pestañas no acompañan al fondo"
            )
        }
    }

    func testColorSchemeMatchesWhetherTheThemeIsDark() {
        for theme in BackgroundTheme.allCases where theme != .system {
            XCTAssertEqual(
                theme.colorScheme, theme.isDark ? .dark : .light,
                "\(theme.rawValue): esquema y fondo van al revés — texto oscuro sobre fondo oscuro"
            )
        }
    }

    // MARK: - Guardado

    func testEveryThemeSurvivesBeingSavedAndReadBack() {
        for theme in BackgroundTheme.allCases {
            XCTAssertEqual(BackgroundTheme(rawValue: theme.rawValue), theme)
        }
    }

    func testAnUnknownSavedValueFallsBackToAutomatic() {
        // Pasa de verdad: si algún día se quita un fondo, quien lo
        // tuviera elegido abriría la app con un valor que ya no existe.
        XCTAssertNil(BackgroundTheme(rawValue: "arcoiris"))
    }

    // MARK: - Nombres

    func testEveryThemeHasItsOwnNameAndDescription() {
        let names = Set(BackgroundTheme.allCases.map(\.displayName))
        XCTAssertEqual(names.count, BackgroundTheme.allCases.count, "hay dos fondos con el mismo nombre")

        for theme in BackgroundTheme.allCases {
            XCTAssertFalse(theme.displayName.isEmpty, "\(theme.rawValue)")
            XCTAssertFalse(theme.subtitle.isEmpty, "\(theme.rawValue)")
        }
    }
}
