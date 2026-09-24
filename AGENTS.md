# Working notes for coding agents

Read README.md and docs/PRODUCT.md before implementing. This is a personal iPhone app: choose the shortest path to a build that can be used on device, and revise freely from real shopping trips.

- Keep native SwiftUI and WidgetKit. Never introduce a web shell or inventory bookkeeping.
- One check-off creates a purchase event; undo/correction removes its learning effect. An accepted suggestion alone is not a purchase.
- Preserve offline usefulness. Jev is an optional narrow judgment after the local predictor, not the calculator for time or quantities.
- Keep the API key in Keychain, never in source, test fixtures, logs or widget storage.
- Prefer small working vertical slices and device checks over broad abstractions. Add tests only for meaningful prediction/event edge cases.
- Follow docs/DESIGN.md for the preferred calm iOS direction, including RTL, accessibility and subtle motion.
- Before implementing a task, check its `Depends on` issue references in docs/ROADMAP.md.
