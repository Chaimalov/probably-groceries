# Household CloudKit sharing

Implementation prepared against main `af862af48425a7f1fb0f1bf6c40eb292e1297318`.
Published for review in PR #13 after GitHub write access was restored.
This is not yet a verified two-account device build; Xcode CI validates the
simulator build and local unit/UI flows, not signed CloudKit sharing.

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

1. Apply the patch on the stated commit, generate with XcodeGen, and run the
   existing simulator build and test jobs on Xcode 27. New unit cases cover scope
   isolation, tombstone routing after restart, old-journal decoding, concurrent
   check-off and undo. The local environment had no Swift/Xcode compiler; these
   XCTest cases have **not** been executed. A Swift grammar parser checked syntax,
   and `git diff --check` checked patch formatting; neither is a type check.
2. Keep `CKSharingSupported: true` in the generated Info.plist and preserve the
   existing CloudKit entitlement/signing setup. Both accounts must use the same
   CloudKit environment. For TestFlight, deploy the existing `ShoppingEntity`
   schema (`modifiedAt`, `payload`, `deleted`) to Production if not already done.
   Zone-change fetches require no query indexes.
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

Apple references used:
- https://developer.apple.com/documentation/cloudkit/ckshare/init(recordzoneid:)
- https://developer.apple.com/documentation/cloudkit/shared-records
- https://developer.apple.com/documentation/cloudkit/ckshare/metadata
- https://developer.apple.com/documentation/cloudkit/ckfetchrecordzonechangesoperation
- https://developer.apple.com/documentation/uikit/uicloudsharingcontroller
