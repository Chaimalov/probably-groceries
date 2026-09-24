# v1 issue DAG

Each node is a GitHub issue. The `Depends on` lines in the issue bodies are the directed edges. Independent branches can move in parallel, but personal-use speed matters more than a ceremony-heavy process.

```mermaid
flowchart TD
  A["#1 App shell and store"] --> B["#2 Shopping loop"]
  B --> C["#3 Local predictor"]
  C --> D["#4 Suggestion UI"]
  B --> E["#5 Widget bridge"]
  E --> F["#6 Widgets"]
  D --> F
  C --> G["#7 Jev spike"]
  B --> H["#8 Cloud sharing"]
  D --> I["#9 First real trip"]
  F --> I
  G --> J["#10 Two-device v1"]
  H --> J
  I --> J
```

| Issue | Depends on | Result |
| --- | --- | --- |
| [#1](https://github.com/Chaimalov/probably-groceries/issues/1) | — | App shell, local domain store |
| [#2](https://github.com/Chaimalov/probably-groceries/issues/2) | #1 | Shopping and purchase loop |
| [#3](https://github.com/Chaimalov/probably-groceries/issues/3) | #1, #2 | Offline prediction |
| [#4](https://github.com/Chaimalov/probably-groceries/issues/4) | #2, #3 | Suggestion UI and feedback |
| [#5](https://github.com/Chaimalov/probably-groceries/issues/5) | #1, #2 | Widget data bridge |
| [#6](https://github.com/Chaimalov/probably-groceries/issues/6) | #4, #5 | Interactive widgets |
| [#7](https://github.com/Chaimalov/probably-groceries/issues/7) | #3 | Jev spike with fallback |
| [#8](https://github.com/Chaimalov/probably-groceries/issues/8) | #1, #2 | Household CloudKit sharing |
| [#9](https://github.com/Chaimalov/probably-groceries/issues/9) | #4, #6 | First genuine shopping trip |
| [#10](https://github.com/Chaimalov/probably-groceries/issues/10) | #7, #8, #9 | Two-device personal v1 |

The sharing spike can be deferred if it slows the first personal device build. The Jev spike has a working local fallback. “Done” means the acceptance checks in the issue work on device, not that every edge case is polished.
