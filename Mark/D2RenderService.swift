//
//  D2RenderService.swift
//  DiagramDown
//

import Foundation

nonisolated struct D2RenderConfiguration: Hashable, Sendable {
    nonisolated enum Layout: String, CaseIterable, Hashable, Identifiable, Sendable {
        case dagre
        case elk

        nonisolated var id: String { rawValue }

        nonisolated var displayName: String {
            switch self {
            case .dagre: "Dagre"
            case .elk: "ELK"
            }
        }
    }

    let layout: Layout
    let lightThemeID: Int
    let darkThemeID: Int
    let padding: Int
    let sketch: Bool

    nonisolated static let preview = D2RenderConfiguration(
        layout: .dagre,
        lightThemeID: 0,
        darkThemeID: 200,
        padding: 40,
        sketch: false
    )

    nonisolated var cacheDescriptor: String {
        [
            layout.rawValue,
            String(lightThemeID),
            String(darkThemeID),
            String(padding),
            sketch ? "sketch" : "standard",
        ].joined(separator: "\0")
    }
}

nonisolated struct D2RenderResult: Sendable {
    let svg: String
    let cacheHit: Bool
}

nonisolated enum D2RenderError: LocalizedError, Sendable {
    case executableMissing
    case inputTooLarge
    case timedOut
    case cancelled
    case processLaunchFailed(String)
    case processFailed(exitCode: Int32, message: String)
    case outputMissing
    case outputTooLarge
    case invalidSVG

    var errorDescription: String? {
        switch self {
        case .executableMissing:
            "D2 CLI is not installed or is not executable."
        case .inputTooLarge:
            "The D2 source exceeds the 256 KB preview limit."
        case .timedOut:
            "D2 rendering exceeded the 6 second time limit."
        case .cancelled:
            "D2 rendering was cancelled."
        case .processLaunchFailed(let message):
            "D2 CLI could not be started: \(message)"
        case .processFailed(let exitCode, let message):
            message.isEmpty
                ? "D2 rendering failed with exit code \(exitCode)."
                : message
        case .outputMissing:
            "D2 CLI finished without producing an SVG."
        case .outputTooLarge:
            "The generated D2 SVG exceeds the 8 MB preview limit."
        case .invalidSVG:
            "D2 CLI produced an invalid SVG document."
        }
    }
}

