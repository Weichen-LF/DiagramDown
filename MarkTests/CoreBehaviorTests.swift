import Foundation
import XCTest
@testable import DiagramDown

final class PreviewZoomTests: XCTestCase {
    func testClampingUsesSupportedBounds() {
        XCTAssertEqual(PreviewZoom.clamped(PreviewZoom.minimum - 1), PreviewZoom.minimum)
        XCTAssertEqual(PreviewZoom.clamped(125), 125)
        XCTAssertEqual(PreviewZoom.clamped(PreviewZoom.maximum + 1), PreviewZoom.maximum)
    }

    func testScalingRoundsAndClampsTrackpadValues() {
        XCTAssertEqual(PreviewZoom.scaled(100, by: 1.126), 113)
        XCTAssertEqual(PreviewZoom.scaled(100, by: 0.874), 87)
        XCTAssertEqual(PreviewZoom.scaled(190, by: 2), PreviewZoom.maximum)
        XCTAssertEqual(PreviewZoom.scaled(60, by: 0.1), PreviewZoom.minimum)
        XCTAssertEqual(PreviewZoom.scaled(100, by: .infinity), 100)
    }

    func testMenuValuesAreOrderedAndContainDefault() {
        XCTAssertEqual(PreviewZoom.menuValues, PreviewZoom.menuValues.sorted())
        XCTAssertTrue(PreviewZoom.menuValues.contains(PreviewZoom.defaultValue))
        XCTAssertTrue(PreviewZoom.menuValues.allSatisfy {
            (PreviewZoom.minimum...PreviewZoom.maximum).contains($0)
        })
    }
}

final class DocumentViewModeTests: XCTestCase {
    func testAllDocumentLayoutsRemainAvailable() {
        XCTAssertEqual(
            DocumentViewMode.allCases.map(\.rawValue),
            ["editorOnly", "editorAndPreview", "previewOnly"]
        )
    }

    func testPreviewVisibilityMatchesLayout() {
        XCTAssertFalse(DocumentViewMode.editorOnly.showsPreview)
        XCTAssertTrue(DocumentViewMode.editorAndPreview.showsPreview)
        XCTAssertTrue(DocumentViewMode.previewOnly.showsPreview)
    }

    func testEveryLayoutHasToolbarMetadata() {
        for mode in DocumentViewMode.allCases {
            XCTAssertFalse(mode.title.isEmpty)
            XCTAssertFalse(mode.systemImage.isEmpty)
        }
    }
}

final class MarkdownFileCodecTests: XCTestCase {
    func testUTF8RoundTripPreservesMarkdownAndUnicode() throws {
        let markdown = "# DiagramDown\n\n中文内容 🌏\n\n```mermaid\nA --> B\n```\n"
        let data = try MarkdownFileCodec.encode(markdown)

        XCTAssertEqual(try MarkdownFileCodec.decode(data), markdown)
    }

    func testInvalidUTF8IsRejected() {
        let invalidUTF8 = Data([0xC3, 0x28])

        XCTAssertThrowsError(try MarkdownFileCodec.decode(invalidUTF8)) { error in
            XCTAssertEqual((error as? CocoaError)?.code, .fileReadInapplicableStringEncoding)
        }
    }
}

final class OnboardingTests: XCTestCase {
    func testBundledExampleExercisesMarkdownAndBothDiagramRenderers() throws {
        let source = try ExampleDocument.source()

        XCTAssertTrue(source.contains("# Welcome to DiagramDown"))
        XCTAssertTrue(source.contains("```mermaid"))
        XCTAssertTrue(source.contains("```d2"))
        XCTAssertTrue(source.contains("## Export"))
    }

    func testHelpLinksUseSecureProjectURLs() {
        let links = [
            DiagramDownLinks.project,
            DiagramDownLinks.feedback,
            DiagramDownLinks.releaseNotes,
        ]

        XCTAssertTrue(links.allSatisfy { $0.scheme == "https" })
        XCTAssertTrue(links.allSatisfy { $0.host == "github.com" })
        XCTAssertTrue(links.allSatisfy { $0.path.hasPrefix("/Weichen-LF/DiagramDown") })
    }

    func testBlankEditorGuidancePointsToTheExampleDocument() {
        XCTAssertTrue(EditorGuidance.placeholder.contains("Help"))
        XCTAssertTrue(EditorGuidance.placeholder.contains("Example Document"))
    }
}

