# Contributing to DiagramDown

Thanks for improving DiagramDown. Keep changes focused, reviewable, and compatible with the application's offline-first trust boundary.

## Development requirements

- macOS 15 or later
- Apple Silicon when exercising the bundled D2 renderer
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
  build
```

Manually verify visible behavior when changing editor layout, scrolling, themes, diagram rendering, zoom, or export.

## Change guidelines

- Preserve native `NSTextView` editing behavior and the persistent `WKWebView` preview architecture.
- Keep Markdown, Mermaid, and D2 rendering offline. Do not add CDN or runtime network dependencies.
- Run D2 only through the fixed bundled executable path; never construct shell commands from document content.
- Preserve source-line anchors and stable diagram identities when changing preview rendering.
- Update tests and `CHANGELOG.md` for user-visible behavior.
- Do not commit build products, credentials, private Markdown documents, absolute local paths, or Xcode user state.

## Bundled dependencies

Changes to Mermaid, markdown-it, or D2 must update the bundled artifact, version documentation, provenance or checksum, and corresponding license notice together. D2 remains an arm64 helper until the universal distribution work is complete.

## Pull requests

Use a short descriptive branch name and explain the rationale, main changes, and validation performed. Keep unrelated refactors out of feature and bug-fix pull requests.
