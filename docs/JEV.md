# Jev integration spike

Jev is an **optional** judgment layer. Its published endpoint accepts a structured `state`, a `model`, and a map of typed `questions`; a Noul answer returns a 0–1 `noul`. Use `jev-latest` initially and decode by the stable question IDs. [Official API reference](https://docs.typesafe.ai/api).

## Appropriate v1 experiment

The local predictor computes dates, intervals, quantities and suppression. If enabled, pass only a small per-product summary for **borderline candidates** and ask one focused question: should this item appear in “Maybe” for the upcoming shopping trip? Compare the result with the local baseline and record the decision source for debugging. The application owns thresholds, cooldowns and list mutations. Jev never records a purchase or overrides an explicit deferral.

An illustrative request shape, subject to validating it with a real key:

```json
{
  "model": "jev-latest",
  "state": {
    "product": "milk",
    "cadence": "usually weekly",
    "timing": "near expected replenishment window",
    "recentFeedback": "accepted recent suggestions",
    "activeOnList": false
  },
  "questions": {
    "surface_maybe": {
      "type": "noul",
      "instructions": "Given the household pattern summarized in state, is this product worth showing as a Maybe suggestion for the next grocery trip?",
      "criteria": {
        "true": "There is a useful recurring signal and showing it now is likely helpful",
        "false": "Evidence is weak or it is likely too early to suggest"
      }
    }
  }
}
```

The API is `POST https://api.typesafe.ai/v1/systemone` with a Bearer API key. For personal development, enter the key in an app setting and store it in Keychain; never hardcode it or put it in the widget snapshot. A distributed app would need a server proxy to keep the key secret. Implement timeout, 401/422 diagnostics, 429/529 backoff, no-call offline path and explicit opt-in before sending purchase-derived summaries. Do not send names if coarse category labels suffice for the experiment.

TypeSafe's own model notes say Jev struggles with numeric precision and date comparisons. Keep arithmetic and time logic in Swift; do not use a Score as a numeric quantity estimator. [Official limitations](https://docs.typesafe.ai/model-jaggedness/jev-1.13). If the Jev layer fails to improve the actual list, leave it disabled without blocking v1.
