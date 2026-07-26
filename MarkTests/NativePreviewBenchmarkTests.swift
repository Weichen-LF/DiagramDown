//
//  NativePreviewBenchmarkTests.swift
//  MarkTests
//

import XCTest
@testable import DiagramDown

final class NativePreviewBenchmarkTests: XCTestCase {
    func testParserSizeScenarios() async throws {
        for scenario in [
            ("small", 20 * 1_024, 8),
            ("medium", 200 * 1_024, 8),
            ("medium-large", 500 * 1_024, 4),
            ("large", 2 * 1_024 * 1_024, 1),
        ] {
            let source = makeMarkdown(minimumUTF8Bytes: scenario.1)
            let parser = MarkdownParserService()
            var previous: PreviewDocument?
            var samples: [Double] = []

            for revision in 1...scenario.2 {
                let start = ContinuousClock.now
                let document = try await parser.parse(
                    source: source,
                    revision: UInt64(revision),
                    previous: previous
                )
                samples.append(seconds(since: start))
                previous = document
                XCTAssertFalse(document.blocks.isEmpty)
            }

            printMetric(
                name: "parser-\(scenario.0)",
                bytes: source.utf8.count,
                samples: samples
            )
        }
    }

    func testSingleCodeBlockAndHighBlockCountScenarios() async throws {
        for (name, source) in [
            ("single-code-block-2mib", makeSingleCodeBlock(minimumUTF8Bytes: 2 * 1_024 * 1_024)),
            ("structural-2mib", makeStructuralMarkdown(minimumUTF8Bytes: 2 * 1_024 * 1_024)),
        ] {
            let parser = MarkdownParserService()
            let start = ContinuousClock.now
            let first = try await parser.parse(
                source: source,
                revision: 1,
                previous: nil
            )
            let second = try await parser.parse(
                source: source,
                revision: 2,
                previous: first
            )
            let elapsed = seconds(since: start)

            XCTAssertEqual(first.blocks.count, second.blocks.count)
            XCTAssertEqual(first.blocks.map(\.id), second.blocks.map(\.id))
            emitMetric(
                "BENCHMARK parser-\(name) bytes=\(source.utf8.count) " +
                    "blocks=\(second.blocks.count) total_ms=\(milliseconds(elapsed))"
            )
        }
    }

    func testDiagramHeavySourceProcessing() async throws {
        let source = makeDiagramHeavyMarkdown()
        let parser = MarkdownParserService()
        var previous: PreviewDocument?
        var samples: [Double] = []

        for revision in 1...8 {
            let start = ContinuousClock.now
            previous = try await parser.parse(
                source: source,
                revision: UInt64(revision),
                previous: previous
            )
            samples.append(seconds(since: start))
        }

        XCTAssertEqual(
            previous?.blocks.filter {
                if case .mermaid = $0.content { return true }
                return false
            }.count,
            20
        )
        XCTAssertEqual(
            previous?.blocks.filter {
                if case .d2 = $0.content { return true }
                return false
            }.count,
            20
        )
        printMetric(
            name: "parser-diagram-heavy",
            bytes: source.utf8.count,
            samples: samples
        )
    }

    @MainActor
    func testRapidEditsApplyOnlyLatestRevision() async {
        let model = NativePreviewModel()
        var tasks: [Task<Void, Never>] = []
        let start = ContinuousClock.now

        for revision in 1...10 {
            let source = "# Revision \(revision)\n"
            tasks.append(Task { @MainActor in
                await model.update(source: source)
            })
            try? await Task.sleep(for: .milliseconds(100))
        }
        for task in tasks {
            await task.value
        }

        guard case .heading(_, let inline) = model.document.blocks.first?.content else {
            return XCTFail("Expected the latest heading")
        }
        XCTAssertEqual(inline.plainText, "Revision 10")
        emitMetric(
            "BENCHMARK rapid-edits updates=10 rate_hz=10 " +
                "total_ms=\(milliseconds(seconds(since: start)))"
        )
    }

    func testTenDocumentSwitchingScenario() async throws {
        let parser = MarkdownParserService()
        let sources = (0..<10).map {
            makeMarkdown(minimumUTF8Bytes: 200 * 1_024)
                + "\nTab \($0)\n"
        }
        let start = ContinuousClock.now
        var blockCount = 0

        for (index, source) in sources.enumerated() {
            let document = try await parser.parse(
                source: source,
                revision: UInt64(index + 1),
                previous: nil
            )
            blockCount += document.blocks.count
        }

        emitMetric(
            "BENCHMARK tab-switching documents=10 blocks=\(blockCount) " +
                "total_ms=\(milliseconds(seconds(since: start)))"
        )
    }

