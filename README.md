# Probably Groceries (working title)

A personal iPhone shopping list that learns from purchases and quietly suggests what the household may need next. Native SwiftUI, interactive widgets, and an optional Jev judgment layer.

## The loop

1. Open one calm list. Add items quickly or accept a suggestion.
2. Check off items **when bought**. A check-off writes a purchase event with quantity and time.
3. On the next visit, local predictions use purchase intervals and feedback to sort products into **You'll probably need** and **Maybe**.
4. Accept, defer, or ignore a suggestion. No inventory entry or stock counts.

The app must be useful with zero history. Predictions improve through ordinary shopping. The user can always add, edit, undo, and override.

## v1 scope

- Native iPhone app in SwiftUI, local persistence, fast add, shopping and purchased states, purchase history.
- Deterministic offline predictions with conservative cold-start behavior and transparent debug data.
- Small and medium WidgetKit widgets; one useful App Intent action (add or defer a suggestion) from the widget.
- Optional Jev integration for a narrow judgment, guarded by a local fallback and an opt-in API key stored on device.
- Household sharing via CloudKit is a later v1 branch once the local loop works on a device.
- Hebrew and English text with RTL support; design starts from the approved calm iOS prototype direction.

Out of scope for v1: pantry/inventory tracking, receipts, barcode scanning, recipe import, commercial accounts, analytics SDKs, subscriptions, and an App Store launch.

## Start here

- [Product and acceptance](docs/PRODUCT.md)
- [Design direction](docs/DESIGN.md)
- [Data and architecture](docs/ARCHITECTURE.md)
- [Prediction contract](docs/PREDICTION.md)
- [Jev spike](docs/JEV.md)
- [v1 dependency graph](docs/ROADMAP.md)

The repository starts with decisions and issues. The Xcode project is the first implementation task. Keep dependencies small, ship to a personal device early, and change the model when actual household usage disproves it.

## First device build

The first SwiftUI slice is in `App/`: quick add, local list, purchase check-off, undo, and a conservative recurring suggestion. Data is saved on this device. Widgets, CloudKit and Jev remain subsequent issues.

On a Mac with Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen), run `xcodegen generate`, open `ProbablyGroceries.xcodeproj`, set your signing team in the app target, and run on your iPhone. The generated project and Info.plist are ignored by git. GitHub Actions runs an unsigned iPhone simulator build on macOS after each push; it cannot produce an installable iPhone build without signing.

To check membership, sign in at [Apple Developer Account](https://developer.apple.com/account/) using the Apple Account you enrolled with. An active Apple Developer Program membership enables TestFlight and iCloud capabilities; a free Personal Team can run a personal build from Xcode but requires periodic reprovisioning. Do not put signing certificates, keys or provisioning files in the repository.

## Working rules

No purchase history is inferred from merely tapping “add.” Check-off means purchased. Record an explicit outcome for rejected/deferred suggestions so the same candidate does not instantly return. Avoid claiming numeric confidence to the user before it is calibrated. Never commit API keys or personal purchase data.
