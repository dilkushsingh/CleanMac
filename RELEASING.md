# Releasing CleanMac

CleanMac ships as a standalone `.app` bundle. This document covers the three
signing paths and the packaging script.

## Local build vs. distributed build

### 1. Local build with your Personal Team

For your own machine. Set the signing Team in Xcode (target → **Signing &
Capabilities** → **Team: your Personal Team**), then ⌘R. The binary is signed
with your Apple ID's development certificate — Gatekeeper permits it on **your
Mac** because your Mac trusts your own development certificates.

- Accessibility and Input Monitoring grants persist across rebuilds **as long
  as the signing identity doesn't change**. If you switch Teams or
  rebuild without signing, macOS treats it as a different app and loses the
  grant (see README → Troubleshooting).
- The build is **not** suitable for distribution. On another Mac, Gatekeeper
  will refuse to launch it.

### 2. Unsigned or ad-hoc signed distribution

This is what `scripts/package-release.sh` produces. The `.app` is signed with
the special identity `-` (ad-hoc), which has no backing certificate.

- The `.app` bundle will run on your own Mac.
- On any **other** Mac, Gatekeeper will show:
  _"CleanMac" can't be opened because Apple cannot check it for malicious
  software._
- Users can work around this (right-click → Open, or System Settings →
  Privacy & Security → "Open Anyway"), but it is a **genuine warning**, not a
  cosmetic one. Users have no cryptographic proof of who built the binary or
  that it hasn't been tampered with in transit.
- This path is appropriate for: friends/beta testers who understand the
  warning, open-source users who can build from source themselves, and
  internal testing.
- This path is **not** appropriate for: a wide-audience public release where
  non-technical users will try to run the app and be confused by the warning.

### 3. Developer ID signing + Apple notarization

This is the only path that ships a `.app` which opens without a Gatekeeper
warning on an arbitrary Mac.

Requirements:

- A paid **Apple Developer Program** membership ($99 / year).
- A **Developer ID Application** certificate installed in your login keychain.
- An App Store Connect API key (or Apple ID + app-specific password) for
  notarization submission.

High-level steps (not scripted here on purpose — these touch credentials and
should not be committed):

1. Archive with `CODE_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"`.
2. `xcodebuild -exportArchive` with an export options plist of method
   `developer-id`.
3. `xcrun notarytool submit CleanMac.zip --wait` with your API key.
4. `xcrun stapler staple CleanMac.app` to attach the notarization ticket so
   Gatekeeper can validate offline.

Apple's reference: <https://developer.apple.com/documentation/security/notarizing_macos_software_before_distribution>

When you're ready to adopt this, add a separate script (e.g.
`scripts/package-release-notarized.sh`) that reads credentials from
environment variables or `xcrun notarytool store-credentials`. Do **not**
commit certificates, provisioning profiles, API keys, or `.p12` files.

## Packaging an ad-hoc release

From a clean working tree:

```sh
./scripts/package-release.sh
```

The script:

1. Regenerates `CleanMac.xcodeproj` with XcodeGen.
2. Cleans `build/`.
3. Archives `CleanMac` in Release configuration with `CODE_SIGN_IDENTITY=-`.
4. Copies the `.app` out of the archive.
5. Zips it to `dist/CleanMac-<MARKETING_VERSION>.zip`.

Version comes from `MARKETING_VERSION` in `project.yml` — bump it there before
running the script.

## Publishing a GitHub Release

Manual, by design — nothing in this repo auto-publishes or auto-tags.

1. Bump `MARKETING_VERSION` (and `CURRENT_PROJECT_VERSION` if it's a new
   build) in `project.yml`.
2. Commit the bump.
3. Tag: `git tag v0.1.0-beta && git push --tags`
4. Run `./scripts/package-release.sh`.
5. On GitHub → Releases → **Draft a new release** → pick the tag → attach
   `dist/CleanMac-<version>.zip` → write release notes → publish.

Include in the release notes:

- What changed.
- The known Gatekeeper warning and how users can bypass it (for ad-hoc
  releases).
- The macOS version requirement (currently **macOS 15+**).

## Gatekeeper limitations — be honest with users

Do not tell users an unsigned `.app` will "just open". It won't on a default
macOS install. The warning dialog is a feature, not a bug — it tells the user
that no trusted party has vouched for the binary's authenticity. Users have
two legitimate responses: trust you and bypass the warning manually, or wait
for a notarized release.
