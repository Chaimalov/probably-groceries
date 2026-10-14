# PRD v1 implementation delta and validation

Brief: Groceries-PRD-v1.md, version 1.0 (14 October 2026).

| Requirement | Baseline | Change |
| --- | --- | --- |
| Native list, inline add/rename/quantity, sections, multi-row drag | Existing | Preserve; 44pt completion, identifying thumbnail, separate details sheet |
| New-shopping preparation | Missing | Locally saved draft per list; editable suggestions/manual additions; reversible exclusions; one confirmation |
| Optional shopping places | Missing | Separate item metadata; All/unassigned/place filters in list and preparation; filter never changes inclusion |
| Prediction evidence | Existing local engine | Reuse conservative three-trip predictor; proposals move into preparation; excluding is local draft state |
| Carry-forward/concurrent draft merge | Missing | Retained rows are live, never committed from a snapshot; additions deduplicate by product identity |
| Notes/photos | Existing local attachments | Details, photo enlargement, camera with denied/cancel path; bounded JPEG payload sync through existing item/purchase records |
| Purchase/undo | Existing | Preserve actor device identity, place/photo context and original manual order; freeze remaining route on check-off |
| Sessions | Existing 12-hour route grouping | Three-hour inactivity route bookkeeping; no destructive finish action |
| Shared state/offline | Existing revision journal/CloudKit | Preserve transport; one publish/persist for draft confirmation |

## Policies

Drafts are device-local and scoped to list ID. Closing retains edits. Place filters select a subset of the same draft. Confirmation includes all included proposals, including hidden ones, and never creates purchase evidence. Stable draft-row IDs plus active product deduplication make retries safe. A local confirmation receipt is saved atomically in shopping.json with the additions; it prevents repeated submission even after restart and later purchase. Confirmation stays open after storage failure for retry. Cross-device new manually named products still have the existing product identity limitation: independently created identities are not automatically merged by fuzzy matching.

Explicit active-item removal records a timestamped temporary deferral, synced through the existing journal, so an older draft cannot resurrect the removed request. Draft exclusion itself never records a deferral or purchase.

Fresh manual additions carry their own request time. A resumed draft’s age must not suppress an explicit new request merely because the product was purchased after the draft was first opened; older pending proposals remain protected against later purchases/removals.

Retained requests are edited through live details, so those explicit changes apply immediately and remain if preparation is closed. Draft name edits for existing products apply only if the current product name still matches the original name; newer remote names win. Existing active quantity always wins over a suggestion. Ordinary simultaneous shared quantity edits retain the repository's entity-level last-revision policy (timestamp, deterministic payload tie break). Undo into an independently created active request adds the undone quantity and preserves its newer context, correcting purchase evidence without duplicating the product.

New photos carry a compressed JPEG in the existing Codable payload, bounded below 600KB to stay below a CloudKit record's payload limit. Available legacy local attachments migrate to bounded payloads on launch. Missing local files cannot be recovered automatically. The actor identifier identifies the originating installation, not a claimed participant display name.

## Validation

Added atomic receipt/idempotency, concurrent request/rename, exact-name batch deduplication, hidden inclusion/context and no-learning-on-exclusion checks; added simulator close/resume/exclude/confirm coverage. Added focused unit checks for draft filtering against current active identities, exclusion/persistence, ambiguous natural input and session boundaries. Existing purchase/undo, predictor, revision journal and native UI tests remain required in the iOS workflow.

This Linux workspace cannot run Xcode or physical-device tests. CI must validate compilation and simulator behavior. Physical-device acceptance remains required for lift/multi-item drag, rapid completion, motion, keyboard/focus, camera permissions, RTL/LTR, Dynamic Type, contrast/transparency and two-account photo sync. Do not treat code or CI as device UX validation.

## Remaining first-delivery limitations

- Draft proposal details now include editable name/quantity/unit/place, note, section and identifying photo; close/reopen preserves edits and partial manual input.
- Natural input recognizes explicit trailing known units with a pre-commit preview and original-text undo. Other input remains unchanged.
- Global rapid-completion guard (350ms) prevents immediate accidental check-off after reflow; needs physical-device tuning.
- Photo compression retries at smaller sizes; load/encode/write failures are explicit. Local list writes show a retryable failure.
- Added Hebrew/English strings and native language-dependent layout for the list/preparation/details flows. Legacy diagnostics and some sharing error messages still need English copy.
- Following-delivery clarification threads are deliberately deferred per PRD.
