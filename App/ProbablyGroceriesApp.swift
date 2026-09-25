import SwiftUI

@main
struct ProbablyGroceriesApp: App {
    var body: some Scene {
        WindowGroup {
            ShoppingView()
                .environment(\.locale, Locale(identifier: "he_IL"))
                .environment(\.layoutDirection, .rightToLeft)
        }
    }
}
