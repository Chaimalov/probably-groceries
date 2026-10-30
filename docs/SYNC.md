# CloudKit and Apple Watch sync — 30 October 2026

## Findings

The previous app only started sync from ShoppingView. There were no database
subscriptions, push entitlement, remote-notification background mode, or push
handler. A foreground 15-second poll was the only automatic remote refresh.
The phone answered watch refresh requests using its local cache, without
fetching CloudKit. Phone-to-watch publication only used opportunistic
application context. Every CloudKit pass refetched whole zones and saved each
changed entity in a separate round trip.

## Implemented path

- Start connectivity and sync from application launch, including background launches.
- Subscribe to private and shared database changes using content-available pushes.
  The app delegate awaits synchronization before completing a push. No alert
  authorization is requested for these silent pushes.
- Keep an atomic checkpoint of secure-archived records and their server change
  token per database/zone. Fetch deltas and return the complete cached remote
  state for journal reconciliation. Rebuild on expired tokens or invalid caches.
  Account identity validation precedes cache use. A crash between fetching and
  merging cannot lose changes because records and token travel together.
- Batch up to 50 uploads with ifServerRecordUnchanged and per-record conflict
  resolution. Split a batch on an operation-level limitExceeded error. Keep the
  existing deterministic timestamp/payload conflict policy and tombstones.
- Coalesce simultaneous sync requests; edits arriving during upload get another
  pass. New edits cannot cancel an already-running CloudKit operation. Respect
  server retry intervals; keep all local work durable on failure.
- Send phone snapshots immediately to a reachable watch, retaining application
  context for background delivery. Watch refresh returns durable local state
  promptly, then syncs CloudKit and pushes fresh state. Offline watch commands
  remain queued with persistent receipts and optimistic state overlays.
- Handle watchConnectivity background tasks in the watch scene. Hold a finite
  iOS background task during sync, and flush when the phone scene backgrounds.
- Retain foreground polling as recovery when silent push delivery is delayed.
- Verify the exported IPA's production APNs entitlement in deployment CI.

The watch remains a companion app. A direct watch CloudKit stack would add a
second sharing/account/conflict implementation and still require lifecycle
recovery; it is unnecessary for fixing this broken companion refresh path.

## Limits and device acceptance

Silent pushes and application context are scheduled by the OS, not guaranteed
instant delivery. Force-quitting the phone app, disabled background refresh,
no phone connectivity, or an exhausted background budget can delay remote data.
The watch keeps the last saved list and queues purchases offline.

CI compilation and domain tests do not prove real APNs delivery or latency.
On two Apple accounts with the signed build installed on phone and watch:

1. Launch each phone once to register database subscriptions and APNs.
2. Background the shopper's phone without force-quitting. From the other account,
   add, rename, flag, and purchase items. Confirm both phone and watch converge.
3. Open only the watch and refresh after a remote edit. Confirm updated cloud
   state arrives while the companion phone UI remains closed.
4. Check off and undo offline on the watch; reconnect and verify exactly one
   purchase effect and no lost pending command.
5. Make conflicting offline phone edits, reconnect, and verify convergence.
6. Repeat with substantial purchase history, relaunch both apps, and compare
   refresh latency. Confirm records are fetched incrementally after relaunch.
7. Verify product details from the inline palette, including name edits, RTL,
   large type, and iPad inspector presentation.

## Apple references

- [Watch Connectivity data transfer](https://developer.apple.com/documentation/watchconnectivity/transferring-data-with-watch-connectivity)
- [WCSession](https://developer.apple.com/documentation/watchconnectivity/wcsession)
- [Watch-to-phone messages wake the companion in the background](https://developer.apple.com/documentation/watchconnectivity/wcsession/sendmessage(_:replyhandler:errorhandler:))
- [Database subscriptions and silent push](https://developer.apple.com/documentation/cloudkit/ckdatabasesubscription)
- [Change tokens](https://developer.apple.com/documentation/cloudkit/ckfetchrecordzonechangesoperation)
- [Conflict-preserving save policy](https://developer.apple.com/documentation/cloudkit/ckmodifyrecordsoperation/savepolicy)
- [SwiftUI watch connectivity background tasks](https://developer.apple.com/documentation/swiftui/backgroundtask/watchconnectivity)
