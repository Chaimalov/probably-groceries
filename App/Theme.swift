import SwiftUI
import UIKit

enum Theme {
    static let accent = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.40, green: 0.82, blue: 0.57, alpha: 1)
            : UIColor(red: 0.10, green: 0.46, blue: 0.29, alpha: 1)
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
