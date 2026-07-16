# Changelog

All notable changes to DiagramDown will be documented in this file.

The project follows [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Planned

- Stability and automated testing
- Signing, notarization, and release preparation

## [0.13.0] - 2026-07-16

### Added

- Per-window Editor Only, Editor and Preview, and Preview Only document layouts
- A segmented toolbar control for switching layouts without changing the document
- Focused Mermaid and D2 diagram viewing in an overlay
- Independent 25%–400% diagram zoom, fit-to-window, actual size, and keyboard controls

### Changed

- Diagram hover actions now group focused preview and SVG export together

## [0.12.0] - 2026-07-16

### Added

- Full Markdown preview export to a paginated PDF
- Toolbar and Preview menu actions for starting PDF export
- Print-specific preview styling that preserves colors and avoids splitting diagrams when possible
- Export readiness checks that wait for Mermaid, D2, fonts, and final layout

## [0.11.0] - 2026-07-16

### Added

- Per-diagram SVG export for successfully rendered Mermaid and D2 blocks
- Native save panels with document-, diagram-, and source-line-based filenames

## [0.10.0] - 2026-07-16

### Added

- Persistent 50–200% Markdown preview zoom
- Preview toolbar controls, preset zoom menu, and Settings control
- Preview menu commands for zoom in, zoom out, and actual size

### Changed

- Preview zoom now uses WebKit's native page zoom without re-rendering Markdown or diagrams

## [0.9.0] - 2026-07-16

### Added

- Persistent D2 SVG cache under the sandboxed user caches directory
- SHA-256-sharded cache paths and atomic entry writes
- A 256 MB disk limit with least-recently-used cleanup to a 224 MB target

### Changed

- D2 renders can now be reused after application relaunches
- Invalid, oversized, unreadable, and symbolic-link cache entries are discarded and regenerated
- Disk cache failures remain best-effort and do not replace successful preview results with errors

## [0.8.0] - 2026-07-16

### Added

- Application appearance setting with Follow System, Light, and Dark modes
- DiagramDown, GitHub, and Paper themes for Markdown preview
- Independent light and dark Mermaid theme selection using bundled Mermaid themes

### Changed

- Appearance changes now update SwiftUI, the native editor, WebKit, Mermaid, and D2 together
- Preview theme changes apply immediately to every open document

## [0.7.0] - 2026-07-16

### Added

- App-wide D2 preview settings for Dagre or ELK layout
- Selectable light and dark D2 themes
- Configurable diagram padding and sketch style
- A Settings window with one-click default restoration

### Changed

- D2 memory and WebKit caches now include the active preview configuration
- Existing D2 SVGs remain visible while a settings change is rendered

## [0.6.3] - 2026-07-16

### Fixed

- Restored Markdown source text rendering when the line-number gutter is visible
- Draw line numbers and source text in the same `NSTextView` layer to avoid ruler and WebKit compositing conflicts

## [0.6.2] - 2026-07-16

### Added

- Native line-number gutter beside the Markdown source editor
- Logical-line numbering that does not renumber wrapped continuation lines
- Current-line emphasis, dynamic gutter width, and light/dark appearance support

### Changed

- Line numbers now refresh with text edits, selection changes, and both user and synchronized scrolling

## [0.6.1] - 2026-07-16

### Changed

- Replaced the fixed 20 ms scroll debounce with immediate updates and animation-frame coordination
- Added smooth editor-to-preview scrolling and animated preview click-to-source positioning
- Added live preview-to-editor synchronization for user-initiated preview scrolling
- Suppressed reverse updates during programmatic scrolling to prevent feedback loops

## [0.6.0] - 2026-07-16

### Added

- Source-line anchors on rendered Markdown, Mermaid, and D2 blocks
- Debounced editor-to-preview scroll synchronization with anchor interpolation and proportional fallback
- Click-to-source navigation from preview blocks to the corresponding editor line

### Changed

- Scroll position updates no longer trigger unnecessary Markdown preview renders

## [0.5.1] - 2026-07-16

### Fixed

- Prevented D2 diagrams from flashing through their pending state on ordinary Markdown edits
- Kept the previous successful D2 SVG visible while changed diagram source is rendered
- Avoided native D2 render requests for unchanged blocks already cached in the preview runtime

## [0.5.0] - 2026-07-16

### Added

- 32 MB in-memory LRU cache for generated D2 SVGs
- SHA-256 cache keys that include source, D2 version, CPU architecture, and render configuration
- Stable content-based block IDs for Mermaid and D2 diagrams, including distinct IDs for duplicate blocks

## [0.4.0] - 2026-07-16

### Added

- Bundled D2 0.7.1 arm64 helper with sandbox inheritance and Hardened Runtime signing
- D2 fenced-block rendering through a native WebKit message bridge
- D2 process cancellation, a 6 second timeout, and input/output size limits
- Inline D2 errors with expandable source
- SVG sanitization before D2 output is inserted into the preview

## [0.3.1] - 2026-07-16

### Fixed

- Replaced the local Mermaid ESM import with the official single-file browser runtime for reliable `WKWebView` file URL loading
- Added an explicit JavaScript runtime readiness check and an in-preview failure message

## [0.3.0] - 2026-07-16

### Added

- Offline Mermaid 11.16.0 rendering for fenced `mermaid` code blocks
- Inline Mermaid parse errors with an expandable source view
- Mermaid themes that follow the macOS light or dark appearance

## [0.2.1] - 2026-07-16

### Fixed

- Enabled the App Sandbox outgoing client entitlement required for WebKit content and network subprocesses, preventing the preview pane from remaining blank

## [0.2.0] - 2026-07-16

### Added

- Native split view with a long-lived WebKit preview
- Offline Markdown rendering using bundled markdown-it 14.3.0
- Light and dark preview styles for headings, lists, quotes, tables, links, and code
- Debounced preview updates that preserve the current scroll ratio
- Local content security policy and external-link handoff to macOS

## [0.1.0] - 2026-07-16

### Added

- Document-based Markdown file creation, opening, editing, and saving
- Native AppKit text editor embedded in SwiftUI
- UTF-8 support for `.md` and `.markdown` documents
- Initial DiagramDown product identity and app icon
