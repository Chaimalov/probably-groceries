# Groceries — Product & Interaction Design PRD

Version: 1.0 · 14 October 2026 · Owner: Chaim Malov

## 1. Status and instructions to implementing agents

This document records the product and design interview in the Groceries project. It is the implementation brief for the next design iteration, not a description of the current codebase. The repository was not inspected while writing it. Inspect existing models, sync, UI and deployment instructions before estimating or changing code.

User-approved decisions are marked **Approved**. Concrete defaults supplied by the designer are marked **Proposed implementation default**. Future capabilities are explicitly separated from the first delivery. Do not imply that proposed engineering values were user-approved or validated on a device.

Recommended repository location when implementation begins: `docs/product/Groceries-PRD-v1.md`. Add a short pointer in the existing root agent instructions and README, preserving their other instructions. This delivery is a project document; it has not been committed to GitHub. Each implementation handoff should name this document and its version.

Priority: written requirements take precedence over generated mockup details. The concept images contain known deviations and cannot be used as pixel-exact specifications. Use native iOS components and validate behavior on a physical device. Do not replace native interaction with a visual imitation merely to match an image.

## 2. Product vision

**The household list that knows us.**

A grocery list preserves a familiar household ritual: someone notices what is needed, someone plans the coming days, and someone goes shopping. The app should carry intent from home to shelf, reduce repeated preparation, and make finding the correct product easier.

The long-term value is solving the historical friction for both planner and shopper: repeated list entry, forgotten essentials, ambiguous names, unavailable products, and unnecessary purchases. The immediate experience remains a simple, trustworthy list.

**Approved:** target a broad audience seeking a smart grocery list. The first reference workflow is a shared household: Harel adds items as things run out and around weekly meal planning; Chaim shops and marks each product when taking it from the shelf. Roles are contextual; do not hard-code gender or permanently assign planner/shopper roles.

Design principle: familiar in operation, original in how it understands and helps. Native navigation, editing, swiping, dragging, typography and accessibility establish familiarity. Helpful preparation and item-specific context establish personality.

## 3. Problems and desired outcomes

| Problem | Desired outcome | First delivery |
| --- | --- | --- |
| Repeatedly building the same list | Start from a useful draft and correct it | Required |
| Forgetting recurring items | Show explainable proposed additions | Required when history supports it |
| Unfamiliar vegetable or vague product name | Preserve a useful photo and clarification beside the item | Photo/note required; live clarification later |
| Too many steps to add or edit | Inline entry and quantity correction | Required |
| Jumpy editing and unstable gestures | Predictable native interaction and stable touch targets | Required |
| Items unavailable or not yet marked | Carry them forward without treating them as purchases | Required |
| Shopping across multiple places | Optional place assignment and filtering | Required |
| Buying something already at home | Easy review and exclusion of proposed items | Required; inventory knowledge later |

Purchase history is evidence of buying habits, not proof of current household inventory. Never present an inferred shortage as an observed fact.

## 4. Scope and delivery sequence

### First delivery: list, preparation and context

1. Design A text-first active list, inline add/edit, quantity/unit, optional note/photo.
2. New-shopping draft with retained items and suggested additions, editing, manual add, reversible exclusion and one confirmation.
3. Optional shopping places, type-based sections, filtering and carry-forward semantics.
4. Immediate purchase marking, optional purchased visibility, undo, stable native gestures and restrained motion.
5. Shared-state/offline handling, accessibility and validation of existing reorder behavior.

### Following delivery: clarification attached to an item

Item-specific question, camera/photo attachment, answer and optional promotion of the answer into reusable product context. Harel is usually available; design for quick exchange while still supporting delayed answers. This is approved as a direction, not a requirement to build a full messaging platform in the first delivery.

### Long-term exploration, not commitments

Meal-aware planning, inventory confidence, duplicate purchase prevention beyond list deduplication, increasingly personalized predictions and substitution assistance. No autonomous inventory claims, mandatory catalog matching, general household chat, engagement streaks or promotional AI dashboard in this iteration.

## 5. Information architecture

**Approved:** begin with the household, not mandatory store selection. The list persists across shopping sessions. A shopping session groups observed purchase activity; a new-shopping draft prepares additions to the persistent list.

| Concept | Meaning |
| --- | --- |
| Household | Shared context and participants |
| List | Persistent set of things to buy; preserve existing multiple-list capabilities |
| Section/category | One concept: product-type grouping such as vegetables or dairy |
| Shopping place | Optional preference such as supermarket, Motty or pharmacy |
| Product memory | Reusable name, approved identifying context and history |
| List item | Current request, quantity, unit, note/photo and optional place |
| Draft suggestion | Proposed addition; not yet an active shared request |
| Purchase event | Actual marking with actor and exact timestamp |
| Shopping session | Logical grouping of purchase events; not a container that deletes remaining items |

