//
//  NativePreviewTests.swift
//  DiagramDownTests
//

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

final class NativePreviewSafetyTests: XCTestCase {
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

    func testImageResolverAllowsWorkspaceRelativePathsAndBlocksEscape() throws {
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let documents = workspace.appendingPathComponent("docs", isDirectory: true)
        let assets = workspace.appendingPathComponent("assets", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: workspace) }
        try FileManager.default.createDirectory(
            at: documents,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: assets,
            withIntermediateDirectories: true
        )
        let expected = Data([0x89, 0x50, 0x4E, 0x47])
        try expected.write(to: assets.appendingPathComponent("image.png"))
        let documentURL = documents.appendingPathComponent("README.md")

        let loaded = try PreviewImageResolver.data(
            for: PreviewImage(
                source: "../assets/image.png",
                title: nil,
                alt: "fixture"
            ),
            documentURL: documentURL,
            workspaceRootURL: workspace
        )

        XCTAssertEqual(loaded, expected)
        XCTAssertThrowsError(
            try PreviewImageResolver.data(
                for: PreviewImage(
                    source: "../../outside.png",
                    title: nil,
                    alt: ""
                ),
                documentURL: documentURL,
                workspaceRootURL: workspace
            )
        ) { error in
            XCTAssertEqual(error as? PreviewImageLoadingError, .outsideWorkspace)
        }
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
    }
}

final class NativePreviewHighlightingTests: XCTestCase {
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
            (.javascript, "const answer = 42; // ready"),
            (.json, #"{"answer": 42, "ready": true}"#),
            (.lua, "local answer = 42 -- ready"),
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
}

final class NativePreviewDiagramTests: XCTestCase {
    func testBundledMermaidRuntimeProducesSanitizableSVGOffline() async throws {
        let rawSVG = try await MermaidRenderService.shared.render(
            source: "flowchart LR\n  A --> B",
            theme: .default,
            appearance: "light"
        )
        let document = try await SVGSanitizer.shared.sanitize(rawSVG)

        XCTAssertTrue(document.sanitizedXML.localizedCaseInsensitiveContains("<svg"))
        XCTAssertFalse(document.sanitizedXML.localizedCaseInsensitiveContains("<script"))
        XCTAssertGreaterThan(document.intrinsicSize.width, 0)
        XCTAssertGreaterThan(document.intrinsicSize.height, 0)
    }

    func testDiagramCacheKeyTracksContentAndThemeButNotViewRevision() async throws {
        let configuration = DiagramConfiguration(
            mermaidTheme: .default,
            appearance: "light",
            d2: .preview
        )
        let first = try await DiagramRenderCoordinator.shared.render(
            DiagramRenderRequest(
                blockID: PreviewBlockID(rawValue: "first"),
                revision: 1,
                kind: .mermaid,
                source: "flowchart LR\n  Cache --> Hit",
                configuration: configuration
            )
        )
        let second = try await DiagramRenderCoordinator.shared.render(
            DiagramRenderRequest(
                blockID: PreviewBlockID(rawValue: "second"),
                revision: 99,
                kind: .mermaid,
                source: "flowchart LR\n  Cache --> Hit",
                configuration: configuration
            )
        )
        let dark = try await DiagramRenderCoordinator.shared.render(
            DiagramRenderRequest(
                blockID: PreviewBlockID(rawValue: "dark"),
                revision: 100,
                kind: .mermaid,
                source: "flowchart LR\n  Cache --> Hit",
                configuration: DiagramConfiguration(
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
}
