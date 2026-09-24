# Prediction contract

## Baseline, all offline

1. Gather purchase events per product. Ignore corrected events and compute elapsed days between distinct shopping events.
2. With fewer than three purchases, keep a candidate in **Maybe** or require explicit opt-in; do not pretend a pattern exists.
3. Estimate interval with median or a recent weighted interval; bound it to avoid one exceptional trip dominating.
4. Compute progress since the most recent purchase relative to the interval, adjust lightly for accepted/deferred feedback, and cap it to a sortable internal score.
5. Derive usual quantity from recent purchases (mode or median); never ask Jev to calculate it.
6. Suppress active list entries and current deferrals. Promote at a conservative threshold; lower scores may appear in Maybe.

Initial thresholds are tunable constants, not claims about calibrated probabilities. Keep features and threshold decisions available in a local debug view. Avoid displaying a percent in the consumer UI.

## Feedback semantics

- **Purchase:** strongest positive timing signal.
- **Accept suggestion:** weak positive signal until purchased.
- **Not yet:** suppress for a short interval; repeated deferrals should shift future timing later.
- **Manual add before predicted:** record as an ordinary list action, then evaluate as a false negative if purchased.
- **Delete list entry:** removal only; do not mark purchased or permanently blacklist.
- **Correction/undo:** remove or reverse the mistaken purchase signal and recalculate.

## Evaluation examples

Build tiny table-driven fixtures with repeat weekly milk, irregular one-off birthday candles, bulk toilet paper, changing quantities, two purchases on one day, and deferral. Assert sorting and suppression behavior, not exact confidence calibration. Compare suggested versus manually added items during household use before tuning.
