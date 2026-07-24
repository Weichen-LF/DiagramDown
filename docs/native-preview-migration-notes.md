# Native preview migration notes

This file records implementation choices and measured verification for
`DiagramDown_native_markdown_preview_migration_plan.md`.

## Implemented

- `swift-markdown` AST adapter and Sendable `PreviewDocument` model
- source ranges, content fingerprints, and stable block-ID reconciliation
- native SwiftUI blocks, themes, appearance, zoom, click-to-source, and
  bidirectional scroll synchronization
- Tree-sitter highlighter with bounded cache and pinned grammar versions
- native D2 path and isolated hidden Mermaid SVG renderer
- SVG sanitation, native SVG display, viewer, and atomic SVG export
- native PDF snapshot and AppKit print pipeline
- memory and disk caching for sanitized diagram output
- workspace-root-confined local image loading in preview and PDF export
- removal of markdown-it, highlight.js, visible preview HTML/CSS/JS, DOM export,
  D2 Web bridge, and JavaScript scroll synchronization
- package licenses, runtime tests, release validation, and architecture docs

## Deliberate staged item

The migration plan permits grammar integration in three batches when adding all
grammars at once makes package size and build cost unacceptable. This change
ships batch 1: Swift, Lua, JavaScript/JSX, TypeScript/TSX, JSON, YAML, and Bash.
The remaining recognized languages render as safe plain text until batches 2
and 3 add their pinned grammars. No JavaScript highlighter fallback remains.

Several current grammar tags use a manifest-time relative-file check that omits
`scanner.c` in Xcode's package graph. DiagramDown therefore pins the latest
compatible official tags whose manifests explicitly include the required
external scanner:

- TreeSitterJavaScript 0.23.1
- TreeSitterLua 0.3.0
- TreeSitterYAML 0.7.0

Grammar versions are part of the highlighter cache key.

## Verification record

- Node bundled-runtime tests: 6 passed after legacy runtime removal.
- macOS XCTest: passed after switching completely to the native preview,
  including a real offline Mermaid render followed by SVG sanitation, all
  first-batch Tree-sitter grammars, versioned diagram caches, confined local
  images, and PDF image snapshots.
- Debug app resource inspection confirmed the Mermaid runtime, all first-batch
  grammar query bundles, and package licenses are present; no legacy preview
  runtime file is bundled.
- The final full `Scripts/test.sh` run passed after fixing XCTest-time
  Tree-sitter query-bundle discovery. The test suite now verifies that every
  first-batch grammar loads a highlights query and emits attributed token runs.

## Follow-up benchmarks

Run `./Scripts/benchmark-native-preview.sh` to execute the opt-in benchmarks;
the normal `./Scripts/test.sh` run excludes them.

Baseline captured on 2026-07-24 on an arm64 MacBook Pro with macOS 26.5.2,
using the Debug XCTest build:

- parser scenarios (20 KiB and 200 KiB sampled eight times, 2 MiB sampled
  once) completed together in 0.874 seconds
- 50 unique Swift blocks, measured with cold then warm Tree-sitter caches,
  completed together in 0.649 seconds
- Debug app bundle size: 110,684 KiB

The benchmark prints per-scenario mean/P95 parser timings and cold/warm
highlighter timings when run from Xcode. The aggregate XCTest durations above
come from the command-line result bundle.

A deliberately adversarial 2 MiB fixture made from thousands of repeated
structural blocks did not finish within 239 seconds and was interrupted. The
repeatable size benchmark instead fixes structural complexity at 20 sections
and pads document prose. Treat very-high block-count reconciliation as a
separate performance issue before the release candidate.

The removed WebKit pipeline is no longer available on this branch, so a
relative old/new baseline was not fabricated. Instruments memory/leak
observations also remain required before declaring a release candidate.
