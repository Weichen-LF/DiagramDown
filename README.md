# DiagramDown

![DiagramDown app icon](Mark/Assets.xcassets/AppIcon.appiconset/icon_128x128@2x.png)

DiagramDown is a native macOS Markdown editor designed for documents that mix prose and diagrams. The long-term goal is an offline editor with live Markdown preview plus first-class Mermaid and D2 fenced code blocks.

The name combines the product's two core ideas: diagrams and Markdown. It is a working product name and can still change before the first public release.

## Current status

Version `0.2.0` adds the first preview MVP:

- Create, open, edit, and save `.md` and `.markdown` files
- Native `NSTextView` editing with macOS input methods
- Undo and redo, selection, scrolling, and find bar support
- UTF-8 document storage and automatic document saving
- App Sandbox access to user-selected files
- Live split-view Markdown preview backed by a persistent `WKWebView`
- Bundled offline `markdown-it` rendering with light and dark appearance support

Mermaid and D2 rendering are planned but not implemented yet.

## Requirements

- macOS 15.0 or later
- Xcode with the macOS SDK and SwiftUI support

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

## Project layout

- `Mark/MarkdownDocument.swift`: Markdown file lifecycle
- `Mark/MarkdownEditorView.swift`: native AppKit editor embedded in SwiftUI
- `Mark/ContentView.swift`: document window content
- `Mark/MarkdownPreviewView.swift`: persistent WebKit preview and update coordination
- `Mark/Resources/Preview`: bundled offline preview runtime
- `docs/swiftui-markdown-mermaid-d2-design.md`: architecture and phased implementation plan
- `docs/product-identity.md`: working name, icon, and visual identity notes

## Roadmap

1. Native Markdown editor — complete for the MVP
2. Local WebKit Markdown preview — complete for the MVP
3. Mermaid fenced-block rendering — next
4. Sandboxed D2 CLI rendering
5. Caching, scroll sync, themes, and export
