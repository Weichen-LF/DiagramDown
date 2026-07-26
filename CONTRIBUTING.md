# Contributing to DiagramDown

Thanks for improving DiagramDown. Keep changes focused, reviewable, and compatible with the application's offline-first trust boundary.

## Development requirements

- macOS 15 or later
- Apple Silicon for the current release target
- Xcode with the macOS SDK and SwiftUI support
- Node.js 18 or later

Open `Mark.xcodeproj` and use the `Mark` scheme for local development.

## Before opening a pull request

Run the complete automated suite:

```sh
./Scripts/test.sh
```

For release-related changes, also build the arm64 Release configuration:

```sh
xcodebuild \
  -project Mark.xcodeproj \
  -scheme Mark \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath /tmp/DiagramDownReleaseDerivedData \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  build
```

Changes to the public packaging path should additionally run:

```sh
./Scripts/package-release.sh --allow-dirty
```

The packaged application is ad-hoc signed and not notarized. Any release-facing documentation must preserve the Gatekeeper warning and checksum instructions.

Manually verify visible behavior when changing editor layout, scrolling, themes, diagram rendering, zoom, or export.

## Change guidelines

- Preserve native `NSTextView` editing and SwiftUI preview behavior.
- Keep Markdown, Mermaid, and D2 rendering local. Do not add CDN or runtime network dependencies.
- Run local diagram tools with absolute executable paths and argument arrays; never construct shell commands from document content.
- Preserve source-line anchors and stable diagram identities when changing preview rendering.
- Update tests and `CHANGELOG.md` for user-visible behavior.
- Do not commit build products, credentials, private Markdown documents, absolute local paths, or Xcode user state.

## Diagram tool compatibility

Mermaid and D2 are optional user-installed tools. Changes to CLI arguments,
discovery, or version handling must include fake-executable tests and manual
coverage against current Homebrew versions. Do not add either executable or its
runtime assets to the application bundle.

## Pull requests

The `main` branch is protected. Submit changes through a pull request, keep the branch current with `main`, and wait for the required test and CodeQL checks to pass. The repository uses squash merges and automatically removes merged branches.

Use a short descriptive branch name and explain the rationale, main changes, and validation performed. Keep unrelated refactors out of feature and bug-fix pull requests.