    func testCodeHeavyColdAndWarmHighlighting() async {
        let sources = (0..<50).map { index in
            """
            struct Fixture\(index) {
                let value: Int = \(index)
                func render() -> String { "fixture-\\(value)" }
            }
            """
        }
        let theme = CodeTheme.resolved(
            markdownTheme: .diagramDown,
            appearance: .light
        )
        let highlighter = TreeSitterCodeHighlighter()

        let coldStart = ContinuousClock.now
        for source in sources {
            let result = await highlighter.highlight(
                source: source,
                language: .swift,
                theme: theme
            )
            XCTAssertGreaterThan(result.runs.count, 1)
        }
        let coldSeconds = seconds(since: coldStart)

        let warmStart = ContinuousClock.now
        for source in sources {
            _ = await highlighter.highlight(
                source: source,
                language: .swift,
                theme: theme
            )
        }
        let warmSeconds = seconds(since: warmStart)

        emitMetric(
            "BENCHMARK highlighter-code-heavy blocks=50 " +
                "cold_ms=\(milliseconds(coldSeconds)) " +
                "warm_ms=\(milliseconds(warmSeconds))"
        )
    }

    private func makeMarkdown(minimumUTF8Bytes: Int) -> String {
        let section = """
        ## Native preview section

        Paragraph text with **strong**, *emphasis*, [link](https://example.com),
        `inline code`, CJK 内容, and enough prose to exercise source ranges.

        - [x] parsed with swift-markdown
        - [ ] reconciled with stable block identifiers

        | Feature | State |
        | --- | --- |
        | Parser | Native |
        | Preview | SwiftUI |

        ```swift
        struct PreviewFixture {
            let value: Int = 42
        }
        ```

        """
        let structuralFixture = String(repeating: section, count: 20)
        let remainingBytes = max(
            0,
            minimumUTF8Bytes - structuralFixture.utf8.count
        )
        let proseLine = "Native preview benchmark prose with CJK 内容. "
        let proseRepetitions = max(
            1,
            Int(
                (Double(remainingBytes) / Double(proseLine.utf8.count))
                    .rounded(.up)
            )
        )
        return structuralFixture
            + "\n"
            + String(repeating: proseLine, count: proseRepetitions)
    }

    private func makeSingleCodeBlock(minimumUTF8Bytes: Int) -> String {
        let prefix = "```text\n"
        let suffix = "```\n"
        let line = "single code block payload with CJK 内容\n"
        let remaining = max(
            0,
            minimumUTF8Bytes - prefix.utf8.count - suffix.utf8.count
        )
        let repetitions = max(
            1,
            Int((Double(remaining) / Double(line.utf8.count)).rounded(.up))
        )
        return prefix + String(repeating: line, count: repetitions) + suffix
    }

    private func makeStructuralMarkdown(minimumUTF8Bytes: Int) -> String {
        let section = """
        ## Repeated structural block

        Paragraph with **strong text**, [link](https://example.com), and CJK 内容.

        """
        let repetitions = max(
            1,
            Int(
                (Double(minimumUTF8Bytes) / Double(section.utf8.count))
                    .rounded(.up)
            )
        )
        return String(repeating: section, count: repetitions)
    }

    private func makeDiagramHeavyMarkdown() -> String {
        (0..<20).map { index in
            """
            ```mermaid
            flowchart LR
              Mermaid\(index) --> Preview\(index)
            ```

            ```d2
            D2\(index) -> Preview\(index)
            ```
            """
        }.joined(separator: "\n\n")
    }

    private func printMetric(
        name: String,
        bytes: Int,
        samples: [Double]
    ) {
        let sorted = samples.sorted()
        let p95Index = min(
            sorted.count - 1,
            max(0, Int((Double(sorted.count) * 0.95).rounded(.up)) - 1)
        )
        let mean = samples.reduce(0, +) / Double(samples.count)
        emitMetric(
            "BENCHMARK \(name) bytes=\(bytes) samples=\(samples.count) " +
                "mean_ms=\(milliseconds(mean)) " +
                "p95_ms=\(milliseconds(sorted[p95Index]))"
        )
    }

    private func emitMetric(_ message: String) {
        let data = Data("\(message)\n".utf8)
        FileHandle.standardError.write(data)

        let path = "/tmp/DiagramDownNativePreviewBenchmarkMetrics.log"
        let url = URL(fileURLWithPath: path)
        if !FileManager.default.fileExists(atPath: path) {
            FileManager.default.createFile(atPath: path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: url) else {
            return
        }
        defer { try? handle.close() }
        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            XCTFail("Could not write benchmark metrics: \(error)")
        }
    }

    private func seconds(
        since start: ContinuousClock.Instant
    ) -> Double {
        let components = start.duration(to: .now).components
        return Double(components.seconds)
            + Double(components.attoseconds) / 1_000_000_000_000_000_000
    }

    private func milliseconds(_ seconds: Double) -> String {
        String(format: "%.2f", seconds * 1_000)
    }
}
