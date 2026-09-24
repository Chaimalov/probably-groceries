# Product brief

## Job to be done

Before a grocery trip, see a list that remembers recurring needs without requiring anyone to manage a home inventory. During the trip, checking off purchases creates the history that improves the next list. Two household members should eventually see the same list.

## v1 flow

1. **First launch:** empty list, one prominent add field, a short explanation that purchases teach the app. No lengthy onboarding.
2. **Add:** type a product, reuse existing names via autocomplete, set an optional quantity (default 1). Manual items stay on the active list until purchased or removed.
3. **Shop:** tap to check off a row. Persist a purchase event and move it to a compact purchased section. Undo immediately if tapped by mistake.
4. **Return:** candidate suggestions appear in “You'll probably need” and “Maybe”; one tap adds to the list. A “Not yet” action defers a candidate until a reasonable later date. Manual removal is not silently treated as a purchase.
5. **Review:** a simple per-item history and a way to correct a mistaken purchase or quantity. Predictions derive from the corrected event log.

## Rules

- One canonical product identity per household; case/whitespace normalization for initial autocomplete, manual merge later if needed.
- Quantity is a positive integer in v1. Keep display names human-readable, including Hebrew.
- A product can have an active manual/list row, a suggestion, or be recently purchased. Do not show duplicate active rows.
- Predictions never commit a purchase event. Only user check-off does.
- Respect deferral and do not re-add immediately after a rejection.
- Local shopping works offline. Cloud sync and Jev are enhancements, not prerequisites.

## Acceptance for personal v1

- Can complete one real grocery trip on an iPhone, including add, check-off, quantity, undo and correction.
- After a few repeat purchases, plausible recurring products appear without manual stock maintenance.
- The app remains useful when predictions are missing, Jev is unavailable or the network is offline.
- A widget shows current context and performs at least one action whose outcome appears in the app.
- The household sync branch is accepted after real two-device edit and offline reconciliation, if chosen for the first personal release.

## Learn from use

For 2–3 weeks, inspect false positives (suggested too soon), false negatives (added manually before suggestion), duplicate names, and friction in check-off. Adjust thresholds from this evidence. No telemetry server is required; a local diagnostics screen or export is enough.
