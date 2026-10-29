# Organization and clarification — 29 October 2026

## Audit against main 98c687c

| Capability | Existing implementation | This change |
| --- | --- | --- |
| Settings, list appearance/deletion | SettingsView; duplicated deletion in overflow | Keep list deletion in Settings |
| Purchase undo | Native UndoManager, shake, Command-Z, purchased rows | Preserve existing implementation |
| Move items between sections | CategoryEditor, swipes, native drag | Use the same section names everywhere |
| Section appearance | Automatic keyword-based icons/colors only | Editable name, symbol and color |
| Section removal | Missing; historical purchases recreate headers | Preserve items in Other by default, or explicitly delete them; keep history |
| Item clarification | PRD direction only; notes/photos already available | One question and answer, active/resolved status, direct row entry |
| Unavailable item | Leftovers persist without an explicit reason | Optional label with reversible toggle in item details |
| Icon badge | Missing | Opt-in local count policy and permission-aware settings |

## Interaction contract

Sections remain aisles. Long press still lifts for native drag. Swipe a header to edit, or open Settings → Manage sections to find the same editor and reorder sections. The built-in Other section is the fallback, so it is not renamed/deleted. Renames reject collisions, preserve route order and affect only the current list. Empty sections remain visible.

List settings hold infrequent configuration. Product details are directly accessible through the info icon. Clarification is accessible from the leading swipe and item tools; only an unresolved question/received answer adds a row label. The label opens the same clarification screen. Photos and identifying notes reuse the existing item context.

The clarification is intentionally a focused question/answer, not household chat. All clear removes the outstanding label and preserves the context. Reopen restores it. Saving is local first; the screen distinguishes local write failure from cloud sync waiting. Question and answer are preserved on purchase/undo. A remotely received edit detected while composing requires review before overwriting. Existing entity-level last-write-wins semantics still apply to simultaneous offline edits.

Unavailable never means purchased, never trains predictions, never hides or deletes the request, and can be cleared from item details. It stays with the request until explicitly cleared. Carry-forward works through the existing persistent list.

Badge is disabled until explicitly enabled. Defaults after enabling: the currently open list, active rows, all urgency levels, include unavailable items. Users can select all lists or a stable set of list IDs, count quantities, limit to urgent, and exclude unavailable. Empty selection means zero, removed lists cannot contribute, zero clears the badge. Permissions request badge only. Changes, received sync, widget/Watch actions (through the authoritative store), list switching and foreground refresh update the badge.

## Limits and device acceptance

This change does not add push alerts or a guaranteed background delivery channel for clarification. Existing CloudKit sync delivers context; foreground shared-list polling remains unchanged. A badge on a terminated app can remain stale until iOS allows the next sync/run. Do not claim immediate delivery to a participant or show a sent/read receipt from global sync status.

Verify on device: header swipe alongside lift/drag; same editor through Settings; rename a legacy aisle, purchase its last item, relaunch; remove and undo an old purchase without recreating its aisle; question/answer across the two Apple Accounts, offline save/reconnect; light/dark, RTL, Dynamic Type; deny/allow badges and check row vs quantity count including widget purchases. Compilation is not visual/device acceptance.

## Verification

OrganizationTests covers historical section resurrection, per-list isolation, duplicate names, deletion semantics, badge policy, backward decoding and clarification payload round trips. Existing domain checks and native app/watch compilation remain the CI gate. No simulator rendering is required for this iteration.

API references: Apple UNUserNotificationCenter setBadgeCount and Asking permission to use notifications. Badge permission is requested only after an explicit toggle.
