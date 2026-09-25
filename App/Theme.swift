import SwiftUI
import UIKit

enum Theme {
    static let accent = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.40, green: 0.82, blue: 0.57, alpha: 1)
            : UIColor(red: 0.10, green: 0.46, blue: 0.29, alpha: 1)
    })
}
