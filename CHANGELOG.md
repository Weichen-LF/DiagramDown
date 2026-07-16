# Changelog

All notable changes to DiagramDown will be documented in this file.

The project follows [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Planned

- D2 preview settings

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
