# DiagramDown release process

The first DiagramDown beta supports Apple Silicon only. Both the application and bundled D2 0.7.1 helper are built as arm64, and release validation intentionally rejects mixed or unexpected architectures.

The repository currently provides two separate packaging paths:

- a temporary, ad-hoc signed private-beta build that does not require a paid Apple Developer account
- the official Developer ID and notarization flow to use after joining the Apple Developer Program

Neither script publishes a GitHub release or changes repository visibility.

## Private beta without a paid developer account

Prerequisites:

- an Apple Silicon Mac
- Xcode with the macOS 15 SDK or later
- Node.js 18 or later for the preview-runtime tests
- a clean Git worktree

Create the private test package:

```sh
./Scripts/package-private-beta.sh
```

The script runs all tests, creates an arm64 Release build with local ad-hoc signatures, validates its architectures, signatures, Hardened Runtime, sandbox entitlements, and bundled project and third-party license texts, then writes these files under `artifacts/`:

- `DiagramDown.app`
- `DiagramDown-<version>-<build>-arm64-private-beta.zip`
- a matching `.sha256` checksum file

Verify the ZIP after copying both files to another directory:

```sh
shasum -a 256 -c DiagramDown-0.16.0-16-arm64-private-beta.zip.sha256
```

The exact filename changes with the application version and build number.

### Private-beta limitations

The package is ad-hoc signed and not notarized. It is suitable only for deliberate testing by people who trust the sender; it is not an official public release. macOS Gatekeeper may block the first launch on another Mac. A tester can use Finder's **Open** command or the **Open Anyway** control in System Settings > Privacy & Security after confirming the checksum and source. Do not disable Gatekeeper globally.

Use `--skip-tests` only when the exact commit has already passed `./Scripts/test.sh`. Use `--allow-dirty` only for deliberate local diagnostics. `BUILD_NUMBER=17 ./Scripts/package-private-beta.sh` overrides the project build number without editing the project.

## Official Developer ID release (deferred)

This path requires:

- Apple Developer Program membership for team `QM6DZQY23F`
- a valid `Developer ID Application` certificate in the login keychain
- notarization credentials stored in the macOS Keychain

Confirm that the signing identity is available:

```sh
security find-identity -v -p codesigning
```

Store notarization credentials once. Do not put an Apple ID password, app-specific password, API private key, or profile contents in this repository.

```sh
xcrun notarytool store-credentials DiagramDown-notary \
  --apple-id "APPLE_ID" \
  --team-id QM6DZQY23F
```

`notarytool` securely prompts for the app-specific password when it is omitted. App Store Connect API key credentials can be stored instead; see `xcrun notarytool help store-credentials`.

Build and inspect a Developer ID package without notarizing:

```sh
./Scripts/release.sh
```

Build, submit for notarization, staple the ticket, and run Gatekeeper validation:

```sh
./Scripts/release.sh --notary-profile DiagramDown-notary
```

The script creates a ZIP but does not upload it. Do not publish an unstapled or unnotarized artifact as the official release.

## Validate an existing application

```sh
./Scripts/validate-release.sh /path/to/DiagramDown.app --adhoc
./Scripts/validate-release.sh /path/to/DiagramDown.app --distribution
./Scripts/validate-release.sh /path/to/DiagramDown.app --notarized
```

Validation covers:

- bundle identifier and version metadata
- arm64 architecture of both the application and bundled D2 helper
- strict nested-code signature validation
- Hardened Runtime on both executables
- application sandbox and inherited helper sandbox entitlements
- exact ad-hoc signature status when requested
- absence of the `get-task-allow` debugging entitlement in distribution builds
- bundled project and third-party license texts
- Developer ID identity and team when requested
- stapled notarization ticket and Gatekeeper acceptance when requested

Before an official public release, install the final notarized ZIP on a separate Apple Silicon Mac and verify document opening, Markdown preview, Mermaid rendering, D2 rendering, PDF export, and SVG export under normal Gatekeeper launch behavior.
