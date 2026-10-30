import SwiftUI
import UIKit

// Configure this navigation item once per list color / text size. Mutating the
// shared bar appearance during SwiftUI updates fights its scroll-edge transition
// and can repeatedly invalidate the native large-title layout.
struct ShoppingNavigationTitleTint: UIViewControllerRepresentable {
    var color: UIColor

    func makeUIViewController(context: Context) -> Controller { Controller(color: color) }
    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.color = color
        controller.apply()
    }

    final class Controller: UIViewController {
        var color: UIColor
        private weak var configuredItem: UINavigationItem?
        private var configuredColor: UIColor?
        private var configuredTextSize: UIContentSizeCategory?

        init(color: UIColor) { self.color = color; super.init(nibName: nil, bundle: nil) }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func viewDidLoad() { super.viewDidLoad(); view.isUserInteractionEnabled = false }
        override func viewWillAppear(_ animated: Bool) { super.viewWillAppear(animated); apply() }
        override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); apply() }
        override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
            super.traitCollectionDidChange(previousTraitCollection)
            if previousTraitCollection?.preferredContentSizeCategory != traitCollection.preferredContentSizeCategory {
                apply()
            }
        }

        func apply() {
            guard let navigation = navigationController,
                  let item = navigation.topViewController?.navigationItem else { return }
            let textSize = traitCollection.preferredContentSizeCategory
            guard configuredItem !== item || configuredColor?.isEqual(color) != true || configuredTextSize != textSize else { return }
            configuredItem = item
            configuredColor = color
            configuredTextSize = textSize

            let base = UIFont.preferredFont(forTextStyle: .largeTitle, compatibleWith: traitCollection)
            let descriptor = (base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor)
                .withSymbolicTraits(.traitBold) ?? base.fontDescriptor
            let large = UIFont(descriptor: descriptor, size: base.pointSize)
            let headline = UIFont.preferredFont(forTextStyle: .headline, compatibleWith: traitCollection)
            let compact = UIFont(descriptor: headline.fontDescriptor.withDesign(.rounded) ?? headline.fontDescriptor,
                                 size: headline.pointSize)
            func appearance(_ source: UINavigationBarAppearance) -> UINavigationBarAppearance {
                let result = source.copy()
                result.largeTitleTextAttributes[.foregroundColor] = color
                result.largeTitleTextAttributes[.font] = large
                result.titleTextAttributes[.font] = compact
                return result
            }
            let bar = navigation.navigationBar
            // Keep native backgrounds/glass and let UIKit own collapse geometry.
            UIView.performWithoutAnimation {
                item.standardAppearance = appearance(bar.standardAppearance)
                let edge = bar.scrollEdgeAppearance ?? {
                    let transparent = bar.standardAppearance.copy()
                    transparent.configureWithTransparentBackground()
                    return transparent
                }()
                item.scrollEdgeAppearance = appearance(edge)
                item.compactAppearance = appearance(bar.compactAppearance ?? bar.standardAppearance)
                item.compactScrollEdgeAppearance = appearance(bar.compactScrollEdgeAppearance ?? edge)
            }
        }
    }
}
