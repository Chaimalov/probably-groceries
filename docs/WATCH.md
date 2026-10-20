# Apple Watch shopping companion

Native SwiftUI watchOS 10+ app, embedded in the iOS app. Open Groceries on the paired iPhone once after installing. The watch defaults to the iPhone's current list until a list is chosen on the watch. The list picker then retains that watch-specific choice.

The watch shows remaining products in aisle order, quantities, shortened units and notes. Tap the whole row to put an item in the cart. Haptics confirm a saved local action. A brief input lock protects the next row from an accidental double tap. Undo stays reachable in the bottom toolbar; the menu also reveals the latest 20 purchased products. Native List scrolling supports the Digital Crown, wrapping text, Dynamic Type and VoiceOver. Hebrew uses RTL; English follows system language.

The paired iPhone is the authority for shared CloudKit state and purchase history. The watch stores a snapshot and an ordered outbox atomically on its own device. It remains usable after losing contact with the phone. Foreground messages carry changes immediately when reachable; background user-info transfers carry the same ordered pending queue otherwise. Snapshots use application context. Pending changes remain visible until the phone acknowledges them; they are never presented as already synced. Background delivery is scheduled by watchOS/iOS and is not guaranteed to be immediate.

Each command has an immutable ID, item ID, list ID, intended purchased state and timestamp. The phone saves the receipt in the same shopping.json write as the normal buy/undo operation, before acknowledging it. Duplicate delivery via foreground and background channels is ignored. Commands use their original list and item identities without changing the iPhone's selected list. Buying records the time of the watch action, capped at the current phone time. Undo uses the existing correction path and removes the learning event.

The watch has no independent CloudKit connection, photo editing, item creation or preparation flow. Prepare on the phone and shop on the watch. Watch state requires the paired iPhone to receive other household members' updates.

## Verification

Domain tests cover pending buy/undo across stale snapshots and partial acknowledgements, old-buy replay after a phone undo, and backward-compatible receipt persistence. PR CI compiles iOS and watchOS without booting a simulator. TestFlight export checks the embedded watch bundle and signature.

Before considering device acceptance complete, test on paired hardware: first install; changing lists; buy/undo in both directions; marking with the phone unreachable; killing/relaunching the watch with pending changes; reconnecting without duplicate purchases; Harel editing the shared list; Hebrew long names and accessibility text sizes. WatchConnectivity background user-info delivery requires paired-device testing.
