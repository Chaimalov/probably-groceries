# iOS design direction

The preferred prototype uses large native typography and a compact, separator-free list like Apple Reminders. Keep breathing room around the headline and sections rather than between every product. Use “Maybe” for uncertainty. Do not repeat “Likely” on every row or show raw percentages by default.

All user-facing app screens use Hebrew and right-to-left layout. The screenshot reference illustrates hierarchy and spacing; its English copy is not the app language.

The selected reference shows a small date and overflow control above a short headline, an airy white list with circular check-off controls, a secondary quantity line, and a restrained “Maybe” divider. An inline add row and one native bottom action anchor the screen. The current interaction model follows Apple Reminders: Enter adds another item, swipes expose row actions, and touch-and-hold drag changes the order. Our functional prototype keeps active items ahead of predictions; the same row language applies to both. Do not depend on product photographs or category illustrations: household products can be highly specific. History, insights, and settings must open working screens rather than decorative destinations.

## Screen anatomy

- One primary list screen, with a short human headline and visible item count.
- Active items first, suggested items next, compact purchased rows last. Keep the shopping state obvious.
- A thumb-reachable New Item action focuses an inline row. Enter saves and keeps the row ready for the next item.
- Each row shows a tappable quantity even when it is one. Tapping animates open quantity controls, an optional unit (including a custom unit), an inline note and an optional photo attachment. Grouping can use a sheet. Completion is generous to tap and supported by VoiceOver.
- A small store picker switches lists and opens a native color and SF Symbol picker for each list. Named sections such as frozen vegetables, canned food and baking are collapsible; the plus in a header adds directly to that section. Touch and hold lifts a product or section; drop above or below another row/header to reorder. While holding products, tap other product rows with a second finger to add them to the drag. Dropping products on a section header moves them into that section, including empty or collapsed sections. Native handles remain available in reorder mode. The section swipe action opens the section editor. Urgent items show a flag in place without moving in the list.
- Detailed why/when and history live behind a tap; the first screen stays quiet.

## Interaction language

- A check-off gives a light haptic and a short, reversible move to Purchased.
- Notes and attached photos belong to the shopping item and survive undo. Photos are resized and stored in the app's local support directory; they do not sync between devices until the CloudKit data work includes attachments.
- Accepting a suggestion promotes it to the active list. “Not yet” records feedback with a temporary snooze.
- Swipe actions use icons with accessible Hebrew labels: a darker amber flag, blue section editor, and red destructive delete independent of the list color. Quantity, units, notes and photos stay available through the quantity button; tap the product name to rename. Touch and hold is reserved for lifting, so a context menu must not intercept this gesture.
- A full swipe flags or deletes from opposite edges. List selection supports the system's two-finger multi-select gesture; selected products can be flagged or deleted together. The selection control in the menu provides a visible alternative.
- A multi-product drop preserves the displayed order across sections, regardless of pickup order, and persists once. Cancellation and foreign-list/text drops must not reorder products or create purchase events.
- Use native lift, stacking and cancellation previews with a visible insertion line. Preview images must contain the item's title and quantity; draw from the item data rather than snapshotting a SwiftUI hosting cell, which can produce an empty background. Use the same image for lift and in-flight flocking. Attach public UIKit drag interactions to the enclosing list row/header, keeping controls and swipes available. Lift previews use the stable window as their animation target. Respect Reduce Motion and avoid animations that delay shopping.
- Hebrew and English must both lay out correctly; test long names, dynamic type, dark mode, and RTL.

## Materials and color

Use system typography, SF Symbols and semantic colors. The accent is a legible green with light and dark variants. Preserve readable content surfaces. Lean on the system's Liquid Glass for navigation and floating controls; keep list rows plain so shopping content stays readable. Check both appearances and increased contrast.

## Widgets

Small: a useful glance (count or top likely need) and deep link. Medium: a few top items plus a single clear action such as “Add all” or “Not yet” for one candidate. Widget snapshots are compact, privacy-conscious and useful in tinted appearances. Interactive actions use App Intents and refresh the widget timeline after persisted changes.

## References to inspect during implementation

- [Apple Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/)
- [Widgets](https://developer.apple.com/design/human-interface-guidelines/widgets)
- [Interactive WidgetKit](https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities)
- Mobbin explorations: Reminders, Things, Todoist, Apple Journal and Apple Invites for list hierarchy, quick add, empty states and interaction details. Treat these as inspiration, not assets to copy.

The actual prototype images from the previous conversation are not stored in this repository. Add selected reference screenshots only with rights and provenance understood.

## Device feedback — 14 October 2026

- Recent purchases are optionally visible through the overflow menu; the preference persists. Hiding the section never deletes purchase events. Undo and full-history affordances use icons with Hebrew accessibility labels. Keep words where an icon cannot communicate a choice, such as menu entries and unit names.
- Opening inline details must not run a second SwiftUI geometry/fade animation alongside the native List update. Preserve the summary note and photo marker so the row's main content doesn't jump when details expand. Editor transactions suppress extra animations; completion and undo retain short Reduce Motion-aware transitions.
- Gesture hit-test frames use a non-observable registry. Geometry changes must not invalidate the whole list on each animation frame. Remove invisible rows from that registry. Inline Enter/add updates use the same non-animated editor transaction.

## Inline editing and iPad — 15 October 2026

- The bottom New Item action is the sole primary add affordance. It creates a temporary row in the list. Enter commits and continues; Done commits a nonempty row and dismisses the editor, or removes an empty row. Preparation remains in the overflow menu.
- The product name opens the same active-row editing surface used by the new-item flow. Moving keyboard focus from the name to the note must save the name without closing the row. Selecting a different row or list commits the current edit first.
- Quantity controls are disclosed by a small quantity button. Ordinary rows omit quantity one without a unit, and place meaningful quantity beside the name. Info is shown only on the active row. Quantity, unit and custom-unit editing share one component across new and saved items.
- New rows support a note, photo, urgency and section before committing. The composer remains at a stable list position while choosing a section; only committed items enter their destination section.
- Section headers use secondary typography. Empty sections are hidden initially; an overflow toggle reveals them for organizing and drop targets. Creating a section or entering reorder mode also reveals empty sections.
- Regular-width windows use a native split view with a list sidebar and a centered shopping list capped at 760 points. The native inspector presents extended item details beside the list where space permits and adapts to a sheet in compact windows. Compact windows keep the phone layout. Command-N starts adding, Command-Return finishes an edit.
