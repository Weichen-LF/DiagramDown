//
//  NativePreviewTests.swift
//  DiagramDownTests
//

import AppKit
import SwiftUI
import XCTest
@testable import DiagramDown

final class NativePreviewParsingTests: XCTestCase {
    func testParserBuildsNativeBlocksForCoreMarkdownAndDiagrams() async throws {
        let source = """
        # Native Preview

        Text with *emphasis*, **strong**, ~~strike~~, [link](https://example.com), and <kbd>raw</kbd>.

        - [x] shipped
        - [ ] pending

        | Name | State |
        | :--- | ---: |
        | Parser | Ready |

        ```swift
        let answer = 42
        ```

        ```mermaid
        flowchart LR
          A --> B
        ```

        ```d2
        A -> B
        ```

        <script>alert("not executable")</script>
        """

        let document = try await MarkdownParserService.shared.parse(
            source: source,
            revision: 7,
            previous: nil
        )

        XCTAssertEqual(document.revision, 7)
        XCTAssertEqual(document.lineCount, source.split(separator: "\n", omittingEmptySubsequences: false).count)
        XCTAssertEqual(document.blocks.first?.sourceRange.startLine, 1)
        XCTAssertTrue(document.blocks.contains { block in
            guard case .heading(level: 1, let inline) = block.content else { return false }
            return inline.plainText == "Native Preview"
        })
        XCTAssertTrue(document.blocks.contains { block in
            guard case .unorderedList(let items) = block.content else { return false }
            return items.map(\.checkbox) == [true, false]
        })
        XCTAssertTrue(document.blocks.contains { block in
            guard case .table(let table) = block.content else { return false }
            return table.headers.map(\.plainText) == ["Name", "State"]
                && table.rows.first?.map(\.plainText) == ["Parser", "Ready"]
        })
        XCTAssertTrue(document.blocks.contains { block in
            guard case .code(.swift, "swift", let code) = block.content else { return false }
            return code.contains("let answer = 42")
        })
        XCTAssertTrue(document.blocks.contains { block in
            guard case .mermaid(let diagram) = block.content else { return false }
            return diagram.contains("A --> B")
        })
        XCTAssertTrue(document.blocks.contains { block in
            guard case .d2(let diagram) = block.content else { return false }
            return diagram.contains("A -> B")
        })
        XCTAssertTrue(document.blocks.contains { block in
            guard case .rawText(let raw) = block.content else { return false }
            return raw.contains("<script>") && raw.contains("not executable")
        })
    }

    func testStableBlockIDsSurviveInsertionAboveUnchangedContent() async throws {
        let original = """
        # Heading

        Keep this paragraph.

        Tail paragraph.
        """
        let first = try await MarkdownParserService.shared.parse(
            source: original,
            revision: 1,
            previous: nil
        )
        let keepID = try XCTUnwrap(block(named: "Keep this paragraph.", in: first)?.id)
        let tailID = try XCTUnwrap(block(named: "Tail paragraph.", in: first)?.id)

        let edited = """
        New top paragraph.

        \(original)
        """
        let second = try await MarkdownParserService.shared.parse(
            source: edited,
            revision: 2,
            previous: first
        )

        XCTAssertEqual(block(named: "Keep this paragraph.", in: second)?.id, keepID)
        XCTAssertEqual(block(named: "Tail paragraph.", in: second)?.id, tailID)
        XCTAssertEqual(block(named: "Keep this paragraph.", in: second)?.sourceRange.startLine, 5)
    }

    private func block(named text: String, in document: PreviewDocument) -> PreviewBlock? {
        document.blocks.first { block in
            switch block.content {
            case .heading(_, let inline), .paragraph(let inline):
                inline.plainText == text
            default:
                false
            }
        }
    }
}