Do not conflate category with place. A product can belong to dairy and have a preferred store. Existing place-like sections need a reviewable migration or compatibility mapping; do not silently reinterpret all section names. Preserve manual ordering and supported list customization.

## 6. Active list screen

**Approved visual direction: A.** Text first, minimal chrome, no row dividers, no card per product, no empty thumbnail placeholders. Dark and light modes must both be designed. Green is the default accent; preserve list color customization.

Structure: native navigation and list title; optional participant context; optional place filter when useful; collapsible sections; active rows; optionally visible collapsed/expanded purchased area; bottom add control.

### Row anatomy

In Hebrew RTL, completion control sits on the right, followed by product text. Name is the primary information. Quantity and unit are compact and readable; use one line when it fits, a secondary line when useful. A meaningful short note can appear below. A small thumbnail is present only when a photo exists. Its placement is consistent and distinct from the completion target. A discreet details icon opens the item sheet. Give icon controls accessible labels.

**Proposed defaults:** 16pt horizontal content inset, native body typography, minimum 44×44pt hit areas, ordinary rows approximately 52–60pt high, photo/detail rows approximately 68–80pt. These are starting values, not fixed heights: Dynamic Type and multiline text expand the row. Thumbnail approximately 36pt; 8–12pt gap between semantic elements. Prefer semantic system text/background colors to hard-coded grays.

Store metadata is secondary. Urgency is a small distinct symbol, not a forced reorder. Section headers use weight and spacing; accent sparingly. Avoid repeated AI symbols or banners in the shopping flow.

### Add and edit

**Approved:** tap the name to edit inline; separate details control opens the sheet. Enter commits the item and keeps entry ready for the next item. An obvious native plus control reveals/focuses inline entry. Adjust quantity during entry without opening a full editor. Optional units are progressively disclosed.

Support natural input such as “בשר טחון 2 חב”. Parsing must be reversible: expose the detected quantity/unit, retain ambiguous original text and never discard a meaningful number. Do not require catalog selection or category/place before adding. Empty submissions create nothing. Cancel is an x icon with an accessible label. Keyboard dismissal, external updates and focus changes must not lose entered text.

### Purchase marking

**Approved:** marking immediately moves an item to purchased; purchased visibility is optional. Provide quick icon-based undo plus restoration from purchased. Record actor and exact timestamp. Restore the item's identity, quantity and context on undo; do not create a duplicate.

The check state responds immediately. Collapse/reflow must not cause a rapid second tap intended for the same control to mark the next item. Validate this explicitly on device; tune native transactions and event handling rather than imposing a noticeable delay on purchase state.

Purchased area is in scrolling content, not a permanent bottom overlay. Its visibility preference is local to the user/device unless existing settings dictate otherwise. Hiding it must never delete purchase history.

### Swipe and reorder

Keep swipe actions brief and high-contrast; deletion is red. Use familiar icons where meaning is clear. Long press lifts a populated preview of the actual row; move and drop reorder items. Sections reorder too. Preserve the requested ability to add other rows to an active multi-item drag where supported. Do not show blank preview rectangles. Resolve drag, text selection, scrolling and swipe conflicts with native gesture behavior. Accessibility exposes equivalent move/action commands.

Manual route ordering must not change unexpectedly while a user is shopping. Purchase order can inform future ordering using actual timestamps, including when multiple shoppers contribute; it does not override current deliberate reorder.

## 7. New-shopping preparation

**Approved:** user explicitly chooses “קנייה חדשה”. The app prepares a draft, rather than silently adding predictions to the live list. Two groups: “נשארו ברשימה” and “השלמות מוצעות”. Existing open requests remain included; proposed additions are preselected. One confirmation applies the reviewed additions.

Required operations: edit name/quantity/unit, add a manual product, exclude a proposed item with minus, undo exclusion, open details, filter by shopping place and confirm. No purchase circles in planning. Excluding a proposal affects the draft, not active items or past history. Removing an existing active request is a separate explicit operation; do not make cancellation of the draft delete anything.

Opening/cancelling/reopening preserves the active list. **Proposed default:** preserve unfinished draft edits locally and offer continuation when returning; cancel closes without committing. Confirmation is atomic/idempotent from the user's perspective and returns to the active list. Repeated taps/retries create no duplicates. Record a confirmation token if needed.

Do not duplicate items already active. Match by stable product identity where possible, not only string similarity. Similar names with different required forms must not be silently merged.

### Optional place filter

“הכול” is the default. Show assigned places only when they exist; do not require creating them. Selecting Motty changes which rows are visible, not which rows are included. Under a filtered draft, confirmation explicitly says “האישור כולל את כל הרשימה”. Hidden exclusions and edits remain intact. Products without a place remain visible under All; an assigned-place view must not imply that unassigned items are forbidden there. Provide a discoverable way to see them without guessing a store assignment.

