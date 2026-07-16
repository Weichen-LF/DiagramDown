# DiagramDown release process

DiagramDown currently ships as an Apple Silicon application because its bundled D2 0.7.1 helper is arm64-only. The release scripts intentionally reject mixed or unexpected architectures.

## Prerequisites

- Xcode with the macOS 15 SDK or later
- An Apple Developer team membership for team `QM6DZQY23F`
- A valid `Developer ID Application` certificate in the login keychain
- A clean Git worktree
- Node.js 18 or later for the preview-runtime tests

Confirm that the signing identity is available:

```sh
security find-identity -v -p codesigning
```

## Store notarization credentials

Store credentials in the macOS Keychain once. Do not put an Apple ID password, app-specific password, API private key, or profile contents in this repository.

```sh
xcrun notarytool store-credentials DiagramDown-notary \
  --apple-id "APPLE_ID" \
  --team-id QM6DZQY23F
```

`notarytool` securely prompts for the app-specific password when it is omitted. App Store Connect API key credentials can be stored instead; see `xcrun notarytool help store-credentials`.

## Build a signed archive without notarizing

```sh
./Scripts/release.sh
```

This runs all tests, archives an arm64 Release build, exports it with Developer ID, verifies the main application and D2 helper, and creates a ZIP under `artifacts/`. The resulting ZIP is useful for release inspection but should not be published until notarized.

To set a monotonically increasing bundle build number without editing the project:

```sh
BUILD_NUMBER=17 ./Scripts/release.sh
```

## Build and notarize

```sh
./Scripts/release.sh --notary-profile DiagramDown-notary
```

After Apple accepts the submission, the script staples the ticket to `DiagramDown.app`, validates the ticket, runs a Gatekeeper assessment, and recreates the ZIP so the final archive contains the stapled application. It does not upload the ZIP to a website or create a GitHub release.

Use `--skip-tests` only when the exact commit has already passed `./Scripts/test.sh`. Use `--allow-dirty` only for deliberate local diagnostics; public artifacts should always come from a clean, tagged commit.

## Validate an existing application

```sh
./Scripts/validate-release.sh /path/to/DiagramDown.app --distribution
./Scripts/validate-release.sh /path/to/DiagramDown.app --notarized
```

Validation covers:

- bundle identifier and version metadata
- arm64 architecture of both the application and bundled D2 helper
- strict nested-code signature validation
- Hardened Runtime on both executables
- application sandbox and inherited helper sandbox entitlements
- absence of the `get-task-allow` debugging entitlement in distribution builds
- bundled third-party license texts
- Developer ID identity and team when requested
- stapled notarization ticket and Gatekeeper acceptance when requested

Before publishing, install the final ZIP on a separate Apple Silicon Mac and verify document opening, Markdown preview, Mermaid rendering, D2 rendering, PDF export, and SVG export under normal Gatekeeper launch behavior.
