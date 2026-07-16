# DiagramDown

![DiagramDown app icon](Mark/Assets.xcassets/AppIcon.appiconset/icon_128x128@2x.png)

DiagramDown is a native macOS Markdown editor designed for documents that mix prose and diagrams. The long-term goal is an offline editor with live Markdown preview plus first-class Mermaid and D2 fenced code blocks.

The name combines the product's two core ideas: diagrams and Markdown. It is a working product name and can still change before the first public release.

## Current status

Version `0.5.1` adds the first diagram cache and stable preview identities:

- Create, open, edit, and save `.md` and `.markdown` files
- Native `NSTextView` editing with macOS input methods
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
- Stable Mermaid and D2 block identities across preview revisions
- Flicker-free D2 updates that reuse unchanged SVGs and retain the previous diagram while edited source renders

The bundled D2 helper currently supports Apple Silicon Macs. A universal helper is planned before public release.

## Requirements

- macOS 15.0 or later
- Apple Silicon for D2 rendering
- Xcode with the macOS SDK and SwiftUI support

## Build

Open `Mark.xcodeproj` in Xcode and run the `Mark` scheme, or build from the command line:

```sh
xcodebuild \
  -project Mark.xcodeproj \
  -scheme Mark \
  -configuration Debug \
  -derivedDataPath /tmp/DiagramDownDerivedData \
  build
```

## Project layout

- `Mark/MarkdownDocument.swift`: Markdown file lifecycle
- `Mark/MarkdownEditorView.swift`: native AppKit editor embedded in SwiftUI
- `Mark/ContentView.swift`: document window content
- `Mark/MarkdownPreviewView.swift`: persistent WebKit preview and update coordination
- `Mark/D2RenderService.swift`: bounded D2 process execution, temporary-file lifecycle, and memory cache
- `Mark/Resources/Preview`: bundled offline preview runtime
- `Helpers/d2`: sandbox-inheriting D2 arm64 helper
- `docs/examples/mermaid.md`: Mermaid rendering smoke-test document
- `docs/examples/d2.md`: D2 rendering smoke-test document
- `docs/swiftui-markdown-mermaid-d2-design.md`: architecture and phased implementation plan
- `docs/product-identity.md`: working name, icon, and visual identity notes

## Roadmap

1. Native Markdown editor — complete for the MVP
2. Local WebKit Markdown preview — complete for the MVP
3. Mermaid fenced-block rendering — complete for the MVP
4. Sandboxed D2 CLI rendering — complete for the MVP
5. D2 memory cache and stable diagram identity — complete
6. Editor-preview scroll synchronization — next
7. D2 preview settings — planned
8. Disk cache, preview zoom, and export — planned
