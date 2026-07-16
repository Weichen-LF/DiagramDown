//
//  D2RenderService.swift
//  DiagramDown
//

import Darwin
import Foundation

struct D2RenderConfiguration: Sendable {
    enum Layout: String, Sendable {
        case dagre
        case elk
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
}

enum D2RenderError: LocalizedError, Sendable {
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
            "The bundled D2 renderer is missing or is not executable."
        case .inputTooLarge:
            "The D2 source exceeds the 256 KB preview limit."
        case .timedOut:
            "D2 rendering exceeded the 6 second time limit."
        case .cancelled:
            "D2 rendering was cancelled."
        case .processLaunchFailed(let message):
            "D2 could not be started: \(message)"
        case .processFailed(let exitCode, let message):
            message.isEmpty
                ? "D2 rendering failed with exit code \(exitCode)."
                : message
        case .outputMissing:
            "D2 finished without producing an SVG."
        case .outputTooLarge:
            "The generated D2 SVG exceeds the 8 MB preview limit."
        case .invalidSVG:
            "D2 produced an invalid SVG document."
        }
    }
}

actor D2RenderService {
    static let shared = D2RenderService()

    private static let maximumInputBytes = 256 * 1_024
    private static let maximumOutputBytes = 8 * 1_024 * 1_024
    private static let maximumDiagnosticBytes = 256 * 1_024

    private let overrideExecutableURL: URL?
    private var runningProcesses: [UUID: Process] = [:]
    private var cancelledJobs: Set<UUID> = []
    private var timedOutJobs: Set<UUID> = []

    init(executableURL: URL? = nil) {
        overrideExecutableURL = executableURL
    }

    func render(
        source: String,
        configuration: D2RenderConfiguration = .preview
    ) async throws -> String {
        try Task.checkCancellation()

        guard source.utf8.count <= Self.maximumInputBytes else {
            throw D2RenderError.inputTooLarge
        }

        guard let executableURL = overrideExecutableURL ?? Self.executableURL,
              FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            throw D2RenderError.executableMissing
        }

        let jobID = UUID()
        let directory = try makeTemporaryDirectory(jobID: jobID)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let inputURL = directory.appendingPathComponent("input.d2", isDirectory: false)
        let outputURL = directory.appendingPathComponent("output.svg", isDirectory: false)
        try source.write(to: inputURL, atomically: true, encoding: .utf8)

        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let stdoutCollector = PipeCollector(
            fileHandle: stdoutPipe.fileHandleForReading,
            maximumBytes: Self.maximumDiagnosticBytes
        )
        let stderrCollector = PipeCollector(
            fileHandle: stderrPipe.fileHandleForReading,
            maximumBytes: Self.maximumDiagnosticBytes
        )

        process.executableURL = executableURL
        process.currentDirectoryURL = directory
        process.arguments = arguments(
            jobID: jobID,
            inputURL: inputURL,
            outputURL: outputURL,
            configuration: configuration
        )
        process.environment = restrictedEnvironment(temporaryDirectory: directory)
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        runningProcesses[jobID] = process

        let timeoutTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(6))
            } catch {
                return
            }
            await self?.timeOut(jobID: jobID)
        }

        defer {
            timeoutTask.cancel()
            runningProcesses.removeValue(forKey: jobID)
            cancelledJobs.remove(jobID)
            timedOutJobs.remove(jobID)
        }

        let exitCode: Int32
        do {
            exitCode = try await withTaskCancellationHandler {
                do {
                    try Task.checkCancellation()
                    return try await runAndWait(process)
                } catch is CancellationError {
                    throw D2RenderError.cancelled
                } catch let error as D2RenderError {
                    throw error
                } catch {
                    throw D2RenderError.processLaunchFailed(error.localizedDescription)
                }
            } onCancel: {
                Task {
                    await self.cancel(jobID: jobID)
                }
            }
        } catch {
            stdoutPipe.fileHandleForWriting.closeFile()
            stderrPipe.fileHandleForWriting.closeFile()
            _ = stdoutCollector.finish()
            _ = stderrCollector.finish()
            throw error
        }

        let stdout = diagnosticString(from: stdoutCollector.finish())
        let stderr = diagnosticString(from: stderrCollector.finish())

        if timedOutJobs.contains(jobID) {
            throw D2RenderError.timedOut
        }

        if cancelledJobs.contains(jobID) || Task.isCancelled {
            throw D2RenderError.cancelled
        }

        guard exitCode == 0 else {
            let message = stderr.isEmpty ? stdout : stderr
            throw D2RenderError.processFailed(exitCode: exitCode, message: message)
        }

        guard FileManager.default.fileExists(atPath: outputURL.path) else {
            throw D2RenderError.outputMissing
        }

        let attributes = try FileManager.default.attributesOfItem(atPath: outputURL.path)
        let outputSize = (attributes[.size] as? NSNumber)?.intValue ?? 0
        guard outputSize <= Self.maximumOutputBytes else {
            throw D2RenderError.outputTooLarge
        }

        let svg = try String(contentsOf: outputURL, encoding: .utf8)
        guard svg.range(of: "<svg", options: .caseInsensitive) != nil,
              svg.range(of: "</svg>", options: .caseInsensitive) != nil else {
            throw D2RenderError.invalidSVG
        }

        return svg
    }

    private static var executableURL: URL? {
        Bundle.main.url(forAuxiliaryExecutable: "d2")
            ?? Bundle.main.bundleURL
                .appendingPathComponent("Contents", isDirectory: true)
                .appendingPathComponent("Helpers", isDirectory: true)
                .appendingPathComponent("d2", isDirectory: false)
    }

    private func makeTemporaryDirectory(jobID: UUID) throws -> URL {
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

        let directory = baseURL.appendingPathComponent(jobID.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        return directory
    }

    private func arguments(
        jobID: UUID,
        inputURL: URL,
        outputURL: URL,
        configuration: D2RenderConfiguration
    ) -> [String] {
        var result = [
            "--layout", configuration.layout.rawValue,
            "--theme", String(configuration.lightThemeID),
            "--dark-theme", String(configuration.darkThemeID),
            "--pad", String(configuration.padding),
            "--timeout", "5",
            "--no-xml-tag",
            "--salt", jobID.uuidString,
        ]

        if configuration.sketch {
            result.append("--sketch")
        }

        result.append(inputURL.path)
        result.append(outputURL.path)
        return result
    }

    private func restrictedEnvironment(temporaryDirectory: URL) -> [String: String] {
        [
            "ALL_PROXY": "http://127.0.0.1:9",
            "HOME": temporaryDirectory.path,
            "HTTP_PROXY": "http://127.0.0.1:9",
            "HTTPS_PROXY": "http://127.0.0.1:9",
            "LANG": "en_US.UTF-8",
            "NO_PROXY": "",
            "PATH": "/usr/bin:/bin",
            "TMPDIR": temporaryDirectory.path,
        ]
    }

    private func runAndWait(_ process: Process) async throws -> Int32 {
        try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { finishedProcess in
                continuation.resume(returning: finishedProcess.terminationStatus)
            }

            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(throwing: error)
            }
        }
    }

    private func cancel(jobID: UUID) {
        cancelledJobs.insert(jobID)
        terminate(jobID: jobID)
    }

    private func timeOut(jobID: UUID) {
        guard runningProcesses[jobID]?.isRunning == true else {
            return
        }

        timedOutJobs.insert(jobID)
        terminate(jobID: jobID)
    }

    private func terminate(jobID: UUID) {
        guard let process = runningProcesses[jobID], process.isRunning else {
            return
        }

        process.terminate()
        Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(500))
            } catch {
                return
            }
            await self?.forceTerminate(jobID: jobID)
        }
    }

    private func forceTerminate(jobID: UUID) {
        guard let process = runningProcesses[jobID], process.isRunning else {
            return
        }

        kill(process.processIdentifier, SIGKILL)
    }

    private func diagnosticString(from data: Data) -> String {
        String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

nonisolated private final class PipeCollector: @unchecked Sendable {
    private let fileHandle: FileHandle
    private let maximumBytes: Int
    private let lock = NSLock()
    private var collectedData = Data()

    init(fileHandle: FileHandle, maximumBytes: Int) {
        self.fileHandle = fileHandle
        self.maximumBytes = maximumBytes
        fileHandle.readabilityHandler = { [weak self] readableHandle in
            self?.consume(readableHandle.availableData)
        }
    }

    func finish() -> Data {
        fileHandle.readabilityHandler = nil
        if let remainder = try? fileHandle.readToEnd() {
            consume(remainder)
        }

        lock.lock()
        defer { lock.unlock() }
        return collectedData
    }

    private func consume(_ data: Data) {
        guard !data.isEmpty else {
            return
        }

        lock.lock()
        defer { lock.unlock() }

        let remaining = maximumBytes - collectedData.count
        guard remaining > 0 else {
            return
        }
        collectedData.append(data.prefix(remaining))
    }
}
