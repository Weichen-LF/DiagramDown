# DiagramDown

[![CI](https://github.com/Weichen-LF/DiagramDown/actions/workflows/ci.yml/badge.svg)](https://github.com/Weichen-LF/DiagramDown/actions/workflows/ci.yml)
[![CodeQL](https://github.com/Weichen-LF/DiagramDown/actions/workflows/codeql.yml/badge.svg)](https://github.com/Weichen-LF/DiagramDown/actions/workflows/codeql.yml)

![DiagramDown app icon](Mark/Assets.xcassets/AppIcon.appiconset/icon_128x128@2x.png)

DiagramDown is a native macOS Markdown editor designed for documents that mix prose and diagrams. The long-term goal is an offline editor with live Markdown preview plus first-class Mermaid and D2 fenced code blocks.

The name combines the product's two core ideas: diagrams and Markdown.

## Current status

Version `0.22.0` makes the folder workspace DiagramDown's only application mode
and adds crash-safe restoration:

- Open a folder with **File > Open Folder…** or `Command-O`
- Reopen the most recently used folder automatically when DiagramDown launches
- Show an in-app **Open Folder…** welcome screen when no folder has been used
- Browse a lazily loaded, sandbox-aware directory tree
- Open and switch between multiple Markdown files using native workspace tabs
- Keep independent text, Undo, selection, scroll, preview, and dirty state per open file
- Save the active workspace file atomically with `Command-S`
- Confirm Save, Discard, or Cancel when closing dirty tabs or a dirty workspace window
- Restore sandbox authority from security-scoped folder bookmarks
- Reject invalid UTF-8, oversized files, symbolic links, and paths outside the workspace root
- Native `NSTextView` editing with macOS input methods
- Native line-number gutter with logical-line numbering and current-line emphasis
- Undo and redo, selection, scrolling, and find bar support
- UTF-8 document storage and explicit atomic saving
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
- Offline Markdown and embedded-code formatting with bundled Prettier
- Official D2 fenced-block formatting with the bundled `d2 fmt` command
- Preview syntax highlighting for explicitly labeled code fences
- Per-window Editor Only, Editor and Preview, and Preview Only layouts
- Focused Mermaid and D2 diagram viewer with fit, 25%–400% zoom, and keyboard controls
- Two-finger trackpad pinch zoom for the Markdown preview and focused diagram viewer
- Native unit tests for zoom, layouts, document encoding, D2 configuration, and scroll state
- Structural preview-runtime tests for offline assets, CSP, WebKit bridges, diagram controls, and gestures
- Automated arm64 archive, Developer ID export, ZIP packaging, notarization, and ticket stapling
- Release validation for nested signatures, Hardened Runtime, sandbox entitlements, architectures, licenses, and Gatekeeper
- MIT license bundled with packaged builds
- Bundled example covering Markdown, Mermaid, D2, focused diagrams, and PDF export
- Help menu links for keyboard shortcuts, documentation, feedback, and release notes
- Privacy-preserving diagnostics export that excludes document content, names, paths, and personal identifiers
- Sanitized environment, preference, D2 helper, and cache summaries for actionable issue reports

The first public release supports Apple Silicon Macs only. Intel support and a universal D2 helper are deferred.

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

## Download

Download the latest DMG and matching SHA-256 checksum from [GitHub Releases](https://github.com/Weichen-LF/DiagramDown/releases/latest).

> [!IMPORTANT]
> The current Apple Silicon build is ad-hoc signed and is not notarized by Apple. macOS Gatekeeper may block its first launch. Verify the checksum and repository source, then use Finder's **Open** command or **Open Anyway** in System Settings > Privacy & Security. Never disable Gatekeeper globally.

To build the same public community-release package locally:

```sh
./Scripts/package-release.sh
```

The script runs the automated suite, creates an arm64 Release build with ad-hoc signatures, validates the application and bundled D2 helper, and writes a drag-to-Applications DMG plus SHA-256 checksum under `artifacts/`. See [the release guide](docs/release.md) for verification and first-launch instructions.

An optional Developer ID packaging path remains available for a future notarized distribution:

```sh
./Scripts/release.sh
```

DiagramDown is open source under the [MIT License](LICENSE).

## Contributing and security

See [CONTRIBUTING.md](CONTRIBUTING.md) for development and pull-request guidance. Report security-sensitive problems privately by following [SECURITY.md](SECURITY.md); do not include vulnerabilities, credentials, or private documents in regular issues.

## Project layout

- `Mark/MarkdownFileCodec.swift`: shared UTF-8 Markdown encoding and decoding
- `Mark/MarkdownEditorView.swift`: native AppKit editor embedded in SwiftUI
- `Mark/MarkdownFormattingService.swift`: isolated offline Prettier runtime and formatting coordination
- `Mark/FormattingCommands.swift`: native Format Document command and focused action
- `Mark/LineNumberTextView.swift`: native editor text drawing with visible logical-line numbering
- `Mark/EditorPreviewSurface.swift`: editor and preview surface used by workspace tabs
- `Mark/WorkspaceSceneView.swift`: single folder-workspace application entry point
- `Mark/WorkspaceModels.swift`: folder authorization, directory tree, and file buffers
- `Mark/WorkspaceRecovery.swift`: atomic workspace tab and unsaved-edit recovery snapshots
- `Mark/WorkspaceLaunchRestoration.swift`: last-folder persistence and launch reopening
- `Mark/WorkspaceView.swift`: folder sidebar, tab bar, multi-file editing, and close protection
- `Mark/WorkspaceCommands.swift`: Open Folder and workspace Save commands
- `Mark/MarkdownPreviewView.swift`: persistent WebKit preview and update coordination
- `Mark/ScrollSyncState.swift`: editor-preview scroll position and source target state
- `Mark/D2RenderService.swift`: bounded D2 process execution, temporary-file lifecycle, and two-level cache
- `Mark/PreviewSettingsView.swift`: persistent appearance and preview preferences
- `Mark/PreviewCommands.swift`: preview zoom and PDF export commands
- `Mark/AppCommands.swift`: Help menu commands and bundled example metadata
- `Mark/DiagnosticsReport.swift`: privacy-preserving support report generation and export
- `Mark/DiagramDown.entitlements`: explicit sandbox permissions used by signed builds
- `Mark/Resources/Preview`: bundled offline preview runtime
- `Mark/Resources/Formatter`: bundled offline Prettier runtime
- `Mark/Resources/DiagramDown-Example.md`: editable first-run example document
- `MarkTests`: native unit tests for core document and preview behavior
- `Tests/PreviewRuntimeTests.mjs`: offline preview structure and bridge regression tests
- `Scripts/test.sh`: complete local test entry point
- `Scripts/package-release.sh`: ad-hoc signed Apple Silicon DMG packaging and checksum generation
- `Scripts/package-private-beta.sh`: compatibility wrapper for the community-release packager
- `Scripts/release.sh`: Developer ID archive, export, packaging, and optional notarization
- `Scripts/validate-release.sh`: architecture, signature, entitlement, license, and Gatekeeper checks
- `Config/ExportOptions-DeveloperID.plist`: reproducible Developer ID export configuration
- `Helpers/d2`: sandbox-inheriting D2 arm64 helper
- `docs/examples/mermaid.md`: Mermaid rendering smoke-test document
- `docs/examples/d2.md`: D2 rendering smoke-test document
- `docs/examples/all-features.md`: combined release smoke-test document
- `docs/swiftui-markdown-mermaid-d2-design.md`: architecture and phased implementation plan
- `docs/workspace-folder-design.md`: folder workspace architecture and delivery plan
- `docs/product-identity.md`: product name, icon, and visual identity notes
- `docs/release.md`: signing, notarization, and release runbook
- `docs/release-checklist.md`: tag, package, GitHub Release, and verification checklist

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
16. Automated tests, release validation, and MIT licensing — complete
17. Apple Silicon community-release packaging — complete
18. Tag-driven GitHub Release automation — complete for `0.17.0`
19. First-run example, Help menu, diagnostics export, and support hardening — complete for `0.19.0`
20. Reliable PDF export, document formatting, and fenced-code highlighting — complete for `0.20.0`
21. Folder workspaces, lazy directory trees, and multi-file Markdown tabs — complete for `0.21.0`
22. Workspace-only startup, tab and unsaved-edit restoration, and DMG distribution — complete for `0.22.0`
23. External file changes and workspace file operations — planned
24. Notarized distribution and universal Intel support — optional later work