actor D2RenderService {
    static let shared = D2RenderService()
    nonisolated static let rendererVersion = "local-d2-v1"

    private static let maximumInputBytes = 256 * 1_024
    private static let maximumOutputBytes = 8 * 1_024 * 1_024

    private let overrideExecutableURL: URL?
    private let runner: ExternalProcessRunner

    init(
        executableURL: URL? = nil,
        cacheDirectoryURL _: URL? = nil,
        runner: ExternalProcessRunner = .shared
    ) {
        overrideExecutableURL = executableURL
        self.runner = runner
    }

    func formatFencedBlocks(in markdown: String) async throws -> String {
        let expression = try NSRegularExpression(
            pattern: #"(?ms)^ {0,3}(`{3,}|~{3,})[ \t]*d2(?:[ \t][^\r\n]*)?\r?\n(.*?)^ {0,3}\1[ \t]*(?=\r?\n|$)"#,
            options: [.caseInsensitive]
        )
        let source = markdown as NSString
        let matches = expression.matches(
            in: markdown,
            range: NSRange(location: 0, length: source.length)
        )
        guard !matches.isEmpty else {
            return markdown
        }

        var replacements: [(range: NSRange, source: String)] = []
        do {
            for match in matches {
                let contentRange = match.range(at: 2)
                replacements.append((
                    contentRange,
                    try await formatSource(source.substring(with: contentRange))
                ))
            }
        } catch is DiagramToolResolutionError {
            return markdown
        } catch D2RenderError.executableMissing {
            return markdown
        }

        let result = NSMutableString(string: markdown)
        for replacement in replacements.reversed() {
            result.replaceCharacters(in: replacement.range, with: replacement.source)
        }
        return result as String
    }

    func render(
        source: String,
        configuration: D2RenderConfiguration = .preview,
        appearance: String = "light",
        tool: InstalledDiagramTool? = nil
    ) async throws -> D2RenderResult {
        try Task.checkCancellation()
        guard source.utf8.count <= Self.maximumInputBytes else {
            throw D2RenderError.inputTooLarge
        }

        let executableURL = try await resolveExecutable(tool: tool)
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let inputURL = directory.appendingPathComponent("input.d2")
        let outputURL = directory.appendingPathComponent("output.svg")
        try source.write(to: inputURL, atomically: true, encoding: .utf8)

        let themeID = appearance == "dark"
            ? configuration.darkThemeID
            : configuration.lightThemeID
        var arguments = [
            "--layout", configuration.layout.rawValue,
            "--theme", String(themeID),
            "--pad", String(configuration.padding),
            "--timeout", "5",
            "--no-xml-tag",
            "--salt", UUID().uuidString,
        ]
        if configuration.sketch {
            arguments.append("--sketch")
        }
        arguments.append(contentsOf: [inputURL.path, outputURL.path])

        let result = try await run(
            executableURL: executableURL,
            arguments: arguments,
            directory: directory
        )
        guard result.exitCode == 0 else {
            let diagnostic = result.standardError.isEmpty
                ? result.standardOutput
                : result.standardError
            throw D2RenderError.processFailed(
                exitCode: result.exitCode,
                message: cleanedDiagnostic(diagnostic, temporaryDirectory: directory)
            )
        }

        return D2RenderResult(svg: try loadSVG(at: outputURL), cacheHit: false)
    }

    private func formatSource(_ source: String) async throws -> String {
        try Task.checkCancellation()
        guard source.utf8.count <= Self.maximumInputBytes else {
            throw D2RenderError.inputTooLarge
        }
        let executableURL = try await resolveExecutable(tool: nil)
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let inputURL = directory.appendingPathComponent("input.d2")
        try source.write(to: inputURL, atomically: true, encoding: .utf8)

        let result = try await run(
            executableURL: executableURL,
            arguments: ["fmt", inputURL.path],
            directory: directory
        )
        guard result.exitCode == 0 else {
            let diagnostic = result.standardError.isEmpty
                ? result.standardOutput
                : result.standardError
            throw D2RenderError.processFailed(
                exitCode: result.exitCode,
                message: cleanedDiagnostic(diagnostic, temporaryDirectory: directory)
            )
        }
        return try String(contentsOf: inputURL, encoding: .utf8)
    }

    private func resolveExecutable(tool: InstalledDiagramTool?) async throws -> URL {
        if let tool {
            return tool.executableURL
        }
        if let overrideExecutableURL {
            guard FileManager.default.isExecutableFile(atPath: overrideExecutableURL.path) else {
                throw D2RenderError.executableMissing
            }
            return overrideExecutableURL
        }
        return try await DiagramToolRegistry.shared
            .installedTool(for: .d2)
            .executableURL
    }

    private func run(
        executableURL: URL,
        arguments: [String],
        directory: URL
    ) async throws -> ExternalProcessResult {
        do {
            return try await runner.run(
                executableURL: executableURL,
                arguments: arguments,
                currentDirectoryURL: directory,
                environment: ExternalProcessRunner.defaultEnvironment(
                    temporaryDirectory: directory
                ),
                timeout: .seconds(6)
            )
        } catch ExternalProcessRunnerError.timedOut {
            throw D2RenderError.timedOut
        } catch ExternalProcessRunnerError.cancelled {
            throw D2RenderError.cancelled
        } catch {
            throw D2RenderError.processLaunchFailed(
                cleanedDiagnostic(error.localizedDescription, temporaryDirectory: directory)
            )
        }
    }

    private func makeTemporaryDirectory() throws -> URL {
        let baseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                Bundle.main.bundleIdentifier ?? "me.walt.diagramdown",
                isDirectory: true
            )
            .appendingPathComponent("d2", isDirectory: true)
        try FileManager.default.createDirectory(
            at: baseURL,
            withIntermediateDirectories: true
        )
        let directory = baseURL.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: false
        )
        return directory
    }

    private func loadSVG(at outputURL: URL) throws -> String {
        guard FileManager.default.fileExists(atPath: outputURL.path) else {
            throw D2RenderError.outputMissing
        }
        let attributes = try FileManager.default.attributesOfItem(atPath: outputURL.path)
        let size = (attributes[.size] as? NSNumber)?.intValue ?? 0
        guard size <= Self.maximumOutputBytes else {
            throw D2RenderError.outputTooLarge
        }
        let svg = try String(contentsOf: outputURL, encoding: .utf8)
        guard svg.range(of: "<svg", options: .caseInsensitive) != nil,
              svg.range(of: "</svg>", options: .caseInsensitive) != nil else {
            throw D2RenderError.invalidSVG
        }
        return svg
    }

    private func cleanedDiagnostic(
        _ diagnostic: String,
        temporaryDirectory: URL
    ) -> String {
        DiagramToolRegistry.cleanedDiagnostic(
            diagnostic.replacingOccurrences(
                of: temporaryDirectory.path,
                with: "<temporary-directory>"
            )
        )
    }
}
