# QuotaNest

A Swift-native macOS menu bar monitor for AI resource usage and subscription quotas.

Current release scope: **Volcengine Ark**, including Agent Plan, Coding Plan, and enabled model resources. Requires macOS 14 or later.

- Lowest remaining plan window in the menu bar.
- Native popover with quota periods, provider reset times, enabled resources and refresh status.
- Refreshes every five minutes, on wake, or manually.
- Optional Launch at Login switch in Settings, managed by macOS.
- Access Key and Secret Key entered in Settings and stored as one record in macOS Keychain.
- Independent results and errors for each plan; failed refreshes retain the previous successful figures and timestamp.
- Changing credentials clears prior account snapshots and rejects its late responses.
- Read-only management requests. No inference traffic, purchases, or cloud resource changes.

## Build

```sh
swift test
./scripts/build-app.sh
open dist/QuotaNest.app
```

The app reads credentials from Keychain. It never automatically imports `.env`. The developer-only command below reads an explicit file and prints aggregate quota results without printing credentials:

```sh
.build/debug/QuotaNest --probe .env
```

The supplied `.env` is excluded from version control and release bundles. The supplied API-signing reference PDF stays local and is not intended for redistribution.

## Homebrew

The Cask installs the prebuilt app into `/Applications`. Requires macOS 14+; Xcode is only needed to build from source.

```sh
brew tap n0rvyn/quotanest https://github.com/n0rvyn/QuotaNest
brew install --cask n0rvyn/quotanest/quotanest
open -a QuotaNest
```

If you previously installed the source Formula, remove it with `brew uninstall --formula quotanest`, then install the Cask above. If macOS previously rejected an older Cask installation, use `brew uninstall --cask quotanest` followed by the Cask install command for a fresh installation. Ordinary uninstall preserves your Keychain credentials.

Settings opens on first launch. Opening the app again shows Settings. Saved credentials remain hidden until you choose **Show saved credentials**. Monitoring reads them automatically and retains them in memory between refreshes.

Published apps use Developer ID signing and Apple notarization. The local build defaults to ad-hoc signing; set `QUOTANEST_SIGN_IDENTITY` to your Developer ID Application identity for a signed build. Signed releases must be notarized and stapled before publication.

## Branches and releases

- `dev`: daily development.
- `main`: milestone releases merged from `dev`.
- Publish a versioned GitHub release only after build, tests, account checks and native UI verification.
- Homebrew Cask installs the checksum-verified universal app release into `/Applications`. Update it with `brew upgrade --cask quotanest`.

## Roadmap

- Alibaba Cloud Model Studio resource usage and Coding Plan.
- MiniMax usage and plan quota.
- Tencent Cloud usage and plan quota.

Each provider needs its own supported read-only APIs, credential handling, and real-account verification before being advertised as supported.
