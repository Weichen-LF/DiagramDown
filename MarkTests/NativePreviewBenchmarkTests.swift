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

        print(
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
        print(
            "BENCHMARK \(name) bytes=\(bytes) samples=\(samples.count) " +
                "mean_ms=\(milliseconds(mean)) " +
                "p95_ms=\(milliseconds(sorted[p95Index]))"
        )
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
