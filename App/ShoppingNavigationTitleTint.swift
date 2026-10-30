import SwiftUI
import UIKit

// Color the system's large title, leaving its collapse, safe areas and glass
// entirely to UINavigationBar. No scroll-offset-driven SwiftUI layout state.
struct ShoppingNavigationTitleTint: UIViewControllerRepresentable {
    var color: UIColor

    func makeUIViewController(context: Context) -> Controller { Controller(color: color) }
    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.color = color
        controller.apply()
    }

    final class Controller: UIViewController {
        var color: UIColor
        init(color: UIColor) { self.color = color; super.init(nibName: nil, bundle: nil) }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func viewDidLoad() { super.viewDidLoad(); view.isUserInteractionEnabled = false }
        override func viewWillAppear(_ animated: Bool) { super.viewWillAppear(animated); apply() }
        override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); apply() }

        func apply() {
            guard let bar = navigationController?.navigationBar else { return }
            let standardColor = bar.standardAppearance.largeTitleTextAttributes[.foregroundColor] as? UIColor
            let edgeColor = bar.scrollEdgeAppearance?.largeTitleTextAttributes[.foregroundColor] as? UIColor
            guard standardColor?.isEqual(color) != true || edgeColor?.isEqual(color) != true else { return }
            let standard = bar.standardAppearance.copy()
            standard.largeTitleTextAttributes[.foregroundColor] = color
            bar.standardAppearance = standard
            let edge = (bar.scrollEdgeAppearance ?? standard).copy()
            edge.largeTitleTextAttributes[.foregroundColor] = color
            bar.scrollEdgeAppearance = edge
        }
    }
}
