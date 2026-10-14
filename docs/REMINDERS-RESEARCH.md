# Reminders interaction study — 14 October 2026

## Evidence and limits

This investigation uses Apple's own Reminders user guide, UIKit contracts and Human Interface Guidelines. No Reminders binary, live iPhone session, or screenshot measurement was available. It establishes observable interaction behavior and supported implementation APIs; it does not establish Apple's private implementation, exact pixel dimensions, timing constants or haptic patterns. REA cannot supply those without a target artifact.

Sources:

- [Edit and organize a Reminders list](https://support.apple.com/en-ae/guide/iphone/iph82596cb20/ios): long-press item and section reorder, section collapse, two-finger selection, shared order.
- [Organise reminders](https://support.apple.com/en-au/119953): hold one item and tap others with another finger to add to the drag.
- [UIKit drag and drop](https://developer.apple.com/documentation/uikit/drag-and-drop): system-managed drag sessions and native view interactions.
- [Collection-view drag and drop](https://developer.apple.com/documentation/uikit/supporting-drag-and-drop-in-collection-views): beginning and adding items, insertion proposals and coordinated animation.
- [Drag and drop HIG](https://developer.apple.com/design/human-interface-guidelines/drag-and-drop): continuous destination feedback, multi-item support and accessible alternatives.
- [Cancellation previews](https://developer.apple.com/documentation/uikit/uidraginteractiondelegate/draginteraction(_:previewforcancelling:withdefault:)): retarget a cancelled lift to its source.
- [Drop previews](https://developer.apple.com/documentation/uikit/uidropinteractiondelegate/dropinteraction(_:previewfordropping:withdefault:)): retarget a drop or fade it when no meaningful visible destination exists.

## Implementation choices in Groceries

Keep the native SwiftUI List and its selection/swipe machinery. Public UIDragInteraction and UIDropInteraction attach to row/header hosts without replacing SwiftUI's collection-view delegates. This is our architecture, not a claim about Reminders internals.

- Retain native hold-to-lift, flocking, typed same-list moves, and displayed-order multi-item persistence.
- Provide source-target cancellation previews and insertion-target landing previews. Fade product drops into a section header rather than depicting an item landing at the wrong row, especially when collapsed. Respect Reduce Motion.
- Use a section highlight for a product destination, an insertion line for row/section reordering. The visual feedback must reflect whether the operation enters a section or inserts beside an item.
- Scroll the list near its visible edges during a lifted session. The driver belongs to the session so source-row reuse doesn't discard it; stop before drop/cancellation, bound offsets and avoid retaining the session.
- Render the add editor inside the chosen expanded section, expand that section when its plus is tapped, and scroll the editor into view. Return continues adding there. Preserve the Others editor when its last item disappears.
- Keep the compact separator-free rows requested by the product design. Use a plain secondary quantity control with a 44-point minimum target instead of a repeated bordered button. This is a product-specific visual choice, not an exact Reminders measurement.
- Commit a product rename when its field loses focus. VoiceOver custom actions move an item up/down within its section or route as alternatives to dragging.

## Validation

Existing CI covers build, add/quantity/purchase/undo persistence, sections, selection, native product and section reorder, and light/dark swipe screenshots. Device validation is still required for second-finger flocking, edge scrolling, cancelling after source reuse, drop preview timing, very large Dynamic Type, and reduced motion. No claim of pixel-perfect fidelity or verified haptics is made.
