# DiagramDown release process

DiagramDown's current public releases support Apple Silicon only. Both the application and bundled D2 0.7.1 helper are arm64, and release validation rejects mixed or unexpected architectures.

The default distribution is a reproducible community release that does not require an Apple Developer account. It is ad-hoc signed and is not notarized by Apple. Every download page must state this limitation prominently.

## Public Apple Silicon community release

Prerequisites:

- an Apple Silicon Mac
- Xcode with the macOS 15 SDK or later
- Node.js 18 or later
- a clean Git worktree

Create the public release package:

```sh
./Scripts/package-release.sh
```

The script:

1. runs the complete automated test suite
2. creates an arm64 Release build with local ad-hoc signatures
3. validates the application and D2 architectures, signatures, Hardened Runtime,
   sandbox entitlements, native-preview runtime assets, Tree-sitter grammar
   resources, absence of the legacy Web preview, and bundled licenses
4. creates `DiagramDown-<version>-arm64.dmg` with `DiagramDown.app` and an Applications shortcut
5. writes a matching `.sha256` checksum

Artifacts are written under `artifacts/`. `--skip-tests` is allowed only when the exact commit already passed `./Scripts/test.sh`; `--allow-dirty` is for deliberate local diagnostics and must not be used for a published build.

The deprecated `package-private-beta.sh` command remains as a compatibility wrapper.

## Verify a download

Download the DMG and checksum file into the same directory, then run:

```sh
shasum -a 256 -c DiagramDown-<version>-arm64.dmg.sha256
```

The result must report `OK`. A checksum proves that the file matches the release asset; it does not provide Apple notarization or identity verification.

## First launch and Gatekeeper

The community build is ad-hoc signed and not notarized. macOS Gatekeeper may block the first launch after downloading it from the internet.

After verifying the checksum and repository source:

1. open the DMG
2. drag `DiagramDown.app` to the Applications shortcut
3. Control-click or right-click the application and choose **Open**
4. if macOS still blocks it, use **Open Anyway** in System Settings > Privacy & Security

Never disable Gatekeeper globally. Users who require an Apple-notarized application should build from source or wait for a future notarized distribution.

## Tag-driven GitHub Release

Pushing a semantic-version tag starts `.github/workflows/release.yml`. The workflow requires the tagged commit to be reachable from `main`, requires matching release notes under `docs/releases/`, reruns all tests, builds and validates the package, and creates a GitHub Release with the DMG and checksum.

Follow [release-checklist.md](release-checklist.md) before pushing a tag. A tag is the publication action; do not push a release tag until its preparation pull request is merged and `main` is green.

## Validate an existing application

```sh
./Scripts/validate-release.sh /path/to/DiagramDown.app --adhoc
```

Validation covers:

- bundle identifier and version metadata
- arm64 architecture of the application and bundled D2 helper
- strict nested-code signature validation
- Hardened Runtime on both executables
- application sandbox and inherited helper sandbox entitlements
- exact ad-hoc signature status
- bundled project and third-party license texts
- isolated Mermaid renderer and Tree-sitter query bundles
- absence of markdown-it, highlight.js, and visible preview Web assets

## Optional future notarized distribution

The existing `Scripts/release.sh` and `Config/ExportOptions-DeveloperID.plist` remain available for a future Developer ID, notarization, and staple workflow. This path is not required for the `0.17.x` community release and does not change the current public packaging process.

## Manual application checks

The release pipeline intentionally performs command-line and automated validation only. It does not control the macOS interface. The combined document at `docs/examples/all-features.md` can be used for later manual checks of editing, preview rendering, layout modes, scroll synchronization, diagram zoom, and export.