final class PreviewDocumentReconcilerTests: XCTestCase {
    func testExactMatchesSurviveDeletionAndReordering() {
        let previous = [
            makeBlock(id: "old-a", line: 1, fingerprint: "a"),
            makeBlock(id: "old-b", line: 3, fingerprint: "b"),
            makeBlock(id: "old-c", line: 5, fingerprint: "c"),
        ]
        let updated = [
            makeBlock(id: "new-c", line: 1, fingerprint: "c"),
            makeBlock(id: "new-a", line: 3, fingerprint: "a"),
        ]

        let reconciled = PreviewDocumentReconciler().reconcile(
            newBlocks: updated,
            previousBlocks: previous
        )

        XCTAssertEqual(reconciled.map(\.id.rawValue), ["old-c", "old-a"])
    }

    func testDuplicateFingerprintsAreMatchedOnceInDocumentOrder() {
        let previous = (0..<100).map {
            makeBlock(id: "old-\($0)", line: $0 * 2 + 1, fingerprint: "same")
        }
        let updated = (0..<101).map {
            makeBlock(id: "new-\($0)", line: $0 * 2 + 1, fingerprint: "same")
        }

        let reconciled = PreviewDocumentReconciler().reconcile(
            newBlocks: updated,
            previousBlocks: previous
        )

        XCTAssertEqual(
            reconciled.prefix(100).map(\.id.rawValue),
            (0..<100).map { "old-\($0)" }
        )
        XCTAssertEqual(reconciled.last?.id.rawValue, "new-100")
        XCTAssertEqual(Set(reconciled.map(\.id)).count, reconciled.count)
    }

    func testEditedBlocksReuseOverlappingIDsByKind() {
        let previous = [
            makeBlock(id: "old-1", line: 1, fingerprint: "before-1"),
            makeBlock(id: "old-2", line: 4, fingerprint: "before-2"),
        ]
        let updated = [
            makeBlock(id: "new-1", line: 1, fingerprint: "after-1"),
            makeBlock(id: "new-2", line: 4, fingerprint: "after-2"),
        ]

        let reconciled = PreviewDocumentReconciler().reconcile(
            newBlocks: updated,
            previousBlocks: previous
        )

        XCTAssertEqual(reconciled.map(\.id.rawValue), ["old-1", "old-2"])
    }

    func testTenThousandRepeatedBlocksCompleteWithoutQuadraticScan() {
        let previous = (0..<10_000).map {
            makeBlock(
                id: "old-\($0)",
                line: $0 * 2 + 1,
                fingerprint: "fingerprint-\($0 % 25)"
            )
        }
        let updated = (0..<10_000).map {
            makeBlock(
                id: "new-\($0)",
                line: $0 * 2 + 2,
                fingerprint: "fingerprint-\($0 % 25)"
            )
        }

        let start = ContinuousClock.now
        let reconciled = PreviewDocumentReconciler().reconcile(
            newBlocks: updated,
            previousBlocks: previous
        )
        let elapsed = start.duration(to: .now)

        XCTAssertEqual(reconciled.count, 10_000)
        XCTAssertEqual(Set(reconciled.map(\.id)).count, reconciled.count)
        XCTAssertLessThan(elapsed, .seconds(5))
    }

    private func makeBlock(
        id: String,
        line: Int,
        fingerprint: String
    ) -> PreviewBlock {
        PreviewBlock(
            id: PreviewBlockID(rawValue: id),
            sourceRange: PreviewSourceRange(
                startLine: line,
                startColumn: 1,
                endLine: line,
                endColumn: 10
            ),
            content: .rawText(fingerprint),
            fingerprint: fingerprint
        )
    }
}

