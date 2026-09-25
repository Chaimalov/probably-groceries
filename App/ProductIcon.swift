import SwiftUI

struct ProductIcon: View {
    let name: String

    var body: some View {
        Group {
            if let emoji {
                Text(emoji).font(.system(size: 31))
            } else {
                Image(systemName: "basket")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 44, height: 48)
        .accessibilityHidden(true)
    }

    private var emoji: String? {
        let value = name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let matches: [(String, String)] = [
            ("milk", "🥛"), ("חלב", "🥛"),
            ("egg", "🥚"), ("ביצ", "🥚"),
            ("bread", "🍞"), ("לחם", "🍞"),
            ("cucumber", "🥒"), ("מלפפון", "🥒"),
            ("coffee", "☕️"), ("קפה", "☕️"),
            ("olive oil", "🫒"), ("שמן זית", "🫒"),
            ("toothpaste", "🪥"), ("משחת שיניים", "🪥"),
            ("tomato", "🍅"), ("עגבני", "🍅"),
            ("banana", "🍌"), ("בננה", "🍌"),
            ("apple", "🍎"), ("תפוח", "🍎"),
            ("cheese", "🧀"), ("גבינה", "🧀")
        ]
        return matches.first { value.contains($0.0) }?.1
    }
}
