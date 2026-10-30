# Reminders implementation audit — 30 October 2026

Baseline: `b2d6617` (main). Contract: Probably-Groceries-Final-Implementation-Spec.md v2.0, 30 October 2026. Visual references: the six user-provided IMG_1162–1167 screenshots in the Reminders Fidelity bundle. Older botanical directions and the HTML prototype are superseded.

| Area | Existing / verified in source | Gap / required change |
| --- | --- | --- |
| Persistence, CloudKit | Atomic local JSON, durable revision journal, tombstones, subscriptions, background notifications, retry and incremental zone cache | Preserve. Two-account latency and delivery require signed devices; record-level conflict resolution can overwrite independent concurrent field edits. |
| Watch | Cached snapshot, durable commands, application context, live replies and queued user info; latest main includes background refresh fix | Preserve; physical Watch/phone delivery still needs validation. |
| Widget | App Intent check-off, list/item deep links, small/medium/large/extra-large layout | Preserve; physical widget validation required. |
| Navigation and list | Native NavigationStack, List, menus; quantity, flag, notes, photo, native drag previews | Replace botanical colors, restore large colored native title, remove aisle decorations and persistent suggestions, float icon-only add. |
| Editing | Transient draft, Enter below same section, empty input guard, quantity and shared inline tools | Preserve behavior; remove redundant scroll-to on every Enter; expose quantity/section in focused tools. |
| Completion | Immediate persisted purchase, stable IDs, purchase Undo/Redo | Add transient checked placeholders to keep all subsequent tap targets fixed. No timers and no model/schema migration. |
| Sections | Visible empty sections, collapsed remaining count, styles, rename/delete with explicit move-to-other choice, reorder | Persist local collapse state per list; remove decorative icon/color in main list; add section-local add affordance and direct management menu. |
| Search | Missing | Native searchable interface, contextual filtering and restoration of prior visible row. |
| Menus | Native overflow, settings, list deletion only inside settings | Group overflow; direct list details, completed visibility, sections and destructive deletion; prominent native sharing action. |
| Suggestions | Permanent likely/maybe sections plus inline autocomplete and preparation | Remove permanent suggestions; preserve preparation and contextual autocomplete with usual quantity. |
| Clarification | Item-scoped question/answer/photo, conflict check, local-save and sync status | Preserve. Dedicated partner alert, unread receipt and item notification routing do not exist; do not claim implemented by generic silent CloudKit push. |
| Accessibility | Semantic fonts, RTL, 44pt controls, VoiceOver actions, Reduce Motion | Keep, check Dynamic Type and quantities; screenshots are required for visual acceptance. |
| Release | PR host-domain tests + unsigned iOS/Watch builds; main checks trigger signed TestFlight upload and existing group distribution | Reuse. Local environment has no Swift/Xcode/simulator; CI and signed-device verification must be distinguished. |

Implementation order: P0 stable completion presentation; P1 native fidelity/search/menus/editing; P2 contextual shopping tools; focused domain and UI validation; review, merge, existing release pipeline. No new backend, sync transport, widget or Watch UI rewrite.

Approved deviations: compact secondary quantity, remaining count on collapsed aisles, checked rows retained until explicit transition, contextual clarification/completions, purpose-built Watch/widgets. CloudKit sharing uses UICloudSharingController: Reminders' first-party Messages/FaceTime collaboration popover is unavailable through that public controller.


## Screenshot-driven corrections

The first actual simulator captures (run 337, before final calibration) revealed a permanent bottom search field, oversized row rhythm, small aisle headings and a small add button. The native bottom search toolbar is now hidden while search is inactive; row rhythm is 44pt with 24pt circles, 40pt text-column offset and horizontally expanded 44pt hit regions that do not overlap adjacent rows. Aisle headings use semantic bold title2; controls keep native glass. The reference viewport is 393×852pt and the fidelity suite now creates an iPhone 15 simulator of that size instead of accepting the runner's first iPhone model.

Two initial UI runs stopped in test navigation: Hebrew bidirectional isolation characters defeated an exact label match, then native menu presentation changed the presenting control's accessibility type. Stable item IDs and an outside-menu dismissal fix the test without changing application behavior. The captured list/menu remain useful audit evidence; they do not establish that later steps passed.