final class NativePreviewSafetyTests: XCTestCase {
    func testInlineBuilderUsesTheRequestedContextFont() {
        let metrics = PreviewMetrics(zoom: 1)
        let theme = PreviewTheme(
            id: "test",
            background: .white,
            primaryText: .black,
            secondaryText: .gray,
            accent: .blue,
            subtleBackground: .white,
            border: .gray,
            blockQuoteBorder: .gray,
            codeTheme: CodeTheme.resolved(
                markdownTheme: .diagramDown,
                appearance: .light
            )
        )
        let content = PreviewInlineContent(nodes: [.text("Heading")])
        let body = InlineAttributedStringBuilder().build(
            content,
            theme: theme,
            metrics: metrics
        )
        let heading = InlineAttributedStringBuilder().build(
            content,
            theme: theme,
            metrics: metrics,
            baseFont: metrics.headingFont(level: 3)
        )

        XCTAssertEqual(body.runs.first?.font, .system(size: metrics.bodyFontSize))
        XCTAssertEqual(heading.runs.first?.font, metrics.headingFont(level: 3))
        XCTAssertNotEqual(body.runs.first?.font, heading.runs.first?.font)
    }

    func testHeadingFontSizesRemainVisuallyHierarchical() {
        let metrics = PreviewMetrics(zoom: 1)
        let sizes = (1...6).map(metrics.headingFontSize(level:))

        XCTAssertEqual(sizes, [30, 25, 21, 18, 16, 15])
        for pair in zip(sizes, sizes.dropFirst()) {
            XCTAssertGreaterThan(pair.0, pair.1)
        }
    }

    func testPreviewLinksAllowOnlyExplicitExternalSchemes() {
        XCTAssertNotNil(SafePreviewURL.link("https://example.com/path"))
        XCTAssertNotNil(SafePreviewURL.link("mailto:hello@example.com"))
        XCTAssertNil(SafePreviewURL.link("javascript:alert(1)"))
        XCTAssertNil(SafePreviewURL.link("file:///tmp/private"))
        XCTAssertNil(SafePreviewURL.link("../relative.md"))
    }

