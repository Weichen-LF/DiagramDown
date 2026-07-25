# Native preview migration notes

This file records implementation choices and measured verification for
`DiagramDown_native_markdown_preview_migration_plan.md`.

## Implemented

- `swift-markdown` AST adapter and Sendable `PreviewDocument` model
- source ranges, content fingerprints, and indexed stable block-ID
  reconciliation without per-block full-array scans
- native SwiftUI blocks, themes, appearance, zoom, click-to-source, and
  bidirectional scroll synchronization
- Tree-sitter highlighter with bounded, memory-pressure-aware cache and pinned
  grammar versions
- optional user-installed `mmdc` and `d2` renderers with safe code-block
  fallback when a tool is unavailable
- SVG sanitation, native SVG display, viewer, and atomic SVG export
- native PDF snapshot and AppKit print pipeline
- bounded memory and disk caching for sanitized diagram output, including
  explicit cache statistics and memory-pressure purging
- native Markdown formatting through `swift-markdown`, with fenced source
  preserved except for local D2 CLI formatting
- workspace-root-confined local image loading in preview and PDF export
- removal of WebKit, JavaScriptCore, Prettier, markdown-it, highlight.js,
  preview HTML/CSS/JS, DOM export, D2 Web bridge, and JavaScript scroll
  synchronization
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

- macOS XCTest: passed after switching completely to the native preview,
  including fake local CLI rendering followed by SVG sanitation, all
  first-batch Tree-sitter grammars, versioned diagram caches, confined local
  images, and PDF image snapshots.
- Debug app resource inspection confirmed all first-batch grammar query bundles
  and package licenses are present; no WebKit, JavaScriptCore, Prettier, or
  bundled diagram runtime remains.
- The final full `Scripts/test.sh` run passed after fixing XCTest-time
  Tree-sitter query-bundle discovery. The test suite now verifies that every
  first-batch grammar loads a highlights query and emits attributed token runs.

## Follow-up benchmarks

Run `./Scripts/benchmark-native-preview.sh` to execute the opt-in benchmarks;
the normal `./Scripts/test.sh` run excludes them.

Benchmark captured on 2026-07-25 on an arm64 MacBook Pro with macOS 26.5.2,
using the Debug XCTest build:

- 20 KiB: mean 20.71 ms, P95 21.91 ms (eight samples)
- 200 KiB: mean 45.67 ms, P95 47.08 ms (eight samples)
- 500 KiB: mean 86.10 ms, P95 86.50 ms (four samples)
- 2 MiB ordinary document: 299.15 ms (one sample)
- 2 MiB single fenced code block: two revisions in 571.54 ms, one block
- 2 MiB high-structure document: two revisions in 7,890.88 ms, 39,200 blocks
- 20 Mermaid plus 20 D2 blocks: mean 2.26 ms, P95 2.86 ms (eight parser
  samples; external CLI execution is intentionally outside this source-processing
  measurement)
- ten 10 Hz revisions: 1,052.17 ms total, with only revision 10 applied
- ten 200 KiB document switches: 444.30 ms total, 1,010 blocks
- 50 unique Swift blocks: 663.40 ms cold, 4.69 ms warm
- Debug app bundle size: 58,652 KiB

The observed Medium P95 remains below the 100 ms observation target. These are
local measurements rather than stable CI assertions.

A previous deliberately adversarial 2 MiB fixture made from thousands of
repeated structural blocks did not finish within 239 seconds. Reconciliation
now indexes exact fingerprints and sweeps unmatched source ranges; a 10,000
block unit regression completes under a generous five-second CI guard, and the
opt-in benchmark now completes the 2 MiB, 39,200-block fixture. The focused
10,000-block reconciliation regression completed in 24 ms during the full
test run.

The removed WebKit pipeline is no longer available on this branch, so no
relative old/new baseline is claimed. The bounded code and SVG cache statistics,
explicit purge tests, and memory-pressure purge path passed. Two automated
`xctrace` attempts against the hardened ad-hoc Release build could not attach
to the target, so representative Allocations/Leaks observations remain a
manual release-candidate gate and are not marked complete.

## Community Release Verification

On 2026-07-25, `Scripts/test.sh`, the opt-in benchmark, and
`Scripts/package-release.sh --skip-tests --allow-dirty --expected-version
0.22.0` passed on the machine above. The resulting 0.22.0 (22) arm64 app was
ad-hoc signed with Hardened Runtime and passed `validate-release.sh --adhoc`.
Validation confirmed no App Sandbox entitlement, WebKit or JavaScriptCore
linkage, bundled Mermaid/D2 runtime, SVGView, or Prettier formatter assets.

The packaged app was 23,456 KiB and the DMG was 7,380 KiB. The DMG SHA-256 was
`ca67c7749d59f8bcc9b79e20ef785467839c7e484af574ca0799465157e0a160`.
Developer ID signing and notarization were not performed.