The generated draft comparison accidentally displayed different suggestion sets between All and Motty. Implementation must filter one underlying draft, never regenerate it on filter change.

### Prediction and trust

Show a concise reason only when useful, for example “נקנה בדרך כלל מדי שבוע”, based on actual evidence. No fabricated confidence percentage. Distinguish an explicit household request from a suggestion. No history: useful empty/manual state, not invented habits. Unavailable prediction service: manual preparation and retained items continue to work.

Accepting a suggestion is planning, not a purchase. Excluding a suggestion is not proof the household dislikes the product. Unpurchased retained items do not increase purchased frequency. Only real purchase events train purchase intervals and route history; undo corrects that evidence. The algorithm and thresholds need repository-specific design and tests before deployment.

## 8. Shopping sessions and unfinished items

**Approved:** shopping is usually a sprint; a few hours without marking likely signals its end. No mandatory finish-shopping action.

**Proposed implementation default:** start with a configurable internal 3-hour inactivity threshold measured from the latest purchase event; this value was not selected by the user. Treat session completion as tentative bookkeeping, not a destructive action. Recompute on next foreground/sync; do not assume an iOS background timer runs exactly on schedule.

Later markings work normally and may start a new logical session. Unpurchased items persist unchanged. Distinguish unavailable/deferred items from purchases if recording a reason; do not force the user to explain every leftover. A new-shopping action never clears open requests or resets quantities automatically.

## 9. Item details and future clarification

Open a native sheet with product name, quantity/unit, identifying photo, note and optional category/place. Photo can expand for identification. Support camera and photo library with cancellation and permission-denied paths. No decorative generated product image presented as the intended real product.

Following delivery: a small clarification action opens a short thread attached to the item. Shopper can ask “זה מתאים?” and attach a shelf photo. Other participant receives context and answers directly. Pending, sent, failed and answered states are distinct; offline questions remain pending with retry. Usually immediate answer, but delayed answers remain discoverable near the item. Do not require either person to leave the shopping context.

Do not automatically turn every conversational answer into permanent product truth. Offer explicit saving of a useful photo/clarification. Requests and notifications must respect household membership/access and existing privacy settings. General chat, calling infrastructure and automatic substitution purchase are out of scope.

## 10. Visual and motion system

### Native material

Use platform-native Liquid Glass for navigation/floating controls where supported, with a native material fallback on older supported OS versions. The repository determines deployment targets. Product content remains readable on stable surfaces. Avoid stacked glass panels, glow borders, custom imitation navigation and tiny low-contrast circles. Validate Reduce Transparency, increased contrast and light/dark appearance.

### Motion specification — proposed starting values

| Interaction | Intent | Starting behavior |
| --- | --- | --- |
| Press | Acknowledge touch | Native highlight/press response, no row bounce |
| Mark purchased | Confirm and explain destination | Immediate check; short 180–240ms collapse/reflow |
| Inline edit | Maintain orientation | Preserve row/scroll anchor; 150–200ms local transition if needed |
| Quantity | Show the changed value | Small content transition; no full-list animation |
| Draft exclusion | Make removal reversible | Short fade/collapse and reachable undo |
| Place filtering | Explain changed subset | Brief fade; preserve edits; no flying rows |
| Details | Reveal context | Native sheet presentation/dismissal |
| Drag/drop | Convey physical pickup | Native lift/shadow and populated preview; controlled settling |

Use scoped transactions. Never attach a broad animation to the full observable store. Sync updates and keystrokes must not animate unrelated layout. Respect Reduce Motion with minimal fades or immediate transitions. Native timing wins when custom timing creates inconsistency. Interruptions and rapid taps must remain correct.

Haptics: proposed light confirmation on purchase and native feedback for lift/drop where provided. No double feedback from custom plus system haptics, no feedback for every character, no custom patterns required in this iteration. Haptics are supplementary to visual/accessible state.

## 11. Shared state, offline and data integrity

Both participants can add/edit/shop. Optimistic local interaction remains usable offline, with subtle sync status and explicit actionable failures. No fake success on rejected writes. Draft generation cannot overwrite active changes arriving from another participant.

At confirmation, merge against the latest active list: retain newly added requests, avoid duplicates, honor confirmed removals and never resurrect purchased/deleted items from a stale retained snapshot. User edits to an explicit request must not be overwritten by a prediction. Conflicting quantity edits require a documented repository-specific policy.

Keep stable item/product identities separate from presentation order. Photo loading never blocks text or marking. Place changes affect metadata, not purchase history. Undo semantics across concurrent edits must be defined and tested. Do not rebuild working CloudKit sharing solely for this design iteration.

