# DiagramDown

[![CI](https://github.com/Weichen-LF/DiagramDown/actions/workflows/ci.yml/badge.svg)](https://github.com/Weichen-LF/DiagramDown/actions/workflows/ci.yml)
[![CodeQL](https://github.com/Weichen-LF/DiagramDown/actions/workflows/codeql.yml/badge.svg)](https://github.com/Weichen-LF/DiagramDown/actions/workflows/codeql.yml)

![DiagramDown app icon](Mark/Assets.xcassets/AppIcon.appiconset/icon_128x128@2x.png)

DiagramDown is a native macOS Markdown editor designed for documents that mix prose and diagrams. The long-term goal is an offline editor with live Markdown preview plus first-class Mermaid and D2 fenced code blocks.

The name combines the product's two core ideas: diagrams and Markdown. It is a working product name and can still change before the first public release.

## Current status

Version `0.16.0` adds a repeatable release foundation for the Apple Silicon build:

- Create, open, edit, and save `.md` and `.markdown` files
- Native `NSTextView` editing with macOS input methods
- Native line-number gutter with logical-line numbering and current-line emphasis
- Undo and redo, selection, scrolling, and find bar support
- UTF-8 document storage and automatic document saving
- App Sandbox access to user-selected files
- Live split-view Markdown preview backed by a persistent `WKWebView`
- Bundled offline `markdown-it` rendering with light and dark appearance support
- Bundled offline Mermaid rendering for fenced `mermaid` code blocks
- Inline Mermaid errors with expandable source and light/dark diagram themes
- Bundled D2 0.7.1 rendering for fenced `d2` code blocks
- Sandboxed D2 execution with cancellation, timeouts, size limits, and inline errors
- 32 MB in-memory LRU cache for repeated D2 renders
- 256 MB on-disk LRU cache that survives relaunches and regenerates damaged entries
- Stable Mermaid and D2 block identities across preview revisions
- Flicker-free D2 updates that reuse unchanged SVGs and retain the previous diagram while edited source renders
- Source-line anchors for rendered Markdown and diagram blocks
- Smooth bidirectional editor-preview scrolling with source anchors and proportional fallback
- Click-to-source navigation from preview blocks back to the native editor with animated positioning
- App-wide D2 layout, theme, padding, and sketch settings
- Follow System, Light, and Dark appearance modes for the whole application
- DiagramDown, GitHub, and Paper Markdown preview themes
- Independent light and dark Mermaid theme selection
- Persistent 50–200% preview zoom with toolbar, menu, keyboard, and Settings controls
- Per-diagram SVG export for successfully rendered Mermaid and D2 blocks
- Full-document Markdown preview export to paginated PDF
- Per-window Editor Only, Editor and Preview, and Preview Only layouts
- Focused Mermaid and D2 diagram viewer with fit, 25%–400% zoom, and keyboard controls
- Two-finger trackpad pinch zoom for the Markdown preview and focused diagram viewer
- Native unit tests for zoom, layouts, document encoding, D2 configuration, and scroll state
- Structural preview-runtime tests for offline assets, CSP, WebKit bridges, diagram controls, and gestures
- Automated arm64 archive, Developer ID export, ZIP packaging, notarization, and ticket stapling
- Release validation for nested signatures, Hardened Runtime, sandbox entitlements, architectures, licenses, and Gatekeeper
- MIT license bundled with packaged builds

The first beta supports Apple Silicon Macs only. Intel support and a universal D2 helper are deferred until after the initial beta.

## Requirements

- macOS 15.0 or later
- Apple Silicon for D2 rendering
- Xcode with the macOS SDK and SwiftUI support
- Node.js 18 or later for preview-runtime tests

## Build

Open `Mark.xcodeproj` in Xcode and run the `Mark` scheme, or build from the command line:

```sh
xcodebuild \
  -project Mark.xcodeproj \
  -scheme Mark \
  -configuration Debug \
  -derivedDataPath /tmp/DiagramDownDerivedData \
  CODE_SIGNING_ALLOWED=NO \
  build
```

## Test

Run the complete Swift and preview-runtime test suite:

```sh
./Scripts/test.sh
```

The Swift tests can also be run from Xcode with the `Mark` scheme.

## Private beta and release

Without a paid Apple Developer account, create an Apple Silicon private-test package with local ad-hoc signatures:

```sh
./Scripts/package-private-beta.sh
```

The result is not notarized and must not be published as an official release. The separate Developer ID workflow remains available for use after developer-program enrollment:

```sh
./Scripts/release.sh
```

Add `--notary-profile PROFILE_NAME` to submit with credentials already stored in the macOS Keychain. See `docs/release.md` for private-beta limitations, checksum verification, certificate setup, notarization, and final smoke-test guidance.

DiagramDown is open source under the [MIT License](LICENSE). Prebuilt, notarized binaries have not been released yet; the current packaging path is intended only for trusted private beta testing.

## Contributing and security

See [CONTRIBUTING.md](CONTRIBUTING.md) for development and pull-request guidance. Report security-sensitive problems privately by following [SECURITY.md](SECURITY.md); do not include vulnerabilities, credentials, or private documents in regular issues.

## Project layout

- `Mark/MarkdownDocument.swift`: Markdown file lifecycle
- `Mark/MarkdownEditorView.swift`: native AppKit editor embedded in SwiftUI
- `Mark/LineNumberTextView.swift`: native editor text drawing with visible logical-line numbering
- `Mark/ContentView.swift`: document window content
- `Mark/MarkdownPreviewView.swift`: persistent WebKit preview and update coordination
- `Mark/ScrollSyncState.swift`: editor-preview scroll position and source target state
- `Mark/D2RenderService.swift`: bounded D2 process execution, temporary-file lifecycle, and two-level cache
- `Mark/PreviewSettingsView.swift`: persistent appearance and preview preferences
- `Mark/PreviewCommands.swift`: preview zoom and PDF export commands
- `Mark/DiagramDown.entitlements`: explicit sandbox permissions used by signed builds
- `Mark/Resources/Preview`: bundled offline preview runtime
- `MarkTests`: native unit tests for core document and preview behavior
- `Tests/PreviewRuntimeTests.mjs`: offline preview structure and bridge regression tests
- `Scripts/test.sh`: complete local test entry point
- `Scripts/package-private-beta.sh`: ad-hoc signed Apple Silicon test packaging and checksum generation
- `Scripts/release.sh`: Developer ID archive, export, packaging, and optional notarization
- `Scripts/validate-release.sh`: architecture, signature, entitlement, license, and Gatekeeper checks
- `Config/ExportOptions-DeveloperID.plist`: reproducible Developer ID export configuration
- `Helpers/d2`: sandbox-inheriting D2 arm64 helper
- `docs/examples/mermaid.md`: Mermaid rendering smoke-test document
- `docs/examples/d2.md`: D2 rendering smoke-test document
- `docs/swiftui-markdown-mermaid-d2-design.md`: architecture and phased implementation plan
- `docs/product-identity.md`: working name, icon, and visual identity notes
- `docs/release.md`: signing, notarization, and release runbook

## Roadmap

1. Native Markdown editor — complete for the MVP
2. Local WebKit Markdown preview — complete for the MVP
3. Mermaid fenced-block rendering — complete for the MVP
4. Sandboxed D2 CLI rendering — complete for the MVP
5. D2 memory cache and stable diagram identity — complete
6. Editor-preview scroll synchronization — complete for the MVP
7. D2 preview settings — complete
8. Application appearance and preview themes — complete
9. Disk cache — complete
10. Persistent preview zoom — complete
11. Mermaid and D2 diagram SVG export — complete
12. Full Markdown preview PDF export — complete
13. Document view modes and focused diagram zoom — complete
14. Trackpad pinch zoom across preview surfaces — complete
15. Stability and automated testing — complete for the first suite
16. Signing, notarization, and release preparation — complete for the arm64 Developer ID workflow
17. Apple Silicon private-beta packaging and MIT licensing — complete
18. Developer ID notarization and first public release — deferred until developer-program enrollment
19. Universal D2 helper and Intel support — later; not required for the first beta
