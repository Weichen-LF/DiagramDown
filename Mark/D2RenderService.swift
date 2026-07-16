//
//  D2RenderService.swift
//  DiagramDown
//

import CryptoKit
import Darwin
import Foundation

struct D2RenderConfiguration: Hashable, Sendable {
    enum Layout: String, CaseIterable, Hashable, Identifiable, Sendable {
        case dagre
        case elk

        nonisolated var id: String { rawValue }

        nonisolated var displayName: String {
            switch self {
            case .dagre:
                "Dagre"
            case .elk:
                "ELK"
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

struct D2RenderResult: Sendable {
    let svg: String
    let cacheHit: Bool
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

    nonisolated static let rendererVersion = "0.7.1"

    #if arch(arm64)
    nonisolated private static let rendererArchitecture = "arm64"
    #elseif arch(x86_64)
    nonisolated private static let rendererArchitecture = "x86_64"
    #else
    nonisolated private static let rendererArchitecture = "unknown"
    #endif

    private static let maximumInputBytes = 256 * 1_024
    private static let maximumOutputBytes = 8 * 1_024 * 1_024
    private static let maximumDiagnosticBytes = 256 * 1_024
    private static let maximumCacheBytes = 32 * 1_024 * 1_024
    private static let maximumDiskCacheBytes = 256 * 1_024 * 1_024
    private static let diskCacheTrimTargetBytes = 224 * 1_024 * 1_024
    private static let diskCacheDirectoryName = "d2"

    private struct CacheEntry {
        let svg: String
        let cost: Int
        var lastAccess: UInt64
    }

    private let overrideExecutableURL: URL?
    private let overrideCacheDirectoryURL: URL?
    private var runningProcesses: [UUID: Process] = [:]
    private var cancelledJobs: Set<UUID> = []
    private var timedOutJobs: Set<UUID> = []
    private var cache: [String: CacheEntry] = [:]
    private var cacheCost = 0
    private var accessCounter: UInt64 = 0

    init(executableURL: URL? = nil, cacheDirectoryURL: URL? = nil) {
        overrideExecutableURL = executableURL
        overrideCacheDirectoryURL = cacheDirectoryURL
    }

    func render(
        source: String,
        configuration: D2RenderConfiguration = .preview
    ) async throws -> D2RenderResult {
        try Task.checkCancellation()

        guard source.utf8.count <= Self.maximumInputBytes else {
            throw D2RenderError.inputTooLarge
        }

        let key = cacheKey(source: source, configuration: configuration)
        if var cached = cache[key] {
            accessCounter &+= 1
            cached.lastAccess = accessCounter
            cache[key] = cached
            return D2RenderResult(svg: cached.svg, cacheHit: true)
        }

        if let cachedSVG = diskCachedSVG(forKey: key) {
            storeInMemory(svg: cachedSVG, forKey: key)
            return D2RenderResult(svg: cachedSVG, cacheHit: true)
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
        guard isValidSVG(svg) else {
            throw D2RenderError.invalidSVG
        }

        storeInMemory(svg: svg, forKey: key)
        storeOnDisk(svg: svg, forKey: key)
        return D2RenderResult(svg: svg, cacheHit: false)
    }

    private func cacheKey(
        source: String,
        configuration: D2RenderConfiguration
    ) -> String {
        let material = [
            Self.rendererVersion,
            Self.rendererArchitecture,
            configuration.cacheDescriptor,
            source,
        ].joined(separator: "\0")
        let digest = SHA256.hash(data: Data(material.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func storeInMemory(svg: String, forKey key: String) {
        let cost = svg.utf8.count
        guard cost <= Self.maximumCacheBytes else {
            return
        }

        if let previous = cache.removeValue(forKey: key) {
            cacheCost -= previous.cost
        }

        accessCounter &+= 1
        cache[key] = CacheEntry(svg: svg, cost: cost, lastAccess: accessCounter)
        cacheCost += cost

        while cacheCost > Self.maximumCacheBytes,
              let oldestKey = cache.min(by: {
                  $0.value.lastAccess < $1.value.lastAccess
              })?.key,
              let removed = cache.removeValue(forKey: oldestKey) {
            cacheCost -= removed.cost
        }
    }

    private func diskCachedSVG(forKey key: String) -> String? {
        guard let fileURL = diskCacheFileURL(forKey: key),
              FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }

        do {
            let resourceValues = try fileURL.resourceValues(forKeys: [
                .fileSizeKey,
                .isRegularFileKey,
                .isSymbolicLinkKey,
            ])
            guard resourceValues.isRegularFile == true,
                  resourceValues.isSymbolicLink != true,
                  let fileSize = resourceValues.fileSize,
                  fileSize <= Self.maximumOutputBytes else {
                try? FileManager.default.removeItem(at: fileURL)
                return nil
            }

            let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
            guard data.count <= Self.maximumOutputBytes,
                  let svg = String(data: data, encoding: .utf8),
                  isValidSVG(svg) else {
                try? FileManager.default.removeItem(at: fileURL)
                return nil
            }

            try? FileManager.default.setAttributes(
                [.modificationDate: Date()],
                ofItemAtPath: fileURL.path
            )
            return svg
        } catch {
            try? FileManager.default.removeItem(at: fileURL)
            return nil
        }
    }

    private func storeOnDisk(svg: String, forKey key: String) {
        let data = Data(svg.utf8)
        guard data.count <= Self.maximumOutputBytes,
              let fileURL = diskCacheFileURL(forKey: key) else {
            return
        }

        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: fileURL, options: .atomic)
            trimDiskCacheIfNeeded()
        } catch {
            // The cache is an optimization. A write or cleanup failure must not
            // turn an otherwise successful render into a preview error.
        }
    }

    private func diskCacheFileURL(forKey key: String) -> URL? {
        guard key.count >= 4, let directoryURL = diskCacheDirectoryURL else {
            return nil
        }

        let firstShard = String(key.prefix(2))
        let secondShard = String(key.dropFirst(2).prefix(2))
        return directoryURL
            .appendingPathComponent(firstShard, isDirectory: true)
            .appendingPathComponent(secondShard, isDirectory: true)
            .appendingPathComponent("\(key).svg", isDirectory: false)
    }

    private var diskCacheDirectoryURL: URL? {
        if let overrideCacheDirectoryURL {
            return overrideCacheDirectoryURL
        }

        guard let cachesURL = FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        ).first else {
            return nil
        }

        return cachesURL
            .appendingPathComponent(
                Bundle.main.bundleIdentifier ?? "me.walt.diagramdown",
                isDirectory: true
            )
            .appendingPathComponent(Self.diskCacheDirectoryName, isDirectory: true)
    }

    private func trimDiskCacheIfNeeded() {
        guard let directoryURL = diskCacheDirectoryURL,
              let enumerator = FileManager.default.enumerator(
                  at: directoryURL,
                  includingPropertiesForKeys: [
                      .contentModificationDateKey,
                      .fileSizeKey,
                      .isRegularFileKey,
                      .isSymbolicLinkKey,
                  ],
                  options: [.skipsHiddenFiles]
              ) else {
            return
        }

        var entries: [(url: URL, size: Int, lastAccess: Date)] = []
        var totalSize = 0

        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == "svg",
                  let values = try? fileURL.resourceValues(forKeys: [
                      .contentModificationDateKey,
                      .fileSizeKey,
                      .isRegularFileKey,
                      .isSymbolicLinkKey,
                  ]),
                  values.isRegularFile == true,
                  values.isSymbolicLink != true,
                  let size = values.fileSize else {
                continue
            }

            entries.append((
                url: fileURL,
                size: size,
                lastAccess: values.contentModificationDate ?? .distantPast
            ))
            totalSize += size
        }

        guard totalSize > Self.maximumDiskCacheBytes else {
            return
        }

        for entry in entries.sorted(by: { $0.lastAccess < $1.lastAccess }) {
            do {
                try FileManager.default.removeItem(at: entry.url)
                totalSize -= entry.size
            } catch {
                continue
            }

            if totalSize <= Self.diskCacheTrimTargetBytes {
                break
            }
        }
    }

    private func isValidSVG(_ svg: String) -> Bool {
        svg.range(of: "<svg", options: .caseInsensitive) != nil
            && svg.range(of: "</svg>", options: .caseInsensitive) != nil
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
