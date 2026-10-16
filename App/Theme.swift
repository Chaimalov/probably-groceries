import SwiftUI
import UIKit

enum Theme {
    static let accent = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.40, green: 0.82, blue: 0.57, alpha: 1)
            : UIColor(red: 0.118, green: 0.318, blue: 0.212, alpha: 1)
    })

    // Quiet warmth on content; system materials remain responsible for chrome.
    static let canvas = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.075, green: 0.082, blue: 0.075, alpha: 1)
            : UIColor(red: 0.980, green: 0.976, blue: 0.957, alpha: 1)
    })
    static let editor = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.125, green: 0.137, blue: 0.125, alpha: 1)
            : .white
    })
    static let control = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.19, green: 0.205, blue: 0.19, alpha: 1)
            : UIColor(red: 0.925, green: 0.925, blue: 0.895, alpha: 1)
    })

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

    static func tint(for name: String) -> Color {
        listColors.first { $0.name == name }?.color ?? accent
    }
}
