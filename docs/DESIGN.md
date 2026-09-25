# iOS design direction

The preferred prototype is the calm left-hand concept: large native typography, generous breathing room, clear list rows, subtle warmth borrowed from the middle concept, and minimal explanation of the prediction machinery. Use “Maybe” for uncertainty. Do not repeat “Likely” on every row or show raw percentages by default.

The selected reference shows a small date and overflow control above a short headline, an airy white list with circular check-off controls, a secondary quantity line, and a restrained “Maybe” divider. A pill-shaped quick-add field and a four-destination bottom bar anchor the screen. Our functional prototype keeps active items ahead of predictions; the same row language applies to both. Do not depend on product photographs or category illustrations: household products can be highly specific. History, insights, and settings must open working screens rather than decorative destinations.

## Screen anatomy

- One primary list screen, with a short human headline and visible item count.
- Active items first, suggested items next, compact purchased rows last. Keep the shopping state obvious.
- A thumb-reachable quick-add action that opens a native entry field and suggestions from history.
- Each row shows name and quantity. Completion is generous to tap and supported by VoiceOver.
- A small store picker switches lists. A menu toggles category grouping; urgent items show a flag in place without moving in the list.
- Detailed why/when and history live behind a tap; the first screen stays quiet.

## Interaction language

- A check-off gives a light haptic and a short, reversible move to Purchased.
- Accepting a suggestion promotes it to the active list. “Not yet” records feedback with a temporary snooze.
- Swipe actions may be shortcuts, but all important actions need discoverable buttons or menus.
- Use native transitions and respect Reduce Motion. No decorative animations that delay shopping.
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