    func testSVGSanitizerRemovesExecutableAndExternalContent() async throws {
        let source = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 120 80" onload="alert(1)">
          <script>alert(1)</script>
          <image href="https://example.com/tracker.png" width="10" height="10"/>
          <a href="https://example.com"><rect width="20" height="20"/></a>
        </svg>
        """

        let document = try await SVGSanitizer().sanitize(source)

        XCTAssertEqual(document.intrinsicSize.width, 120)
        XCTAssertEqual(document.intrinsicSize.height, 80)
        XCTAssertFalse(document.sanitizedXML.localizedCaseInsensitiveContains("<script"))
        XCTAssertFalse(document.sanitizedXML.localizedCaseInsensitiveContains("onload"))
        XCTAssertFalse(document.sanitizedXML.contains("tracker.png"))
        XCTAssertTrue(document.sanitizedXML.contains("https://example.com"))
    }

    func testSVGSanitizerRejectsEntityDocumentsAndInvalidDimensions() async {
        do {
            _ = try await SVGSanitizer().sanitize(
                #"<!DOCTYPE svg [<!ENTITY xxe SYSTEM "file:///etc/passwd">]><svg>&xxe;</svg>"#
            )
            XCTFail("Expected prohibited XML to be rejected")
        } catch {
            XCTAssertEqual(error as? SVGSanitizerError, .prohibitedXML)
        }

        do {
            _ = try await SVGSanitizer().sanitize(
                #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 0 10"/>"#
            )
            XCTFail("Expected invalid dimensions to be rejected")
        } catch {
            XCTAssertEqual(error as? SVGSanitizerError, .invalidDimensions)
        }
    }

    func testImageResolverSupportsRelativeAndExternalLocalFiles() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let workspace = root.appendingPathComponent("workspace", isDirectory: true)
        let documents = workspace.appendingPathComponent("docs", isDirectory: true)
        let assets = workspace.appendingPathComponent("assets", isDirectory: true)
        let external = root.appendingPathComponent("external images", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(
            at: documents,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: assets,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: external,
            withIntermediateDirectories: true
        )
        let expected = Data([0x89, 0x50, 0x4E, 0x47])
        try expected.write(to: assets.appendingPathComponent("image.png"))
        let externalJPEG = external.appendingPathComponent("photo.jpeg")
        try expected.write(to: externalJPEG)
        let externalSVG = external.appendingPathComponent("diagram.svg")
        let svg = Data(
            #"<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10"/>"#.utf8
        )
        try svg.write(to: externalSVG)
        let documentURL = documents.appendingPathComponent("README.md")

        let relative = try PreviewImageResolver.data(
            for: PreviewImage(
                source: "../assets/image.png",
                title: nil,
                alt: "fixture"
            ),
            documentURL: documentURL,
            workspaceRootURL: workspace
        )
        let escapedWorkspace = try PreviewImageResolver.data(
            for: PreviewImage(
                source: "../../external%20images/photo.jpeg",
                title: nil,
                alt: "external"
            ),
            documentURL: documentURL,
            workspaceRootURL: workspace
        )
        let absolute = try PreviewImageResolver.data(
            for: PreviewImage(
                source: externalSVG.path,
                title: nil,
                alt: "svg"
            ),
            documentURL: documentURL,
            workspaceRootURL: workspace
        )
        let fileURL = try PreviewImageResolver.data(
            for: PreviewImage(
                source: externalJPEG.absoluteString,
                title: nil,
                alt: "file URL"
            ),
            documentURL: documentURL,
            workspaceRootURL: workspace
        )

        XCTAssertEqual(relative, expected)
        XCTAssertEqual(escapedWorkspace, expected)
        XCTAssertEqual(absolute, svg)
        XCTAssertEqual(fileURL, expected)
        XCTAssertNotNil(NSImage(data: absolute))
        XCTAssertThrowsError(
            try PreviewImageResolver.data(
                for: PreviewImage(
                    source: "https://example.com/image.png",
                    title: nil,
                    alt: ""
                ),
                documentURL: documentURL,
                workspaceRootURL: workspace
            )
        ) { error in
            XCTAssertEqual(error as? PreviewImageLoadingError, .remoteImageDisabled)
        }
        let unsupported = external.appendingPathComponent("notes.txt")
        try expected.write(to: unsupported)
        XCTAssertThrowsError(
            try PreviewImageResolver.data(
                for: PreviewImage(
                    source: unsupported.path,
                    title: nil,
                    alt: ""
                ),
                documentURL: documentURL,
                workspaceRootURL: workspace
            )
        ) { error in
            XCTAssertEqual(error as? PreviewImageLoadingError, .unsupportedFormat)
        }
    }
}

final class NativePreviewHighlightingTests: XCTestCase {
    func testBundledGrammarDefinitionsLoadHighlightQueries() throws {
        let registry = TreeSitterLanguageRegistry()
        for language in [
            CodeLanguage.bash,
            .dockerfile,
            .go,
            .javascript,
            .json,
            .lua,
            .python,
            .sql,
            .swift,
            .typescript,
            .tsx,
            .yaml,
        ] {
            let definition = try XCTUnwrap(
                registry.definition(for: language),
                "\(language)"
            )
            XCTAssertNotNil(
                definition.configuration.queries[.highlights],
                "\(language)"
            )
        }
    }

    func testLanguageAliasesResolveToCanonicalGrammars() {
        XCTAssertEqual(CodeLanguage.resolve("JS"), .javascript)
        XCTAssertEqual(CodeLanguage.resolve("tsx title=App"), .tsx)
        XCTAssertEqual(CodeLanguage.resolve("c++"), .cpp)
        XCTAssertEqual(CodeLanguage.resolve("shell"), .bash)
        XCTAssertEqual(CodeLanguage.resolve("yml"), .yaml)
        XCTAssertNil(CodeLanguage.resolve("unknown-language"))
    }

    func testTreeSitterHighlightingPreservesSourceText() async {
        let source = "struct Greeting { let message = \"hello\" }"
        let theme = CodeTheme.resolved(
            markdownTheme: .diagramDown,
            appearance: .light
        )

        let highlighted = await TreeSitterCodeHighlighter.shared.highlight(
            source: source,
            language: .swift,
            theme: theme
        )

        XCTAssertEqual(String(highlighted.characters), source)
    }

    func testBundledGrammarBatchProducesAttributedTokenRuns() async {
        let fixtures: [(CodeLanguage, String)] = [
            (.bash, "if true; then echo \"ready\"; fi"),
            (.dockerfile, "FROM swift:latest\nRUN echo ready"),
            (.go, "package main\nfunc main() { println(\"ready\") }"),
            (.javascript, "const answer = 42; // ready"),
            (.json, #"{"answer": 42, "ready": true}"#),
            (.lua, "local answer = 42 -- ready"),
            (.python, "def answer() -> int:\n    return 42"),
            (.sql, "SELECT answer FROM results WHERE ready = TRUE"),
            (.swift, "struct Answer { let value = 42 }"),
            (.typescript, "const answer: number = 42;"),
            (.tsx, "const view = <Text value={42} />;"),
            (.yaml, "answer: 42\nready: true"),
        ]
        let theme = CodeTheme.resolved(
            markdownTheme: .diagramDown,
            appearance: .light
        )

        for (language, source) in fixtures {
            let highlighted = await TreeSitterCodeHighlighter.shared.highlight(
                source: source,
                language: language,
                theme: theme
            )

            XCTAssertEqual(String(highlighted.characters), source, "\(language)")
            XCTAssertGreaterThan(highlighted.runs.count, 1, "\(language)")
        }
    }

    func testHighlightCacheReportsCostAndCanBePurged() async {
        let highlighter = TreeSitterCodeHighlighter()
        let theme = CodeTheme.resolved(
            markdownTheme: .diagramDown,
            appearance: .light
        )

        _ = await highlighter.highlight(
            source: "struct Cached { let value = 42 }",
            language: .swift,
            theme: theme
        )
        let populated = await highlighter.cacheStatistics()
        XCTAssertEqual(populated.entryCount, 1)
        XCTAssertGreaterThan(populated.estimatedBytes, 0)

        await highlighter.purgeCaches()
        let purged = await highlighter.cacheStatistics()
        XCTAssertEqual(
            purged,
            PreviewCacheStatistics(entryCount: 0, estimatedBytes: 0)
        )
    }
}

final class NativePreviewDiagramTests: XCTestCase {
    func testLocalMermaidCLIProducesPNGPreviewAndRawSVGExport() async throws {
        let fixture = try makeFakeMermaidCLI()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let tool = InstalledDiagramTool(
            kind: .mermaid,
            executableURL: fixture.executable,
            version: "11.16.0"
        )
        let png = try await MermaidRenderService.shared.renderPNG(
            source: "flowchart LR\n  A --> B",
            theme: .default,
            appearance: "light",
            tool: tool
        )
        let capturedArguments = try loadCapturedArguments(in: fixture.directory)
        let preview = try RasterDiagramDocument(
            data: png,
            displayScale: CGFloat(MermaidRenderService.pngScale)
        )
        let rawSVG = try await MermaidRenderService.shared.renderSVG(
            source: "flowchart LR\n  A --> B",
            theme: .default,
            tool: tool
        )

        XCTAssertEqual(MermaidRenderService.pngScale, 2)
        XCTAssertEqual(
            preview.intrinsicSize,
            CGSize(width: 0.5, height: 0.5)
        )
        XCTAssertTrue(capturedArguments.contains("-s"))
        XCTAssertTrue(capturedArguments.contains("2"))
        XCTAssertTrue(rawSVG.localizedCaseInsensitiveContains("<foreignObject"))
        XCTAssertTrue(rawSVG.contains("default mmdc output"))
    }

    func testLocalMmdrCLIProducesSanitizedSVGPreview() async throws {
        let fixture = try makeFakeMmdrCLI()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let registry = DiagramToolRegistry(
            automaticDirectories: [fixture.directory]
        )
        let coordinator = DiagramRenderCoordinator(
            toolRegistry: registry,
            diskCacheDirectoryURL: fixture.directory
                .appendingPathComponent("diagram-cache", isDirectory: true)
        )
        let result = try await coordinator.render(
            DiagramRenderRequest(
                blockID: PreviewBlockID(rawValue: "mmdr"),
                revision: 1,
                kind: .mermaid,
                source: "flowchart LR\n  A --> B",
                configuration: DiagramConfiguration(
                    mermaidRenderer: .mmdr,
                    mermaidTheme: .default,
                    appearance: "light",
                    d2: .preview
                )
            )
        )
        let capturedArguments = try loadCapturedArguments(in: fixture.directory)

        guard case .svg(let document) = result.document else {
            return XCTFail("Expected an SVG Mermaid preview from mmdr.")
        }
        XCTAssertTrue(capturedArguments.contains("-e"))
        XCTAssertTrue(capturedArguments.contains("svg"))
        XCTAssertFalse(document.sanitizedXML.localizedCaseInsensitiveContains("script"))
        XCTAssertTrue(document.sanitizedXML.contains("mmdr output"))
        XCTAssertGreaterThan(document.intrinsicSize.width, 0)
        XCTAssertGreaterThan(document.intrinsicSize.height, 0)
    }

    func testDiagramCacheKeyTracksContentAndThemeButNotViewRevision() async throws {
        let fixture = try makeFakeMermaidCLI()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let registry = DiagramToolRegistry(
            automaticDirectories: [fixture.directory]
        )
        let coordinator = DiagramRenderCoordinator(
            toolRegistry: registry,
            diskCacheDirectoryURL: fixture.directory
                .appendingPathComponent("diagram-cache", isDirectory: true)
        )
        let configuration = DiagramConfiguration(
            mermaidRenderer: .mmdc,
            mermaidTheme: .default,
            appearance: "light",
            d2: .preview
        )
        let first = try await coordinator.render(
            DiagramRenderRequest(
                blockID: PreviewBlockID(rawValue: "first"),
                revision: 1,
                kind: .mermaid,
                source: "flowchart LR\n  Cache --> Hit",
                configuration: configuration
            )
        )
        let second = try await coordinator.render(
            DiagramRenderRequest(
                blockID: PreviewBlockID(rawValue: "second"),
                revision: 99,
                kind: .mermaid,
                source: "flowchart LR\n  Cache --> Hit",
                configuration: configuration
            )
        )
        let dark = try await coordinator.render(
            DiagramRenderRequest(
                blockID: PreviewBlockID(rawValue: "dark"),
                revision: 100,
                kind: .mermaid,
                source: "flowchart LR\n  Cache --> Hit",
                configuration: DiagramConfiguration(
                    mermaidRenderer: .mmdc,
                    mermaidTheme: .dark,
                    appearance: "dark",
                    d2: .preview
                )
            )
        )

        XCTAssertEqual(first.cacheKey, second.cacheKey)
        XCTAssertEqual(first.document.digest, second.document.digest)
        XCTAssertNotEqual(first.cacheKey, dark.cacheKey)
    }

    func testDiagramCachesReportCostAndCanAllBePurged() async throws {
        let fixture = try makeFakeMermaidCLI()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let diskCacheDirectory = fixture.directory
            .appendingPathComponent("diagram-cache", isDirectory: true)
        let coordinator = DiagramRenderCoordinator(
            toolRegistry: DiagramToolRegistry(
                automaticDirectories: [fixture.directory]
            ),
            diskCacheDirectoryURL: diskCacheDirectory
        )

        _ = try await coordinator.render(
            DiagramRenderRequest(
                blockID: PreviewBlockID(rawValue: "cache"),
                revision: 1,
                kind: .mermaid,
                source: "flowchart LR\n  Cache --> Purge",
                configuration: DiagramConfiguration(
                    mermaidRenderer: .mmdc,
                    mermaidTheme: .default,
                    appearance: "light",
                    d2: .preview
                )
            )
        )
        let populated = await coordinator.cacheStatistics()
        XCTAssertEqual(populated.entryCount, 1)
        XCTAssertGreaterThan(populated.estimatedBytes, 0)
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: diskCacheDirectory.path)
        )

        try await coordinator.purgeAllCaches()
        let purged = await coordinator.cacheStatistics()
        XCTAssertEqual(
            purged,
            PreviewCacheStatistics(entryCount: 0, estimatedBytes: 0)
        )
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: diskCacheDirectory.path)
        )
    }

    private func makeFakeMermaidCLI() throws -> (
        directory: URL,
        executable: URL
    ) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let executable = directory.appendingPathComponent("mmdc")
        let pngFixture = directory.appendingPathComponent("preview.png")
        let argumentsURL = directory.appendingPathComponent("arguments.txt")
        let png = try XCTUnwrap(
            Data(
                base64Encoded:
                    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
            )
        )
        try png.write(to: pngFixture)
        let script = """
        #!/bin/sh
        if [ "$1" = "--version" ]; then
          printf '11.16.0\\n'
          exit 0
        fi
        printf '%s\\n' "$*" > "\(argumentsURL.path)"
        output=""
        while [ "$#" -gt 0 ]; do
          case "$1" in
            -o) output="$2"; shift 2 ;;
            *) shift ;;
          esac
        done
        [ -n "$output" ] || exit 8
        case "$output" in
          *.png) cp "\(pngFixture.path)" "$output" ;;
          *.svg) printf '<svg xmlns="http://www.w3.org/2000/svg" width="160" height="80"><foreignObject width="160" height="80"><div xmlns="http://www.w3.org/1999/xhtml">default mmdc output</div></foreignObject></svg>' > "$output" ;;
          *) exit 9 ;;
        esac
        """
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executable.path
        )
        return (directory, executable)
    }

    private func makeFakeMmdrCLI() throws -> (
        directory: URL,
        executable: URL
    ) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let executable = directory.appendingPathComponent("mmdr")
        let argumentsURL = directory.appendingPathComponent("arguments.txt")
        let script = """
        #!/bin/sh
        if [ "$1" = "--version" ]; then
          printf '0.2.2\\n'
          exit 0
        fi
        printf '%s\\n' "$*" > "\(argumentsURL.path)"
        output=""
        while [ "$#" -gt 0 ]; do
          case "$1" in
            -o|--output) output="$2"; shift 2 ;;
            *) shift ;;
          esac
        done
        [ -n "$output" ] || exit 8
        printf '<svg xmlns="http://www.w3.org/2000/svg" width="120" height="60"><text>mmdr output</text></svg>' > "$output"
        """
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executable.path
        )
        return (directory, executable)
    }

    private func loadCapturedArguments(in directory: URL) throws -> [String] {
        let argumentsURL = directory.appendingPathComponent("arguments.txt")
        let contents = try String(contentsOf: argumentsURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return contents.split(separator: " ").map(String.init)
    }
}

final class PreviewMediaViewerSizingTests: XCTestCase {
    func testFitZoomFallsBackToActualSizeForZeroViewport() {
        XCTAssertEqual(
            PreviewMediaViewerSizing.fitZoom(
                contentSize: CGSize(width: 2_000, height: 1_000),
                viewportSize: .zero
            ),
            1
        )
        XCTAssertEqual(
            PreviewMediaViewerSizing.fitZoom(
                contentSize: CGSize(width: 2_000, height: 1_000),
                viewportSize: CGSize(width: 800, height: 0)
            ),
            1
        )
    }

    func testFitZoomScalesDownWhenContentExceedsViewport() {
        // Viewport 848×648 → available 800×600 after 24pt padding on each side.
        XCTAssertEqual(
            PreviewMediaViewerSizing.fitZoom(
                contentSize: CGSize(width: 1_600, height: 1_200),
                viewportSize: CGSize(width: 848, height: 648)
            ),
            0.5,
            accuracy: 0.000_1
        )
    }

    func testFitZoomDoesNotUpscaleSmallerContent() {
        XCTAssertEqual(
            PreviewMediaViewerSizing.fitZoom(
                contentSize: CGSize(width: 100, height: 80),
                viewportSize: CGSize(width: 848, height: 648)
            ),
            1
        )
    }
}
