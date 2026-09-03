//
//  SeasonPass.swift
//  Habitium
//
//  El pase de temporada: una tabla de niveles que se llena con la
//  experiencia del mes y va soltando recompensas.
//
//  Sobre las recompensas: son cosméticas (temas de color, insignias,
//  títulos) y eso es deliberado, no una limitación. Un pase que
//  desbloquease funciones dejaría la app peor de lo que está para quien
//  no juegue, y esto es una app de cuidado personal, no un juego con
//  micropagos. Lo que se desbloquea es identidad — cómo se ve tu app y
//  cómo te llamas dentro de ella — que es justo lo que hace que apetezca
//  seguir sin quitarle nada a nadie.
//
//  La temporada es el mes natural (ver PlayerProfile.seasonID). Al
//  cambiar de mes, la experiencia de temporada vuelve a cero pero lo ya
//  desbloqueado NO se pierde: quitar algo conseguido castiga por
//  descansar un mes, que es justo lo contrario de lo que se busca.
//

import SwiftUI

/// Lo que otorga un nivel del pase.
enum SeasonReward: Equatable {
    /// Un tema de acento que se puede activar en Ajustes.
    case accent(AccentTheme)
    /// Una insignia para la pantalla de progreso.
    case badge(symbol: String, name: String)
    /// Un título que aparece bajo tu nivel.
    case title(String)
}

/// Paletas de acento desbloqueables. El caso `.classic` es el de siempre
/// y está disponible desde el principio.
enum AccentTheme: String, CaseIterable, Identifiable {
    case classic
    case ocean
    case sunset
    case forest
    case grape
    case midnight

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .classic: return "Clásico"
        case .ocean: return "Océano"
        case .sunset: return "Atardecer"
        case .forest: return "Bosque"
        case .grape: return "Uva"
        case .midnight: return "Medianoche"
        }
    }

    var color: Color {
        switch self {
        case .classic: return Theme.Colors.nutrition
        case .ocean: return Color(red: 0.05, green: 0.55, blue: 0.78)
        case .sunset: return Color(red: 0.95, green: 0.42, blue: 0.24)
        case .forest: return Color(red: 0.18, green: 0.45, blue: 0.28)
        case .grape: return Color(red: 0.55, green: 0.24, blue: 0.70)
        case .midnight: return Color(red: 0.22, green: 0.26, blue: 0.45)
        }
    }
}

/// Un nivel del pase: la experiencia que hace falta y lo que da.
struct SeasonTier: Identifiable {
    let id: String
    let tier: Int
    let xpRequired: Int
    let reward: SeasonReward

    var rewardName: String {
        switch reward {
        case .accent(let theme): return "Tema \(theme.displayName)"
        case .badge(_, let name): return name
        case .title(let title): return "Título «\(title)»"
        }
    }

    var symbolName: String {
        switch reward {
        case .accent: return "paintpalette.fill"
        case .badge(let symbol, _): return symbol
        case .title: return "rosette"
        }
    }
}

enum SeasonPass {

    /// Los niveles del pase. Los primeros están muy juntos a propósito:
    /// desbloquear algo el primer día es lo que engancha; si la primera
    /// recompensa tardara una semana, casi nadie llegaría a verla.
    static let tiers: [SeasonTier] = [
        SeasonTier(id: "t1", tier: 1, xpRequired: 50, reward: .badge(symbol: "leaf.fill", name: "Primer paso")),
        SeasonTier(id: "t2", tier: 2, xpRequired: 150, reward: .accent(.ocean)),
        SeasonTier(id: "t3", tier: 3, xpRequired: 300, reward: .title("Constante")),
        SeasonTier(id: "t4", tier: 4, xpRequired: 500, reward: .badge(symbol: "flame.fill", name: "En racha")),
        SeasonTier(id: "t5", tier: 5, xpRequired: 750, reward: .accent(.sunset)),
        SeasonTier(id: "t6", tier: 6, xpRequired: 1050, reward: .title("Disciplinado")),
        SeasonTier(id: "t7", tier: 7, xpRequired: 1400, reward: .badge(symbol: "bolt.fill", name: "Imparable")),
        SeasonTier(id: "t8", tier: 8, xpRequired: 1800, reward: .accent(.forest)),
        SeasonTier(id: "t9", tier: 9, xpRequired: 2250, reward: .title("Referente")),
        SeasonTier(id: "t10", tier: 10, xpRequired: 2750, reward: .accent(.grape)),
        SeasonTier(id: "t11", tier: 11, xpRequired: 3300, reward: .badge(symbol: "crown.fill", name: "Corona del mes")),
        SeasonTier(id: "t12", tier: 12, xpRequired: 4000, reward: .accent(.midnight)),
    ]

    static var maxXP: Int { tiers.last?.xpRequired ?? 0 }

    /// Los niveles ya alcanzados con la experiencia de temporada dada.
    static func unlockedTiers(seasonXP: Int) -> [SeasonTier] {
        tiers.filter { seasonXP >= $0.xpRequired }
    }

    /// El siguiente nivel por alcanzar, o nil si el pase está completo.
    static func nextTier(seasonXP: Int) -> SeasonTier? {
        tiers.first { seasonXP < $0.xpRequired }
    }

    /// Progreso hacia el siguiente nivel, de 0 a 1.
    static func progressToNextTier(seasonXP: Int) -> Double {
        guard let next = nextTier(seasonXP: seasonXP) else { return 1 }
        let previous = tiers.last { seasonXP >= $0.xpRequired }?.xpRequired ?? 0
        let span = next.xpRequired - previous
        guard span > 0 else { return 1 }
        return min(max(Double(seasonXP - previous) / Double(span), 0), 1)
    }

    /// Los temas de acento que este perfil puede usar. `.classic`
    /// siempre está; el resto salen del pase.
    static func availableAccents(unlockedRewardIDs: [String]) -> [AccentTheme] {
        var accents: [AccentTheme] = [.classic]
        for tier in tiers where unlockedRewardIDs.contains(tier.id) {
            if case .accent(let theme) = tier.reward { accents.append(theme) }
        }
        return accents
    }

    /// El título más alto desbloqueado, si hay alguno.
    static func highestTitle(unlockedRewardIDs: [String]) -> String? {
        var result: String?
        for tier in tiers where unlockedRewardIDs.contains(tier.id) {
            if case .title(let title) = tier.reward { result = title }
        }
        return result
    }
}
