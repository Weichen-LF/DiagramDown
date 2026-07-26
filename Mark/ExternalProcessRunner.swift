//
//  ExternalProcessRunner.swift
//  DiagramDown
//

import Darwin
import Foundation

nonisolated struct ExternalProcessResult: Sendable {
    let exitCode: Int32
    let standardOutput: String
    let standardError: String
}

nonisolated enum ExternalProcessRunnerError: LocalizedError, Sendable {
    case cancelled
    case timedOut
    case launchFailed(String)

    var errorDescription: String? {
        switch self {
        case .cancelled:
            "The command was cancelled."
        case .timedOut:
            "The command exceeded its time limit."
        case .launchFailed(let message):
            "The command could not be started: \(message)"
        }
    }
}

actor ExternalProcessRunner {
    static let shared = ExternalProcessRunner()

    private struct RunningCommand {
        let process: Process
        let processGroupID: pid_t
    }

    private var runningCommands: [UUID: RunningCommand] = [:]
    private var cancelledCommands: Set<UUID> = []
    private var timedOutCommands: Set<UUID> = []

    func run(
        executableURL: URL,
        arguments: [String],
        currentDirectoryURL: URL? = nil,
        environment: [String: String]? = nil,
        timeout: Duration,
        maximumOutputBytes: Int = 256 * 1_024
    ) async throws -> ExternalProcessResult {
        try Task.checkCancellation()

        let commandID = UUID()
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let stdoutCollector = BoundedPipeCollector(
            fileHandle: stdoutPipe.fileHandleForReading,
            maximumBytes: maximumOutputBytes
        )
        let stderrCollector = BoundedPipeCollector(
            fileHandle: stderrPipe.fileHandleForReading,
            maximumBytes: maximumOutputBytes
        )

        process.executableURL = executableURL.standardizedFileURL
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectoryURL
        process.environment = environment ?? Self.defaultEnvironment(
            temporaryDirectory: currentDirectoryURL
        )
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let timeoutTask = Task { [weak self] in
            do {
                try await Task.sleep(for: timeout)
            } catch {
                return
            }
            await self?.timeOut(commandID)
        }

        defer {
            timeoutTask.cancel()
            runningCommands.removeValue(forKey: commandID)
            cancelledCommands.remove(commandID)
            timedOutCommands.remove(commandID)
        }

        let exitCode: Int32
        do {
            exitCode = try await withTaskCancellationHandler {
                try Task.checkCancellation()
                return try await launchAndWait(process, commandID: commandID)
            } onCancel: {
                Task { await self.cancel(commandID) }
            }
        } catch is CancellationError {
            throw ExternalProcessRunnerError.cancelled
        } catch let error as ExternalProcessRunnerError {
            throw error
        } catch {
            throw ExternalProcessRunnerError.launchFailed(error.localizedDescription)
        }

        let stdout = Self.diagnosticString(from: stdoutCollector.finish())
        let stderr = Self.diagnosticString(from: stderrCollector.finish())
        if timedOutCommands.contains(commandID) {
            throw ExternalProcessRunnerError.timedOut
        }
        if cancelledCommands.contains(commandID) || Task.isCancelled {
            throw ExternalProcessRunnerError.cancelled
        }

        return ExternalProcessResult(
            exitCode: exitCode,
            standardOutput: stdout,
            standardError: stderr
        )
    }

    private func launchAndWait(_ process: Process, commandID: UUID) async throws -> Int32 {
        try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { finishedProcess in
                continuation.resume(returning: finishedProcess.terminationStatus)
            }

            do {
                try process.run()
                let pid = process.processIdentifier
                // This succeeds before the child has spawned descendants on the
                // common path. Even if the child has already exec'd, terminating
                // the Process itself remains a safe fallback.
                _ = setpgid(pid, pid)
                runningCommands[commandID] = RunningCommand(
                    process: process,
                    processGroupID: pid
                )
            } catch {
                process.terminationHandler = nil
                continuation.resume(throwing: error)
            }
        }
    }

    private func cancel(_ commandID: UUID) {
        cancelledCommands.insert(commandID)
        terminate(commandID)
    }

    private func timeOut(_ commandID: UUID) {
        guard runningCommands[commandID]?.process.isRunning == true else {
            return
        }
        timedOutCommands.insert(commandID)
        terminate(commandID)
    }

    private func terminate(_ commandID: UUID) {
        guard let command = runningCommands[commandID], command.process.isRunning else {
            return
        }

        _ = kill(-command.processGroupID, SIGTERM)
        command.process.terminate()
        Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(500))
            } catch {
                return
            }
            await self?.forceTerminate(commandID)
        }
    }

    private func forceTerminate(_ commandID: UUID) {
        guard let command = runningCommands[commandID], command.process.isRunning else {
            return
        }
        _ = kill(-command.processGroupID, SIGKILL)
        _ = kill(command.process.processIdentifier, SIGKILL)
    }

    nonisolated static func defaultEnvironment(
        temporaryDirectory: URL? = nil
    ) -> [String: String] {
        let inherited = ProcessInfo.processInfo.environment
        let inheritedPaths = inherited["PATH"]?
            .split(separator: ":")
            .map(String.init) ?? []
        let paths = Self.unique([
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
        ] + inheritedPaths)

        var environment: [String: String] = [
            "LANG": inherited["LANG"] ?? "en_US.UTF-8",
            "PATH": paths.joined(separator: ":"),
        ]
        if let home = inherited["HOME"], !home.isEmpty {
            environment["HOME"] = home
        }
        if let temporaryDirectory {
            environment["TMPDIR"] = temporaryDirectory.path
        } else if let temporary = inherited["TMPDIR"], !temporary.isEmpty {
            environment["TMPDIR"] = temporary
        }
        return environment
    }

    nonisolated private static func unique(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    nonisolated private static func diagnosticString(from data: Data) -> String {
        String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

nonisolated private final class BoundedPipeCollector: @unchecked Sendable {
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
