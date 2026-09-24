# v1 issue DAG

Each node is a GitHub issue. `Depends on` uses issue numbers once created; this file mirrors their order and intent. Independent branches can move in parallel, but personal-use speed matters more than a ceremony-heavy process.

```mermaid
flowchart TD
  A[App shell and local store] --> B[Shopping loop]
  A --> C[Prediction baseline]
  B --> C
  B --> D[Widget data bridge]
  D --> E[Interactive widgets]
  C --> F[Jev spike]
  C --> G[Suggestion UX]
  B --> H[Cloud sharing spike]
  G --> I[Device dogfood]
  E --> I
  F --> I
  H --> I
```

The sharing spike can be deferred if it slows the first personal device build. The Jev spike is an optional enhancement with a working local fallback. “Done” means the acceptance checks in the issue work on device, not that every edge case is polished.
