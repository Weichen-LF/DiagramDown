//
//  NativePreviewModel.swift
//  DiagramDown
//

import Foundation
import Combine
import SwiftUI

@MainActor
final class NativePreviewModel: ObservableObject {
    @Published private(set) var document = PreviewDocument.empty
    @Published private(set) var parseError: String?
    @Published private(set) var isParsing = false

    private var revision: UInt64 = 0

    func update(source: String) async {
        revision &+= 1
        let requestedRevision = revision
        isParsing = true

        do {
            try await Task.sleep(for: .milliseconds(120))
            try Task.checkCancellation()
            let parsed = try await MarkdownParserService.shared.parse(
                source: source,
                revision: requestedRevision,
                previous: document
            )
            try Task.checkCancellation()
            guard requestedRevision == revision else {
                return
            }
            document = parsed
            parseError = nil
            isParsing = false
        } catch is CancellationError {
            if requestedRevision == revision {
                isParsing = false
            }
        } catch {
            guard requestedRevision == revision else {
                return
            }
            parseError = error.localizedDescription
            isParsing = false
        }
    }
}
