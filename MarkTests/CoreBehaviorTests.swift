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
