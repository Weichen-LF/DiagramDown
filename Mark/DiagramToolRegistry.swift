//
//  DiagramToolRegistry.swift
//  DiagramDown
//

import Foundation

nonisolated enum DiagramToolKind: String, CaseIterable, Identifiable, Sendable {
    case mermaid
    case d2

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .mermaid: "Mermaid CLI"
        case .d2: "D2 CLI"
        }
    }

    var executableName: String {
        switch self {
        case .mermaid: "mmdc"
        case .d2: "d2"
        }
    }

    var versionArguments: [String] {
        switch self {
        case .mermaid: ["--version"]
        case .d2: ["version"]
        }
    }

    var installCommand: String {
        switch self {
        case .mermaid: "npm install -g @mermaid-js/mermaid-cli"
        case .d2: "brew install d2"
        }
    }

    var customPathPreferenceKey: String {
        "DiagramTools.\(rawValue).customPath"
    }
}

nonisolated struct InstalledDiagramTool: Equatable, Hashable, Sendable {
    let kind: DiagramToolKind
    let executableURL: URL
    let version: String

    var cacheDescriptor: String {
        "\(executableURL.path)\u{0}\(version)"
    }
}

nonisolated enum DiagramToolStatus: Equatable, Sendable {
    case installed(InstalledDiagramTool)
    case missing
    case invalid(path: String, message: String)

    var installedTool: InstalledDiagramTool? {
        guard case .installed(let tool) = self else {
            return nil
        }
        return tool
    }
}

nonisolated enum DiagramToolResolutionError: LocalizedError, Sendable {
    case missing(DiagramToolKind)
    case invalid(DiagramToolKind, String)

    var errorDescription: String? {
        switch self {
        case .missing(let kind):
            "\(kind.displayName) is not installed."
        case .invalid(let kind, let message):
            "\(kind.displayName) is unavailable: \(message)"
        }
    }
}

