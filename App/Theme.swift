import SwiftUI
import UIKit

enum Theme {
    static let accent = Color.green
    static let canvas = Color(uiColor: .systemBackground)
    static let editor = Color(uiColor: .secondarySystemBackground)
    static let control = Color(uiColor: .tertiarySystemFill)

    static let listColors: [(name: String, color: Color)] = [
        ("green", accent), ("mint", .mint), ("teal", .teal),
        ("blue", .blue), ("indigo", .indigo), ("purple", .purple),
        ("pink", .pink), ("orange", .orange), ("red", .red)
    ]
    static let listSymbols = [
        "cart", "basket", "bag", "bag.fill", "list.bullet", "checklist",
        "fork.knife", "carrot", "leaf", "cup.and.saucer", "birthday.cake",
        "snowflake", "house", "storefront", "heart", "star", "shippingbox", "gift"
    ]

    static func sectionAppearance(for name: String, listTint: String) -> SectionAppearance {
        let options: [(words: [String], symbol: String, tint: String)] = [
            (["ירק", "פירות", "produce", "vegetable", "fruit"], "carrot", "green"),
            (["חלב", "גבינ", "ביצ", "dairy", "egg"], "mug", "teal"),
            (["לחם", "מאפ", "אפייה", "bakery", "baking"], "birthday.cake", "orange"),
            (["קפוא", "frozen"], "snowflake", "blue"),
            (["בשר", "דגים", "meat", "fish"], "fish", "indigo"),
            (["ניקוי", "ניקיון", "clean"], "bubbles.and.sparkles", "teal"),
            (["משקא", "שתייה", "drink"], "waterbottle", "blue"),
            (["שימור", "מזווה", "pantry", "canned"], "cabinet", "orange")
        ]
        if let match = options.first(where: { option in option.words.contains { name.localizedCaseInsensitiveContains($0) } }) {
            return SectionAppearance(symbol: match.symbol, tint: match.tint)
        }
        return SectionAppearance(symbol: "basket", tint: listTint)
    }

    static func tint(for name: String) -> Color {
        listColors.first { $0.name == name }?.color ?? accent
    }
}

