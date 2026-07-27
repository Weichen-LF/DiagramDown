# Changelog

All notable changes to DiagramDown will be documented in this file.

The project follows [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.26.0] - 2026-07-27

### Added

- Sidebar directory tree auto-refreshes when files or folders change on disk
- Active-line highlighting in the Markdown editor, similar to JetBrains IDEs
- Settings option to render Mermaid with `mmdc` (PNG) or `mmdr` (SVG)
- Mermaid renderer defaults to `mmdr`

### Changed

- Diagram Tools settings list both Mermaid CLI (`mmdc`) and `mmdr`, with install
  guidance for each
- Diagram Tools moved to the bottom of Settings
- D2 and mmdr SVG previews clear the baked-in white canvas so the Markdown
  theme shows through

### Fixed

- Sidebar auto-refresh no longer publishes on unchanged polls, which was making
  nested Edit menus flicker and become unusable
- Sidebar directory polling runs every 10 seconds and also refreshes when a tree
  row is clicked, instead of scanning every second

## [0.25.0] - 2026-07-27

### Added

- Edit > Markdown > Insert Image… opens a file picker, optionally copies into
  the workspace `assets/` folder, and inserts a document-relative Markdown image
- Mermaid and D2 diagram viewer sheets are resizable and open near the size of
  the parent window
- Local Markdown images open in a resizable viewer sheet, like diagrams

### Changed

- Mermaid PNG previews render at 2× scale for sharper text and edges while
  keeping on-screen layout size unchanged
- Newly opened Markdown files default to Preview Only
- Mermaid and D2 blocks show their fenced source first, then replace it when
  rendering finishes

## [0.24.0] - 2026-07-26

### Added

- A Settings action that clears syntax-highlighting caches and all rendered
  Mermaid/D2 memory and disk caches
- Local Markdown images from document-relative paths, absolute paths, and
  `file://` URLs, including PNG, JPEG, GIF, TIFF, BMP, HEIC, WebP, and SVG
- External file-change and deletion detection with automatic clean-buffer
  reloads and explicit conflict resolution for unsaved edits
- Sidebar actions to create Markdown files and folders, rename or move workspace
  items, and delete them with confirmation
- Tree-sitter highlighting for Dockerfile, Python, SQL, Go, and Lua
- Edit-menu Markdown actions for emphasis, links, headings, quotes, lists, code
  blocks, tables, and horizontal rules
- Restored window frame and sidebar width, File > Open Recent, and Command-W to
  close the active file

### Fixed

- Mermaid previews now use PNG output from the local `mmdc`, preserving its
  default HTML labels; SVG export writes the original `mmdc` SVG without
  application-side sanitation
- Removed the Base Mermaid theme option because current Mermaid CLI versions do
  not accept it through the command-line theme argument

### Removed

- Remaining unused single-file migration artifacts: the bundled example
  document, the legacy WebKit PDF pagination helper, and the native preview
  forwarding facade

## [0.23.0] - 2026-07-26

### Added

- Local Mermaid CLI and D2 discovery, version checks, custom executable paths,
  installation guidance, and diagram-tool status in Settings
- Safe bounded CLI execution with cancellation, timeout, process-group cleanup,
  SVG sanitation, and cache invalidation when a tool path or version changes

### Changed

- Mermaid and D2 previews now use user-installed `mmdc` and `d2`; unavailable
  tools fall back to fenced source and CLI failures show a diagnostic card
- SVG display now uses the macOS native SVG image representation, and D2 emits
  only the theme for the effective appearance
- The Markdown formatter now uses `swift-markdown`; fenced code is preserved
  except for D2 blocks formatted by the local D2 CLI

### Removed

- WKWebView, JavaScriptCore, bundled Prettier, the bundled Mermaid browser
  runtime, the bundled D2 helper, SVGView, App Sandbox, and the obsolete WebKit
  network entitlement

## [0.22.0] - 2026-07-24

### Added

- Crash-safe workspace recovery for open tabs, active file, sidebar and tree state,
  per-tab layout and scroll position, and unsaved edits
- Automatic reopening of the most recently used folder workspace on application launch
- Drag-to-Applications DMG packaging for Apple Silicon community releases

### Changed

- Replaced the separate `DocumentGroup` and workspace scenes with one folder-workspace
  application scene; startup no longer presents the macOS single-file document browser
- **Open Folder…** now replaces the current window's workspace and uses `Command-O`
- Clean recovered workspace tabs reload their current on-disk contents, while dirty
  tabs retain the unsaved recovery copy

