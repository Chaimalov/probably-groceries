# Product brief

## Job to be done

Before a grocery trip, the user and his wife see one shared list that remembers recurring needs without requiring anyone to manage a home inventory. During the trip, checking off purchases creates the history that improves the next list. The user also sees it on his iPhone and iPad through iCloud.

## v1 flow

1. **First launch:** empty list, one prominent add field, a short explanation that purchases teach the app. No lengthy onboarding.
2. **Add:** type a product, reuse existing names via autocomplete, set an optional quantity (default 1). Manual items stay on the active list until purchased or removed.
3. **Shop:** tap to check off a row. Persist a purchase event and move it to a compact purchased section. Undo immediately if tapped by mistake.
4. **Return:** candidate suggestions appear in “You'll probably need” and “Maybe”; one tap adds to the list. A “Not yet” action defers a candidate until a reasonable later date. Manual removal is not silently treated as a purchase.
5. **Review:** a simple per-item history and a way to correct a mistaken purchase or quantity. Predictions derive from the corrected event log.

## Rules

- One canonical product identity per household list; case/whitespace normalization for initial autocomplete, manual merge later if needed.
- Quantity is a positive integer in v1. Keep display names human-readable, including Hebrew.
- A product can have an active manual/list row, a suggestion, or be recently purchased. Do not show duplicate active rows.
- Predictions never commit a purchase event. Only user check-off does.
- Respect deferral and do not re-add immediately after a rejection.
- Local shopping works offline. Personal iCloud sync catches up after connectivity returns; a sync error must not block local edits.
- The user's iPhone and iPad sync through his iCloud account; his wife joins the same list from her separate Apple Account through CloudKit sharing.

## Acceptance for personal v1

- Can complete one real grocery trip on an iPhone, including add, check-off, quantity, undo and correction.
- After a few repeat purchases, plausible recurring products appear without manual stock maintenance.
- The app remains useful when predictions are missing, Jev is unavailable, iCloud is unavailable or the network is offline.
- A widget shows current context and performs at least one action whose outcome appears in the app.
- Personal iCloud sync is accepted after initial sync and offline add/check-off/undo converge between the user's iPhone and iPad.
- Household sharing is accepted after the wife accepts an invite on her Apple Account and both accounts converge on add/check-off/undo, including offline edits.

## Learn from use

For 2–3 weeks, inspect false positives (suggested too soon), false negatives (added manually before suggestion), duplicate names, and friction in check-off. Adjust thresholds from this evidence. No telemetry server is required; a local diagnostics screen or export is enough.
