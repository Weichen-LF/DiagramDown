<p align="center">
  <img src="Mark/Assets.xcassets/AppIcon.appiconset/icon_128x128@2x.png" width="128" alt="DiagramDown app icon">
</p>

<h1 align="center">DiagramDown</h1>

<p align="center">
  <strong>Markdown and diagrams, side by side.</strong>
</p>

<p align="center">
  A native macOS workspace for writing Markdown with live Mermaid and D2 diagrams.
  Fast, private, and fully offline.
</p>

<p align="center">
  <a href="https://github.com/Weichen-LF/DiagramDown/releases/latest"><strong>Download the latest release</strong></a>
  ·
  <a href="CHANGELOG.md">What’s new</a>
  ·
  <a href="https://github.com/Weichen-LF/DiagramDown/issues">Feedback</a>
</p>

<p align="center">
  <a href="https://github.com/Weichen-LF/DiagramDown/actions/workflows/ci.yml"><img src="https://github.com/Weichen-LF/DiagramDown/actions/workflows/ci.yml/badge.svg" alt="CI status"></a>
  <a href="https://github.com/Weichen-LF/DiagramDown/actions/workflows/codeql.yml"><img src="https://github.com/Weichen-LF/DiagramDown/actions/workflows/codeql.yml/badge.svg" alt="CodeQL status"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="MIT license"></a>
</p>

## Write ideas. Draw systems.

DiagramDown brings prose and diagrams into one focused workspace. Open a folder,
write naturally in Markdown, and see the finished document update beside you.
Mermaid and D2 fenced blocks become live diagrams through command-line tools
installed on your Mac, without a server or cloud account.

The native SwiftUI preview, Tree-sitter syntax highlighting, and Swift Markdown
formatter are bundled with the app. DiagramDown calls local `mmdc`/`mmdr` and
`d2` executables directly; your documents stay on your Mac.

## Features

### Workspace

- Open a folder of Markdown files and browse them in a sidebar tree
- Create, rename, move, and delete files or folders from the app
- Keep multiple documents open in tabs, with **Open Recent** for folders
- Restore the last folder, window frame, sidebar width, tabs, layout, scroll
  position, and unsaved edits after relaunch
- Detect external file changes and deletions, with conflict handling for dirty
  buffers

### Editing

- Native macOS text editing with line numbers, Undo, Find, and familiar shortcuts
- Edit-menu Markdown actions for emphasis, links, headings, quotes, lists, code
  blocks, tables, and horizontal rules
- **Insert Image…** to pick a local image, optionally copy it into workspace
  `assets/`, and insert a document-relative Markdown path
- Format Document for Markdown and embedded D2 fences
- Tree-sitter highlighting for common languages, including Dockerfile, Python,
  SQL, Go, and Lua

### Preview and diagrams

- Live Markdown preview with light/dark themes and zoom
- Mermaid and D2 fences render through local CLIs; choose `mmdc` (PNG) or
  `mmdr` (SVG) for Mermaid in Settings; missing tools fall back to fenced source
- Focused Mermaid/D2 viewer: resize the sheet, pinch to zoom, and export SVG
- Sharper Mermaid PNG previews at 2× render scale when using `mmdc`
- Mermaid and D2 fences show as code while rendering, then swap in when ready
- Sidebar tree auto-refreshes when files or folders change on disk
- Active-line highlighting in the Markdown editor
- Local images from relative, absolute, or `file://` paths (PNG, JPEG, GIF,
  TIFF, BMP, HEIC, WebP, SVG, and more), with a resizable full viewer
- Open files in **Preview Only** by default; switch layouts anytime from the
  toolbar
- Scroll sync between editor and preview; click the preview to jump to source
- Export the complete preview as PDF

Choose the layout that fits the moment: **Editor Only**, **Editor and Preview**,
or **Preview Only**.

## Get started

1. Download the Apple Silicon DMG from [GitHub Releases](https://github.com/Weichen-LF/DiagramDown/releases/latest).
2. Drag `DiagramDown.app` into Applications.
3. Clear the quarantine attribute (required while the community build is not
   Apple-notarized), then open the app:

```sh
xattr -r -d com.apple.quarantine /Applications/DiagramDown.app
open /Applications/DiagramDown.app
```

4. Open a folder containing `.md` or `.markdown` files and start writing.

For diagram previews, install either or both optional tools:

```sh
npm install -g @mermaid-js/mermaid-cli
brew tap 1jehuang/mmdr && brew install mmdr
brew install d2
```

Choose Mermaid rendering (`mmdc` PNG or `mmdr` SVG) under **Settings > Mermaid
Preview**. Missing tools simply leave their fenced source visible as code.
Their detected versions and paths are shown under **Settings > Diagram Tools**.

DiagramDown requires macOS 15 or later on Apple Silicon.

> [!IMPORTANT]
> The current community build is ad-hoc signed and is **not** notarized by
> Apple (no Developer ID certificate yet). macOS Gatekeeper will usually block
> a freshly downloaded copy.
>
> Prefer removing the quarantine attribute with `xattr` as shown above. You
> can also Control-click the app in Finder and choose **Open**, or use
> **Open Anyway** in System Settings > Privacy & Security. Never disable
> Gatekeeper globally.

## Current release

DiagramDown `0.26.0` is an Apple Silicon release. It refreshes the sidebar tree
when the filesystem changes, highlights the active editor line, and lets you
choose Mermaid rendering with `mmdc` (PNG) or `mmdr` (SVG).

Intel Macs and automatic updates are not available yet.

<details>
<summary><strong>Build from source</strong></summary>

Requirements:

- macOS 15 or later
- Apple Silicon
- Xcode with the macOS SDK

Open `Mark.xcodeproj` and run the `Mark` scheme, or use:

```sh
xcodebuild \
  -project Mark.xcodeproj \
  -scheme Mark \
  -configuration Debug \
  -derivedDataPath /tmp/DiagramDownDerivedData \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Run the complete test suite:

```sh
./Scripts/test.sh
```

Create the ad-hoc signed Apple Silicon DMG:

```sh
./Scripts/package-release.sh
```

See [the release guide](docs/release.md) for packaging and verification details.

</details>

## Project

- Read the [native preview architecture](docs/native-markdown-preview-architecture.md).
- See the [migration plan](docs/DiagramDown_native_markdown_preview_migration_plan.md)
  and [implementation notes](docs/native-preview-migration-notes.md).
- Explore the [folder workspace design](docs/workspace-folder-design.md).
- See [CONTRIBUTING.md](CONTRIBUTING.md) before proposing a change.
- Follow [SECURITY.md](SECURITY.md) for security-sensitive reports.

DiagramDown is open source under the [MIT License](LICENSE).
