# First TestFlight install

This app targets iOS 27. The `Upload to TestFlight` workflow uses GitHub's Xcode 27 runner and Apple's cloud-managed signing. The existing `iOS build` workflow only produces an unsigned simulator build.

## One-time Apple setup

1. Sign in to [App Store Connect](https://appstoreconnect.apple.com/) with the enrolled Apple Account. If Apple asks for an agreement, the account holder must review it.
2. In [Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/identifiers/list), register the explicit App ID `com.chaimalov.probablygroceries` for iOS if it is not already present. No iCloud capability is used by the current local-only build.
3. In App Store Connect, add an iOS app named `קניות` with the same bundle ID, Hebrew as primary language, and any unique SKU. Creating this app record is required before uploading its first build.
4. In App Store Connect → Users and Access → Integrations → App Store Connect API, the Account Holder requests API access if needed. An Account Holder or Admin then creates a **team API key** with the App Manager or Admin role. Download its `.p8` file once and record its Key ID and Issuer ID. If your role is Developer, an admin may also need to enable access to cloud-managed distribution certificates.
5. In the GitHub repository → Settings → Secrets and variables → Actions, add repository **variable** `APPLE_TEAM_ID` (the Apple Developer Team ID) and repository **secrets** `APPLE_API_KEY_ID`, `APPLE_API_ISSUER_ID`, `APPLE_API_KEY_P8` (the *contents* of the downloaded `.p8`). Never commit these values or paste the private key into a chat.

## Upload and install

1. In GitHub Actions, choose **Upload to TestFlight** → **Run workflow** on `main`.
2. After the upload completes and Apple processes the build, open the app in App Store Connect → TestFlight. Add your Apple Account to an **internal testing** group and assign the build. Complete any Apple prompts for beta information or compliance that appear.
3. Accept the invitation with the same Apple Account used in TestFlight on the iPhone, then tap **Install**. Test the shopping flow on your device and report any issue or screenshot here.

Each manual workflow run uses its GitHub run number as a distinct build number. The workflow keeps the API key only in a temporary runner file and removes it after the build. The first build stores shopping data locally on that iPhone; iCloud sync and sharing are separate upcoming tasks.
