//
//  MermaidRenderService.swift
//  DiagramDown
//

import Foundation

nonisolated enum MermaidRenderError: LocalizedError, Sendable {
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
        case .inputTooLarge:
            "The Mermaid source exceeds the 256 KB preview limit."
        case .timedOut:
            "Mermaid rendering exceeded the 15 second time limit."
        case .cancelled:
            "Mermaid rendering was cancelled."
        case .processLaunchFailed(let message):
            "Mermaid CLI could not be started: \(message)"
        case .processFailed(let exitCode, let message):
            message.isEmpty
                ? "Mermaid rendering failed with exit code \(exitCode)."
                : message
        case .outputMissing:
            "Mermaid CLI finished without producing an output file."
        case .outputTooLarge:
            "The generated Mermaid output exceeds the 16 MB preview limit."
        case .invalidSVG:
            "Mermaid CLI produced an invalid SVG document."
        }
    }
}

actor MermaidRenderService {
    static let shared = MermaidRenderService()
    nonisolated static let mmdcRendererVersion = "local-mmdc-png-v2"
    nonisolated static let mmdrRendererVersion = "local-mmdr-svg-v3"
    nonisolated static let pngScale = 2

    /// Kept for call sites that still refer to the historical mmdc cache token.
    nonisolated static var rendererVersion: String { mmdcRendererVersion }

    private static let maximumInputBytes = 256 * 1_024
    private static let maximumOutputBytes = 16 * 1_024 * 1_024
    private let runner: ExternalProcessRunner

    init(runner: ExternalProcessRunner = .shared) {
        self.runner = runner
    }

    func renderPNG(
        source: String,
        theme: MermaidPreviewTheme,
        appearance _: String,
        tool: InstalledDiagramTool? = nil
    ) async throws -> Data {
        try await render(
            source: source,
            theme: theme,
            engine: .mmdc,
            outputExtension: "png",
            tool: tool
        )
    }

    func renderSVG(
        source: String,
        theme: MermaidPreviewTheme,
        engine: MermaidRendererEngine = .mmdc,
        tool: InstalledDiagramTool? = nil
    ) async throws -> String {
        let data = try await render(
            source: source,
            theme: theme,
            engine: engine,
            outputExtension: "svg",
            tool: tool
        )
        guard let svg = String(data: data, encoding: .utf8),
              svg.range(of: "<svg", options: .caseInsensitive) != nil,
              svg.range(of: "</svg>", options: .caseInsensitive) != nil else {
            throw MermaidRenderError.invalidSVG
        }
        return svg
    }

    private func render(
        source: String,
        theme: MermaidPreviewTheme,
        engine: MermaidRendererEngine,
        outputExtension: String,
        tool: InstalledDiagramTool?
    ) async throws -> Data {
        try Task.checkCancellation()
        guard source.utf8.count <= Self.maximumInputBytes else {
            throw MermaidRenderError.inputTooLarge
        }

        let installedTool: InstalledDiagramTool
        if let tool {
            installedTool = tool
        } else {
            installedTool = try await DiagramToolRegistry.shared.installedTool(
                for: engine.toolKind
            )
        }

        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let inputURL = directory.appendingPathComponent("input.mmd")
        let outputURL = directory.appendingPathComponent("output.\(outputExtension)")
        try source.write(to: inputURL, atomically: true, encoding: .utf8)

        let arguments: [String]
        switch engine {
        case .mmdc:
            var mmdcArguments = [
                "-i", inputURL.path,
                "-o", outputURL.path,
                "-t", theme.rawValue,
                "-b", "transparent",
            ]
            if outputExtension == "png" {
                mmdcArguments.append(contentsOf: ["-s", "\(Self.pngScale)"])
            }
            arguments = mmdcArguments
        case .mmdr:
            arguments = [
                "-i", inputURL.path,
                "-o", outputURL.path,
                "-e", outputExtension,
            ]
        }

        let result: ExternalProcessResult
        do {
            result = try await runner.run(
                executableURL: installedTool.executableURL,
                arguments: arguments,
                currentDirectoryURL: directory,
                environment: ExternalProcessRunner.defaultEnvironment(
                    temporaryDirectory: directory
                ),
                timeout: .seconds(15)
            )
        } catch ExternalProcessRunnerError.timedOut {
            throw MermaidRenderError.timedOut
        } catch ExternalProcessRunnerError.cancelled {
            throw MermaidRenderError.cancelled
        } catch {
            throw MermaidRenderError.processLaunchFailed(
                cleanedDiagnostic(error.localizedDescription, temporaryDirectory: directory)
            )
        }

        guard result.exitCode == 0 else {
            let diagnostic = result.standardError.isEmpty
                ? result.standardOutput
                : result.standardError
            throw MermaidRenderError.processFailed(
                exitCode: result.exitCode,
                message: cleanedDiagnostic(diagnostic, temporaryDirectory: directory)
            )
        }

        return try loadOutput(at: outputURL)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let baseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                Bundle.main.bundleIdentifier ?? "me.walt.diagramdown",
                isDirectory: true
            )
            .appendingPathComponent("mermaid", isDirectory: true)
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

    private func loadOutput(at outputURL: URL) throws -> Data {
        guard FileManager.default.fileExists(atPath: outputURL.path) else {
            throw MermaidRenderError.outputMissing
        }
        let attributes = try FileManager.default.attributesOfItem(atPath: outputURL.path)
        let size = (attributes[.size] as? NSNumber)?.intValue ?? 0
        guard size <= Self.maximumOutputBytes else {
            throw MermaidRenderError.outputTooLarge
        }
        return try Data(contentsOf: outputURL, options: [.mappedIfSafe])
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
