# Grocery product decisions

Cloudflare Worker + D1 access control + Mercury Decide. The phone sends one product name/unit and up to eight local candidate names/units. It never sends purchase history, photos or notes. The Worker accepts only this task, not arbitrary model questions. It stores hashed device credentials, expiring hashed invitation codes, and quota counters; product names and decisions are not stored on the server. Worker observability is disabled.

## First deployment

1. Create Cloudflare and Inception accounts. Inception: create a provider API key.
2. In this directory run `npx wrangler@4.152.0 login`, then `npx wrangler@4.152.0 d1 create groceries-decisions`. Copy the returned database ID into `wrangler.jsonc` (it is not a secret).
3. Add GitHub repository variables `CLOUDFLARE_ACCOUNT_ID` and `DECISION_DATABASE_ID`.
4. Add GitHub repository secrets `CLOUDFLARE_API_TOKEN` (Workers Scripts Edit + D1 Edit for this account), `INCEPTION_API_KEY`, and `DECISION_ADMIN_KEY` (at least 32 random characters; retain it in a password manager). Never paste these into chat, commit them, or put them in the app.
5. Run the **Decision service** workflow on main. It applies the D1 migration, deploys the Worker, and writes provider/admin secrets. The deployment log shows the `workers.dev` origin. `/health` returns `ok` without touching Mercury.

No deployment runs until the two account/database variables exist. The workflow also runs the server tests on PRs. The iOS CI continues to compile the native integration.

For local development: `npx wrangler@4.152.0 d1 migrations apply groceries-decisions --local`; supply local-only keys in ignored `.dev.vars`, then `npm run dev`.

## Connect a family device

Run `python3 scripts/admin.py https://YOUR-WORKER.workers.dev`. Enter the admin key in the hidden terminal prompt. The script prints a 256-bit one-use pairing code, valid for 20 minutes. On the phone open **⋯ → זיהוי מוצרים**, enter the origin and pairing code, and connect. Pair each phone/iPad separately. Credentials are in Keychain and do not sync or appear in diagnostics. No provider/admin key is distributed to testers.

The app displays a device ID. Revoke it with `python3 scripts/admin.py https://YOUR-WORKER.workers.dev --revoke DEVICE_ID`. Disconnecting locally removes the token from that device; revocation is the server-side kill switch. Resetting learned links disconnects first and leaves purchases/names intact.

This family release uses invitation-based device credentials, **not App Attest**. Invitations must be issued out of band by the owner. Add App Attest and a household enrollment policy before broad public enrollment. Do not replace authentication with an embedded shared app secret.

## Evaluate, then enable learning

`AUTO_LINK_ENABLED` defaults to **false**: Mercury decisions are available for evaluation, while the phone shows “מחובר · בדיקת דיוק” and does not apply links. Create a separate test invitation, redeem it with `POST /v1/enroll`, and run `python3 scripts/evaluate.py https://YOUR-WORKER.workers.dev`; the enrolled token is entered at a hidden prompt. The included 12-case Hebrew corpus covers spelling, sizes, variants and generic-versus-specific ambiguity. No real household history is uploaded by this script.

Review false positives and expand the corpus with representative examples. A passing small corpus is a smoke test, not evidence of production accuracy or calibration. Do not treat the fixed 0.98 probability / 0.9 confidence gates as measured accuracy. Once evaluated, set repository variable `DECISION_AUTO_LINK_ENABLED=true` and rerun deployment. Evaluation-mode responses expire from the phone cache after one hour; reopening the app after that refreshes them.

Accepted links keep product/purchase IDs and display names unchanged. Prediction groups combine matching history, suppress an entire group when an alias is active/deferred, and emit at most one suggestion. Name/unit edits invalidate a link. Links live on Product records, so existing iCloud entity synchronization carries them; old versions can ignore them. Model inference, probability gates, and the versioned prompt are separate from deterministic date/quantity calculations.

## Bounds and failures

- Default caps: 40 model requests/device/day, 200 globally/day, 8 candidates/request, 120 characters/name, 8 KiB request body, 8-second provider deadline.
- D1 conditional increments enforce quotas across concurrent requests. Failed calls also consume a quota reservation. Expired counters and invitations are cleaned daily.
- Unauthorized/revoked devices never call Mercury. Upstream error bodies and credentials are not returned.
- Phone: at most 20 uncached calls per pass; no blocking shopping edits; one-hour retry after failures; cached results expire; changing credentials cancels outstanding work. HTTP redirects are rejected so the device credential is never forwarded to a different origin.
- The service is not yet deployed or live-evaluated until account credentials are configured. Provider charges are separate from Cloudflare quotas; set an Inception spending limit too.

Run `npm test` on Node 24. Tests use a real in-memory SQLite database behind a D1-compatible adapter and a mocked provider. Native tests verify non-destructive grouping, exclusions, rename/unit invalidation, and cycle handling.
