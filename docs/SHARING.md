# Household CloudKit sharing

Sharing shipped in TestFlight build 24. Xcode CI passed the simulator build and
local unit/UI flows. Signed entitlements and TestFlight processing were verified,
but this is not yet a verified two-account sharing build. A device report exposed
a missing Production schema type: `cloudkit.share`.

## User flow

- In the list menu, choose **שיתוף הרשימה…**. The list is uploaded before
  presenting Apple's private read/write sharing controller. Select the invited
  person's Apple Account using the system UI. No invitation is sent by this patch.
- A collaborator opens the invitation link on a device with this build installed.
  Both cold-launch and running-scene callbacks accept the share and select the
  joined list. Acceptance errors retain the invitation for an in-process retry.
- **ניהול השיתוף…** opens the system participants/permissions interface. The
  owner can revoke access; a participant can leave using the system controller.
- Local writes schedule a sync. Foreground shared lists refresh every 15 seconds;
  returning to the app and the manual iCloud command also refresh. There is no
  background push implementation in this slice.

## Data boundary and migration

- Container: `iCloud.com.chaimalov.probablygroceries`. The old `Groceries` zone
  remains private. Every list prepared for sharing gets its own `List_<UUID>`
  zone in the owner's private database and a private zone-wide `CKShare`.
- Participants read/write that zone through the **shared** database. Other
  private lists and their purchase history are excluded.
- First preparation assigns the selected list a fresh ID and copies only its
  referenced products to fresh product IDs. Existing item/purchase IDs, history,
  quantities, notes and section order remain. This avoids collisions with the
  recipient's built-in default list and isolates product edits from private lists.
- Scope metadata retains every record key ever belonging to the zone, including
  tombstones. Scope discovery runs before private reconciliation on another owner
  device. Shared keys are excluded from private merges and uploads.
- Routing is calculated after network fetches because local UI edits can happen
  while a sync awaits CloudKit. Failed uploads keep the local journal for retry.
- Reconciliation is last-writer-wins per whole entity, with deterministic payload
  tie-breaking. JSON payloads use sorted keys. Independent entities coexist;
  concurrent edits to different fields of the same row do not merge field-by-field.
- Check-off uses the source row's UUID as the purchase event UUID, so simultaneous
  check-offs of the same row converge to one purchase. Undo retains a tombstone.
- Account changes pause sync and invitations rather than copying data to the new
  account. Missing participant access retains offline data and prevents fallback
  uploads into the participant's personal database. This slice offers no explicit
  account-reset or detach-as-private-copy UI.
- Attached photo files remain local, as before. Notes and photo filenames sync;
  image bytes do not. Concurrent adds of the same newly named product can still
  create distinct rows; canonical product merging is a follow-up.
- An owner device running an older app version during migration can continue
  editing the old private list. Upgrade all owner devices before preparing a share.

## Build and verification gate

1. Generate with XcodeGen and run the existing simulator build and test jobs on
   Xcode 27. CI has passed the local unit/UI cases, including scope isolation,
   tombstone routing after restart, old-journal decoding, concurrent check-off and
   undo. Unsigned simulator checks do not validate CloudKit account access or
   the Production schema.
2. Complete the **CloudKit schema release gate** below before relying on sharing
   in TestFlight. Keep `CKSharingSupported: true` and the existing CloudKit signing
   entitlements. Both accounts must use the same CloudKit environment.
3. Owner device A: create a private second-store list, add notes and history to
   the target list, open sharing, and invite device B on another Apple Account.
   Confirm only the target list/history is visible to B and its default list stays.
4. Accept with B's app terminated, then repeat with it running. Verify selection,
   retry after offline acceptance, and no duplicate imported lists.
5. Owner iPad: confirm discovery of the dedicated zone and convergence with A.
   Test add, rename, quantity, check-off, undo and correction from both accounts.
6. Disconnect both accounts, check off the same row on both, reconnect, and
   confirm one purchase. Undo and reconnect the stale device: no resurrection.
   Make independent offline adds and confirm both remain.
7. Revoke B from A, refresh B, edit B offline, and confirm edits remain local and
   never enter B's private zone. Verify the unavailable-sharing message.
8. Cancel an invitation, stop sharing, re-open management to create another
   invitation, and verify the list remains usable locally. Change the device's
   Apple Account and confirm sync pauses without cross-account copying.

Issue #8 should remain open until the signed two-account checks pass.

## CloudKit schema release gate

TestFlight uses Production. A successful archive/upload does not deploy CloudKit
schema changes. Build 24 reported:

`Cannot create new type cloudkit.share in production schema`

This blocks saving the zone-wide share before Apple's invitation UI is presented.
Repeated retries or another TestFlight upload cannot create a missing Production
type. Complete these steps with the Apple Developer account that manages
`iCloud.com.chaimalov.probablygroceries`:

1. Open [CloudKit Console](https://icloud.developer.apple.com/), select that exact
   container and Development, then inspect Schema → Record Types.
2. If `cloudkit.share` is absent, run the app on an iCloud-signed-in device from
   Xcode with development signing and the Development CloudKit environment.
   Use **שיתוף הרשימה…** once and let the CKShare save finish. No invitation needs
   to be sent. This registers the system share type in Development; do not try to
   create a custom record type with that reserved name in the console.
3. Confirm Development contains `cloudkit.share` and `ShoppingEntity` with
   `modifiedAt`, `payload` and `deleted`. Use **Deploy Schema Changes** to deploy
   the schema to Production, and verify the types appear there. This deploys the
   schema, not the development test records. Zone-change fetches need no query
   indexes.
4. On the existing TestFlight build, reopen sharing or tap **ניסיון נוסף**. Verify
   that Apple's invitation UI appears, then complete the two-account checks above.
   Do not mark issue #8 complete from the schema deployment alone.

References:
- [Apple: Deploying an iCloud container's schema](https://developer.apple.com/documentation/cloudkit/deploying-an-icloud-container-s-schema)
- [Matching device failure and development-share bootstrap on Apple's developer forums](https://developer.apple.com/forums/thread/840248)

Apple references used:
- https://developer.apple.com/documentation/cloudkit/ckshare/init(recordzoneid:)
- https://developer.apple.com/documentation/cloudkit/shared-records
- https://developer.apple.com/documentation/cloudkit/ckshare/metadata
- https://developer.apple.com/documentation/cloudkit/ckfetchrecordzonechangesoperation
- https://developer.apple.com/documentation/uikit/uicloudsharingcontroller
