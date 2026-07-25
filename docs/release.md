# DiagramDown release process

DiagramDown's current public releases support Apple Silicon only. Mermaid and
D2 are optional user-installed command-line tools and are not part of the
application bundle.

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
3. validates the application architecture, signature, Hardened Runtime,
   native-preview runtime assets, Tree-sitter grammar resources, absence of
   WebKit/bundled diagram runtimes, and bundled licenses
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
- arm64 architecture of the application
- strict nested-code signature validation and Hardened Runtime
- absence of App Sandbox and obsolete WebKit network entitlements
- exact ad-hoc signature status
- bundled project and third-party license texts
- bundled Prettier and Tree-sitter query resources
- absence of WebKit linkage, Mermaid browser assets, D2 helpers, SVGView,
  markdown-it, and highlight.js

## Optional future notarized distribution

`Scripts/release.sh` and `Config/ExportOptions-DeveloperID.plist` provide the
Developer ID, notarization, and staple workflow for direct distribution. The
application intentionally does not target the Mac App Store because executing
user-installed diagram tools requires App Sandbox to remain disabled.

## Manual application checks

The release pipeline intentionally performs command-line and automated
validation only. Before publishing, manually test `docs/examples/all-features.md`
once with neither CLI installed and once with current Homebrew `mermaid-cli` and
`d2` installations.
