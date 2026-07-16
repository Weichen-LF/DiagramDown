# Changelog

All notable changes to DiagramDown will be documented in this file.

The project follows [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Planned

- Mermaid fenced-block rendering
- D2 fenced-block rendering

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