### Removed

- Single-file document creation, Finder document associations, and the separate
  `MarkdownDocument`/`ContentView` lifecycle

## [0.21.0] - 2026-07-24

### Added

- Folder workspaces opened through a sandbox-authorized **Open Folder** command
- Lazily loaded directory tree with Markdown file recognition and safe symlink handling
- Multi-file workspace tabs with independent editor, preview, Undo, selection, scroll, layout, and dirty state
- Explicit atomic saving for the active workspace file and Save All when closing a dirty workspace
- Save, Discard, and Cancel confirmation for dirty tabs and workspace windows
- Security-scoped bookmark ownership for the lifetime of each workspace window
- UTF-8 validation, a 4 MB editing limit, and root-containment checks for workspace files
- Unit coverage for directory enumeration, path containment, multi-buffer state, file loading, and saving

### Changed

- Extracted the document editor and preview into a shared surface used by single-file and workspace modes
- Retained each native editor view across tab switches so Undo, selection, and scroll state remain file-specific

## [0.20.0] - 2026-07-17

### Added

- Offline Format Document command using bundled Prettier for Markdown and supported embedded code
- Official D2 fenced-block formatting through the bundled `d2 fmt` command
- Offline syntax highlighting for explicitly labeled preview code fences
- Bundled Prettier and Highlight.js license notices and release validation

### Fixed

- Full-document PDF export now uses WebKit PDF data, validates it, and paginates it without the blank `WKPrintingView` path

## [0.19.0] - 2026-07-17

### Added

- A bundled, editable example document covering Markdown, Mermaid, D2, focused diagrams, and PDF export
- Help menu actions for the example document, keyboard shortcuts, project page, issue reporting, and release notes
- Lightweight guidance inside an empty editor that points new users to the example document
- Release validation that confirms the example document and both diagram samples are present in the packaged application
- Privacy-preserving diagnostics export with application, macOS, architecture, locale, preview settings, D2 helper, and cache summaries
- Automated diagnostics tests covering preference sanitization, path and content exclusion, and cache statistics

## [0.17.0] - 2026-07-17

### Added

- GitHub Actions CI for automated tests and an unsigned arm64 Release build
- Tag-driven GitHub Release automation for the Apple Silicon community build
- Dependabot updates for pinned GitHub Actions
- Contribution, security, issue, and pull-request guidance for repository collaboration
- MIT project license
- Apple Silicon community-release packaging with ad-hoc signature validation and a SHA-256 checksum
- A combined Markdown, Mermaid, and D2 release smoke-test document
- Public release notes and a reproducible release checklist

### Changed

- The first public release is explicitly Apple Silicon-only; a universal D2 helper and Intel support are deferred
- The public binary is distributed as an ad-hoc signed, unnotarized community release with prominent Gatekeeper instructions
- Developer ID notarization is an optional future distribution improvement rather than a blocker for the first release

## [0.16.0] - 2026-07-16

### Added

- A repeatable arm64 archive and Developer ID export workflow with optional notarization and ticket stapling
- Release validation for application and D2 helper architectures, nested signatures, Hardened Runtime, sandbox entitlements, bundled licenses, and Gatekeeper acceptance
- A Keychain-based notarization and final-device smoke-test runbook

### Changed

- The application build number is now 16 and release builds explicitly match the arm64 D2 helper architecture
- Release builds no longer inject Xcode's base debugging entitlements
- Application sandbox permissions now come from an explicit, reviewable entitlement file
- Release archives and generated artifacts are excluded from version control

## [0.15.0] - 2026-07-16

### Added

- A native `MarkTests` unit-test target with coverage for preview zoom, document layouts, UTF-8 Markdown storage, D2 configuration, error messages, and scroll state
- Node-based preview-runtime regression tests for bundled assets, content security policy, WebKit message handlers, exported entry points, diagram controls, print exclusions, and trackpad gestures
- `Scripts/test.sh` as a single entry point for JavaScript checks and macOS unit tests

### Changed

- Markdown UTF-8 encoding and decoding now use a directly testable codec
- Trackpad zoom arithmetic now uses a bounded, directly testable helper

## [0.14.0] - 2026-07-16

### Added

- Two-finger trackpad pinch zoom for the full Markdown preview
- Independent trackpad pinch zoom inside focused Mermaid and D2 diagram previews
- WebKit gesture and control-wheel handling with the existing preview zoom limits

### Changed

- Markdown pinch gestures now update the toolbar, Settings value, and persisted zoom preference

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