final class DiagnosticsReportTests: XCTestCase {
    func testReportContainsActionableEnvironmentAndConfiguration() {
        let snapshot = DiagnosticsSnapshot(
            generatedAt: Date(timeIntervalSince1970: 0),
            appVersion: "0.19.0",
            buildNumber: "19",
            operatingSystem: "macOS test",
            architecture: "arm64",
            locale: "en_US",
            d2HelperAvailable: true,
            preferences: DiagnosticsPreferences(
                appearance: "dark",
                markdownTheme: "github",
                mermaidLightTheme: "forest",
                mermaidDarkTheme: "dark",
                previewZoom: 125,
                d2Layout: "elk",
                d2LightThemeID: 3,
                d2DarkThemeID: 201,
                d2Padding: 64,
                d2Sketch: true
            ),
            cache: D2CacheStatistics(fileCount: 4, totalBytes: 1_024)
        )

        let report = DiagnosticsReport.make(from: snapshot)

        XCTAssertTrue(report.contains("Version: 0.19.0 (19)"))
        XCTAssertTrue(report.contains("Architecture: arm64"))
        XCTAssertTrue(report.contains("Markdown theme: github"))
        XCTAssertTrue(report.contains("Layout: elk"))
        XCTAssertTrue(report.contains("Disk cache entries: 4"))
        XCTAssertTrue(report.contains("document content"))
    }

    func testCurrentReportDoesNotLeakUnknownPreferenceValuesOrCachePaths() throws {
        let suiteName = "DiagnosticsReportTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let secret = "private-document-content-and-path"
        defaults.set(secret, forKey: PreviewPreferences.appearanceKey)
        defaults.set(secret, forKey: PreviewPreferences.markdownThemeKey)
        defaults.set(secret, forKey: PreviewPreferences.d2LayoutKey)

        let cacheURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(secret, isDirectory: true)
        try FileManager.default.createDirectory(
            at: cacheURL,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: cacheURL) }

        let report = DiagnosticsReport.current(
            defaults: defaults,
            cacheDirectoryURL: cacheURL,
            generatedAt: Date(timeIntervalSince1970: 0)
        )

        XCTAssertFalse(report.contains(secret))
        XCTAssertTrue(report.contains("Appearance: system"))
        XCTAssertTrue(report.contains("Markdown theme: diagramDown"))
        XCTAssertTrue(report.contains("Layout: dagre"))
    }

    func testCacheStatisticsCountOnlyRegularSVGFiles() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data(repeating: 1, count: 12).write(
            to: directory.appendingPathComponent("first.svg")
        )
        try Data(repeating: 2, count: 20).write(
            to: directory.appendingPathComponent("second.SVG")
        )
        try Data(repeating: 3, count: 99).write(
            to: directory.appendingPathComponent("ignored.txt")
        )

        XCTAssertEqual(
            D2CacheStatistics.collect(at: directory),
            D2CacheStatistics(fileCount: 2, totalBytes: 32)
        )
    }
}

final class D2ConfigurationTests: XCTestCase {
    func testPreviewCacheDescriptorIsStable() {
        XCTAssertEqual(
            D2RenderConfiguration.preview.cacheDescriptor,
            "dagre\0" + "0\0" + "200\0" + "40\0" + "standard"
        )
    }

    func testEveryRenderingOptionChangesCacheIdentity() {
        let baseline = D2RenderConfiguration.preview
        let variants = [
            D2RenderConfiguration(
                layout: .elk,
                lightThemeID: baseline.lightThemeID,
                darkThemeID: baseline.darkThemeID,
                padding: baseline.padding,
                sketch: baseline.sketch
            ),
            D2RenderConfiguration(
                layout: baseline.layout,
                lightThemeID: 3,
                darkThemeID: baseline.darkThemeID,
                padding: baseline.padding,
                sketch: baseline.sketch
            ),
            D2RenderConfiguration(
                layout: baseline.layout,
                lightThemeID: baseline.lightThemeID,
                darkThemeID: 201,
                padding: baseline.padding,
                sketch: baseline.sketch
            ),
            D2RenderConfiguration(
                layout: baseline.layout,
                lightThemeID: baseline.lightThemeID,
                darkThemeID: baseline.darkThemeID,
                padding: 64,
                sketch: baseline.sketch
            ),
            D2RenderConfiguration(
                layout: baseline.layout,
                lightThemeID: baseline.lightThemeID,
                darkThemeID: baseline.darkThemeID,
                padding: baseline.padding,
                sketch: true
            ),
        ]

        for variant in variants {
            XCTAssertNotEqual(variant.cacheDescriptor, baseline.cacheDescriptor)
        }
    }