actor DiagramToolRegistry {
    static let shared = DiagramToolRegistry()
    nonisolated static let revisionPreferenceKey = "DiagramTools.revision"

    private let defaults: UserDefaults
    private let fileManager: FileManager
    private let runner: ExternalProcessRunner
    private let environment: [String: String]
    private let automaticDirectories: [URL]
    private var cachedStatuses: [DiagramToolKind: DiagramToolStatus] = [:]

    init(
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default,
        runner: ExternalProcessRunner = .shared,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        automaticDirectories: [URL]? = nil
    ) {
        self.defaults = defaults
        self.fileManager = fileManager
        self.runner = runner
        self.environment = environment
        self.automaticDirectories = automaticDirectories
            ?? Self.defaultSearchDirectories(environment: environment)
    }

    func status(
        for kind: DiagramToolKind,
        refresh: Bool = false
    ) async -> DiagramToolStatus {
        if !refresh, let cached = cachedStatuses[kind] {
            if case .installed(let tool) = cached,
               !fileManager.isExecutableFile(atPath: tool.executableURL.path) {
                cachedStatuses.removeValue(forKey: kind)
            } else {
                return cached
            }
        }
        let status = await discover(kind)
        cachedStatuses[kind] = status
        return status
    }

    func installedTool(
        for kind: DiagramToolKind,
        refresh: Bool = false
    ) async throws -> InstalledDiagramTool {
        let status = await status(for: kind, refresh: refresh)
        switch status {
        case .installed(let tool):
            return tool
        case .missing:
            throw DiagramToolResolutionError.missing(kind)
        case .invalid(_, let message):
            throw DiagramToolResolutionError.invalid(kind, message)
        }
    }

    func refreshAll(notifyViews: Bool = false) async -> [DiagramToolKind: DiagramToolStatus] {
        var statuses: [DiagramToolKind: DiagramToolStatus] = [:]
        for kind in DiagramToolKind.allCases {
            statuses[kind] = await status(for: kind, refresh: true)
        }
        if notifyViews {
            defaults.set(
                defaults.integer(forKey: Self.revisionPreferenceKey) &+ 1,
                forKey: Self.revisionPreferenceKey
            )
        }
        return statuses
    }

    func setCustomExecutable(
        _ url: URL?,
        for kind: DiagramToolKind
    ) async -> DiagramToolStatus {
        if let url {
            let validated = await validate(url, kind: kind, reportsInvalid: true)
            guard case .installed = validated else {
                return validated
            }
            defaults.set(url.standardizedFileURL.path, forKey: kind.customPathPreferenceKey)
            cachedStatuses[kind] = validated
        } else {
            defaults.removeObject(forKey: kind.customPathPreferenceKey)
            cachedStatuses.removeValue(forKey: kind)
        }
        let status = url == nil
            ? await self.status(for: kind, refresh: true)
            : cachedStatuses[kind] ?? .missing
        defaults.set(
            defaults.integer(forKey: Self.revisionPreferenceKey) &+ 1,
            forKey: Self.revisionPreferenceKey
        )
        return status
    }

    nonisolated static func defaultSearchDirectories(
        environment: [String: String]
    ) -> [URL] {
        let environmentPaths = environment["PATH"]?
            .split(separator: ":")
            .map(String.init) ?? []
        var seen: Set<String> = []
        return ([
            "/opt/homebrew/bin",
            "/usr/local/bin",
        ] + environmentPaths)
            .filter { $0.hasPrefix("/") && seen.insert($0).inserted }
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    private func discover(_ kind: DiagramToolKind) async -> DiagramToolStatus {
        if let customPath = defaults.string(forKey: kind.customPathPreferenceKey),
           !customPath.isEmpty {
            return await validate(
                URL(fileURLWithPath: customPath),
                kind: kind,
                reportsInvalid: true
            )
        }

        for directory in automaticDirectories {
            let candidate = directory.appendingPathComponent(kind.executableName)
            guard fileManager.isExecutableFile(atPath: candidate.path) else {
                continue
            }
            return await validate(candidate, kind: kind, reportsInvalid: true)
        }
        return .missing
    }

    private func validate(
        _ candidate: URL,
        kind: DiagramToolKind,
        reportsInvalid: Bool
    ) async -> DiagramToolStatus {
        let standardized = candidate.standardizedFileURL.resolvingSymlinksInPath()
        guard fileManager.isExecutableFile(atPath: standardized.path) else {
            return reportsInvalid
                ? .invalid(path: candidate.path, message: "The selected file is not executable.")
                : .missing
        }

        do {
            let result = try await runner.run(
                executableURL: standardized,
                arguments: kind.versionArguments,
                environment: ExternalProcessRunner.defaultEnvironment(),
                timeout: .seconds(3),
                maximumOutputBytes: 16 * 1_024
            )
            guard result.exitCode == 0 else {
                let diagnostic = Self.cleanedDiagnostic(
                    result.standardError.isEmpty
                        ? result.standardOutput
                        : result.standardError
                )
                return .invalid(
                    path: candidate.path,
                    message: diagnostic.isEmpty
                        ? "Version check exited with code \(result.exitCode)."
                        : diagnostic
                )
            }
            let output = result.standardOutput.isEmpty
                ? result.standardError
                : result.standardOutput
            let version = Self.cleanedDiagnostic(output)
                .split(whereSeparator: \.isNewline)
                .first
                .map(String.init) ?? "unknown"
            return .installed(InstalledDiagramTool(
                kind: kind,
                executableURL: standardized,
                version: version
            ))
        } catch {
            return .invalid(
                path: candidate.path,
                message: Self.cleanedDiagnostic(error.localizedDescription)
            )
        }
    }

    nonisolated static func cleanedDiagnostic(_ diagnostic: String) -> String {
        let collapsed = diagnostic
            .replacingOccurrences(of: "\0", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(collapsed.prefix(1_024))
    }
}
