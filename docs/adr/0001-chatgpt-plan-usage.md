# ADR 0001: ChatGPT plan usage feasibility

Date: 2026-10-30. Epic: [#38](https://github.com/Chaimalov/probably-groceries/issues/38).
Baseline: `2a364e5` on main. Status: **HOLD at Phase 0; no production integration approved.**

## Superseding clarification — 2026-10-31

The owner explicitly selects **Decisions API**, with a single consenting household sponsor and shared recommendation results. The SIWC exploration below is historical and does not establish access to this endpoint. Do not implement Responses as a substitute.

[Decisions documentation](https://developers.openai.com/api/docs/guides/decisions) identifies `gpt-6-luna` and bounded predicate/choice/score answers. Native code must construct candidates, validate results and own mutations. Update the contract accordingly; arbitrary prose/JSON generation is outside this decision boundary.

[SIWC inference documentation](https://developers.openai.com/siwc/token-sharing-open-source/models-and-inference) establishes Responses access only. Decisions authorization through that token remains unverified. [API subscription credits](https://developers.openai.com/api/docs/guides/chatgpt-api-credits) are a separate organization-key benefit for eligible Pro/Business subscriptions; Plus does not qualify. A funded API project behind the existing Worker is a candidate route, requiring an explicit billing choice and access verification. No spending or subscription upgrade is authorized.

Share recommendation records through CloudKit, never credentials. Device-hosted calculations depend on sponsor availability. Offline intelligence remains disabled. See the updated [epic](https://github.com/Chaimalov/probably-groceries/issues/38) for current requirements. **Phase 0 remains HOLD on the Decisions authorization/funding route; the old SIWC-only gates below apply only if that route becomes supported.** No live provider test has been performed.

## Original SIWC decision (2026-10-30)

The official service exists and supports user-authorized inference. However, this audit does not establish that our native iOS distribution and callback flow are supported, or that the required structured output works on an eligible account. Keep the existing implementation until those gates have evidence. This is uncertainty, not a claim that iOS is prohibited.

No app, backend, credentials, billing, repository visibility or TestFlight changes accompany this ADR. Public GitHub visibility was confirmed through repository metadata; no LICENSE file was found. Public visibility alone does not establish open-source licensing or provider eligibility. Do not add a license or temporarily publish code to obtain access without a separate owner decision.

## Official findings

Sources below were opened on the audit date. These findings describe documentation, not a live account test.

| Account tier | Identity sign-in | User-funded inference |
| --- | --- | --- |
| Free | No per-tier assurance established for our client | Not established; unavailable in our proposed UX until verified |
| Go | No per-tier assurance established for our client | Not established; unavailable in our proposed UX until verified |
| Plus | Documented for eligible integrations | Documented, subject to consent, workspace policy and quota |
| Pro | Documented for eligible integrations | Documented, subject to consent, workspace policy and quota |

The [quickstart](https://developers.openai.com/siwc/quickstart) distinguishes identity from permission to use a plan. It identifies Plus/Pro eligibility and limited partner availability. Login alone is insufficient. The [cookbook](https://developers.openai.com/cookbook/articles/sign-in-with-chatgpt) describes open-source/local personal use and directs paid or remotely hosted apps to an interest process. Our personal native app is a plausible local-project candidate, not confirmed admission. A shared Cloudflare inference service must not be assumed eligible under the local-client route.

The [registration guide](https://developers.openai.com/siwc/token-sharing-open-source/sign-in) documents dynamic registration, a persistent host identifier, fresh state/nonce/PKCE, and an HTTP callback at `127.0.0.1`. It does not establish our iOS browser/session and suspension behavior. An app URL scheme must not be substituted without documented support. New registration returns an issued client ID; verify the ID-token signature, issuer, audience, expiry and nonce before accepting identity. Require granted inference permission separately.

The [inference guide](https://developers.openai.com/siwc/token-sharing-open-source/models-and-inference) provides account-specific model discovery and public Responses inference with streaming and storage disabled. Only a completed terminal response is success. It does not establish access to Decisions API or a particular decision model; neither is selected. Strict structured output for the intended grocery schema remains unverified on this authorization route.

The [preview limits](https://developers.openai.com/siwc/token-sharing-open-source/preview-limitations) exclude background mode and several ordinary API fields, including output-token caps. Do not reuse a normal API request body unchanged. Input size and request frequency can be bounded locally; a hard server output-cost cap is not established.

The [session guide](https://developers.openai.com/siwc/token-sharing-open-source/profiles-and-sessions) describes isolated registrations, serialized rotating refresh and revocation. Plus shares a five-hour allowance across participating apps; Pro has no such five-hour limit. This is not unlimited usage or a fixed grocery budget. Exact per-request prices, credits conversion and this account's remaining quota are not established. Show provider usage controls rather than invented estimates. The [token reference](https://developers.openai.com/siwc/token-sharing-open-source/token-reference) documents one-hour access and renewable 30-day refresh tokens; honor returned expiry and renewal fields.

The [recovery guide](https://developers.openai.com/siwc/token-sharing-open-source/errors-and-recovery) distinguishes denied inference permission, ineligible accounts, usage limits, temporary outages and terminal refresh failures. Stop inference on denied permission, never silently change payer, and do not erase usable credentials for transient failures. Remote disconnection is discovered through requests/refresh rather than a guaranteed callback.

## Repository audit

| Surface | Current implementation and migration implication |
| --- | --- |
| `App/ShoppingStore.swift`, `App/PredictionEngine.swift` | Suggestions are derived locally through `predictionEvaluations`; current offline recommendations remain legacy behavior until an accepted migration. |
| `App/ProductDecisionService.swift` | Optional name/unit identity matching, enrollment, device-only Keychain credentials, network monitoring, debounce, retries and cache. Not ChatGPT authentication or replenishment inference. |
| `App/ProductDecisionSettings.swift`, `App/SettingsView.swift` | Existing server URL/pairing code UI explains name/unit sharing only. It does not consent to purchase-history transfer. |
| `server/` | Cloudflare/D1 Mercury matching with invitation credentials and quotas. README says live deployment/evaluation require configuration; actual deployed state was not checked. |
| `docs/JEV.md` | Earlier spike specification; no Jev-named runtime adapter found. Do not present it as a shipped ChatGPT connection. |
| `App/PersonalCloudSync.swift`, shared-list code | Existing shared identities and history must survive migration. AI consent is separate from CloudKit participation. |
| `Shared/GroceryWidgetSnapshot.swift`, `Widgets/`, `App/PhoneWatchBridge.swift`, `Watch/` | Existing snapshot and shopping paths must remain independent of inference and OAuth credentials. |

No dedicated privacy manifest/disclosure file was found by filename search. That is not a completed App Store privacy audit; inspect account-side declarations before release.

## Proposed architecture after the gate

Prefer direct native requests if that deployment is confirmed eligible. Keep OAuth credentials in device-only Keychain, outside CloudKit, Watch, widgets, diagnostics and logs. Use a vendor-independent typed provider boundary, but do not implement a speculative OAuth adapter now. Reuse the Worker only if provider approval requires/permits a backend; existing Mercury device authentication does not authorize OpenAI plan usage.

Each adult separately consents before their shared history is sent. CloudKit ownership does not authorize AI processing. Requests use the account explicitly selected on the initiating device; never copy a spouse's tokens or automatically incur their usage after a shared edit. Initially allow foreground, explicit refresh only. Background billing remains disabled pending provider and household authorization.

Send bounded product/purchase summaries with request-scoped identifiers. Exclude notes, photos, email, location and CloudKit account IDs. Define exact bounds and consent text in Phase 1. Treat all product text as untrusted data. `store:false` is not a promise of zero provider retention; retention/data-use terms and deletion wording still need review before purchase data leaves the device.

In the future ChatGPT mode, offline, disconnected and ineligible states hide recommendations and generate none. Hide cached results offline as the initial product choice. Keep arithmetic, suppression, ID validation, positive quantities, deduplication and all list mutations native; AI results are proposals requiring user acceptance. Feature-off retains legacy behavior until the migration acceptance gate; never fall back silently within ChatGPT mode.

## Evidence required to open Phase 1

1. Confirm applicable local-project eligibility/licensing or obtain private-client admission. Record any approval without committing private correspondence or credentials.
2. Establish an officially supported native callback/session approach. Validate sign-in, cancellation, app suspension, returning sign-in and callback tampering on a real iPhone. Do not assume simulator success proves device support.
3. On a consenting eligible account, verify model discovery, one synthetic minimal inference, strict grocery-schema output and terminal stream handling. Record sanitized results and capability failures. Do not upload household history for this probe.
4. Complete retention/terms review, both participants' consent design, payer semantics and quota controls. Verify Free/Go behavior separately or explicitly exclude them from AI eligibility.
5. Update this ADR with a GO decision and remaining release prerequisites. Only then implement the provider contract, settings and migration phases in #38.

If native admission cannot be established, alternatives are an approved private-client integration or an explicitly chosen developer-funded API through the existing Worker architecture. Both require separate access/billing decisions; neither is an automatic fallback or authorized expenditure.

## Validation

Read-only source audit and official documentation review completed. No live OAuth, inference, entitlement, device or retention verification was performed. This documentation-only change needs no iOS build or TestFlight run. Phase 0 remains open because its required evidence is incomplete.