    func testD2ErrorsHaveActionableMessages() {
        let errors: [D2RenderError] = [
            .executableMissing,
            .inputTooLarge,
            .timedOut,
            .cancelled,
            .processLaunchFailed("launch failed"),
            .processFailed(exitCode: 5, message: ""),
            .outputMissing,
            .outputTooLarge,
            .invalidSVG,
        ]

        for error in errors {
            XCTAssertFalse((error.errorDescription ?? "").isEmpty)
        }
    }
}

final class D2FormattingTests: XCTestCase {
    func testOnlyD2FencesUseTheOfficialFormatterCommand() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let formatterURL = directory.appendingPathComponent("d2")
        let formatter = """
        #!/bin/sh
        [ "$1" = "fmt" ] || exit 9
        printf 'formatted -> d2\n' > "$2"
        """
        try formatter.write(to: formatterURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: formatterURL.path
        )

        let service = D2RenderService(
            executableURL: formatterURL,
            cacheDirectoryURL: directory
        )
        let markdown = """
        ```D2
        a:     b
        ```

        ```mermaid
        graph TD
        A-->B
        ```
        """
        let result = try await service.formatFencedBlocks(in: markdown)

        XCTAssertTrue(result.contains("formatted -> d2"))
        XCTAssertTrue(result.contains("graph TD\nA-->B"))
    }

    func testMarkdownWithoutD2DoesNotRequireAFormatterExecutable() async throws {
        let service = D2RenderService(executableURL: URL(fileURLWithPath: "/missing"))
        let markdown = "```json\n{\"ok\":true}\n```"
        let result = try await service.formatFencedBlocks(in: markdown)
        XCTAssertEqual(result, markdown)
    }
}

final class PDFExportServiceTests: XCTestCase {
    func testPaginationProducesMultipleNonEmptyA4Pages() throws {
        var sourceBounds = CGRect(x: 0, y: 0, width: 400, height: 1_600)
        let sourceData = NSMutableData()
        let consumer = try XCTUnwrap(CGDataConsumer(data: sourceData as CFMutableData))
        let context = try XCTUnwrap(CGContext(consumer: consumer, mediaBox: &sourceBounds, nil))
        context.beginPDFPage(nil)
        context.setFillColor(CGColor(red: 0.2, green: 0.3, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 20, y: 20, width: 360, height: 1_560))
        context.endPDFPage()
        context.closePDF()

        let result = try PDFExportService.paginate(sourceData as Data)
        try PDFExportService.validate(result)
        let provider = try XCTUnwrap(CGDataProvider(data: result as CFData))
        let document = try XCTUnwrap(CGPDFDocument(provider))

        XCTAssertGreaterThan(document.numberOfPages, 1)
        XCTAssertGreaterThan(result.count, 1_000)
        XCTAssertEqual(document.page(at: 1)?.getBoxRect(.mediaBox).width ?? 0, 595.28, accuracy: 0.1)
    }

    func testInvalidPDFIsRejected() {
        XCTAssertThrowsError(try PDFExportService.validate(Data("not a pdf".utf8)))
    }
}

final class ScrollSyncStateTests: XCTestCase {
    func testInitialPositionIsAtDocumentStart() {
        XCTAssertEqual(ScrollSyncPosition.initial.sourceLine, 1)
        XCTAssertEqual(ScrollSyncPosition.initial.progress, 0)
        XCTAssertEqual(ScrollSyncPosition.initial.generation, 0)
    }

    func testInitialTargetDoesNotAnimateOrUseFallback() {
        XCTAssertEqual(ScrollSyncTarget.initial.sourceLine, 1)
        XCTAssertEqual(ScrollSyncTarget.initial.progress, 0)
        XCTAssertFalse(ScrollSyncTarget.initial.usesProgressFallback)
        XCTAssertFalse(ScrollSyncTarget.initial.animated)
        XCTAssertEqual(ScrollSyncTarget.initial.generation, 0)
    }
}