## 12. Accessibility and localization

Hebrew RTL first, plus correct LTR layout. Use logical leading/trailing alignment and locale-aware quantities; preserve mixed Hebrew/Latin product names. Do not copy the concept board's incorrect back-chevron direction into the implementation.

VoiceOver announces name, quantity, meaningful note, purchase state and available actions. Photos need meaningful descriptions when available. Icons have localized labels; color alone never carries state. Support Dynamic Type, sufficient contrast, 44pt targets, keyboard focus and accessible undo. Keep essentials visible above the keyboard and away from safe-area overlaps.

## 13. Reference mockups and known corrections

Reference 1: two dark list concepts A/B generated during this interview; A selected. Reference 2: household draft / place-filtered draft comparison; structure accepted. Images illustrate intent, not implementation proof.

Mandatory corrections: remove row dividers; remove purchase circles from preparation; maintain one identical underlying draft across filter views; fix native RTL navigation; reduce excessive section gaps; keep completion targets visible; show user-provided identifying photos; make purchased area scroll with content and optional; preserve a manual-add route in preparation.

## 14. Acceptance criteria

| ID | Scenario | Pass condition |
| --- | --- | --- |
| AC01 | Add “מלפפון 5 יח׳” | One item, correct editable quantity/unit; repeated Enter remains fast |
| AC02 | Ambiguous numeric name | No destructive parsing; original intent remains recoverable |
| AC03 | Edit while scrolling/keyboard shown | Stable focus/scroll; unrelated rows do not jump |
| AC04 | Rapid purchase taps | Correct intended products marked; next row not accidentally hit |
| AC05 | Undo purchase | Same item/context restored; learning evidence corrected |
| AC06 | Hide purchased | Active list clearer; purchase history retained |
| AC07 | Lift and multi-drag | Actual preview visible; order persists; no swipe/edit conflict |
| AC08 | New shopping with leftovers | All open requests retained; no false purchase events |
| AC09 | Exclude suggestion then undo | Draft-only reversible change; active list untouched |
| AC10 | Filter to Motty | Same draft subset; all-list confirmation scope explicit |
| AC11 | Confirm twice/retry offline | No duplicate additions; outcome/sync state understandable |
| AC12 | Partner updates during draft | Merge preserves current requests; stale items not resurrected |
| AC13 | No history/prediction failure | Manual planning fully usable; no invented recommendations |
| AC14 | Long inactivity | Session bookkeeping only; remaining products untouched |
| AC15 | Missing photo | Plain compact row; no placeholder box or blocked action |
| AC16 | Dark/light, RTL/LTR, accessibility | Readable controls, expanding text, correct native navigation |
| AC17 | Reduce Motion/Transparency | Complete usable flow with appropriate native fallbacks |
| AC18 | Relaunch/offline sync | Draft/list/order/context behavior matches documented persistence |

Future clarification acceptance: question/photo linked to correct item; recipient sees context; answer discoverable; delayed/offline/failed sends represented; saving context requires explicit action.

## 15. Implementation plan and validation

First inspect existing code and produce a short delta map: existing/partial/missing for each requirement. Preserve working functionality and use native building blocks. Implement in reviewable slices: (1) list/inline edit stability, (2) draft/place model and semantics, (3) prediction integration, (4) photo/details, (5) interaction/accessibility polish. Clarification follows separately.

Required checks focus on meaningful risks: draft idempotency and concurrent merge; purchase/undo learning; carry-forward and session boundaries; parser ambiguity. Validate UI on device for drag previews, rapid marking, keyboard editing, dark/light and accessibility. Generated images do not validate Liquid Glass, animation smoothness or touch behavior. Run repository-required checks; avoid redundant broad CI runs after unchanged successful validation.

Evidence to include in implementation handoff: changed scope, acceptance criteria checked, real screen capture of list/preparation/details, physical-device motion findings, remaining limitations and build/distribution status. Do not claim TestFlight delivery without verifying the actual release outcome.

## 16. Success measures and remaining engineering decisions

Assess through observed tasks: steps/time to add and change quantity; preparation effort from draft to confirmation; accidental marking/undo frequency; identification questions repeated for the same product; subjective stability and trust. No invented adoption targets or mandatory external analytics; prefer privacy-preserving local evaluation for initial iterations.

Before implementation settle from the actual codebase: minimum supported iOS and native material availability; how product memory maps to list items; exact deduplication/concurrency policy; existing list/section migration; prediction confidence/sample thresholds; local/shared draft ownership and persistence. The 3-hour session threshold and proposed motion/dimensions are tunable defaults, not blockers requiring another product interview.

The first version should feel like the familiar household list, with less repeated work and better context. Every added control must justify the effort it saves for planning or shopping.
