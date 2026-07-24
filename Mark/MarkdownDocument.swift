//
//  MarkdownDocument.swift
//  DiagramDown
//

import SwiftUI
import UniformTypeIdentifiers

nonisolated enum MarkdownFileCodec {
    static func decode(_ data: Data) throws -> String {
        guard let text = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        return text
    }

    static func encode(_ text: String) throws -> Data {
        guard let data = text.data(using: .utf8) else {
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }
        return data
    }
}

struct MarkdownDocument: FileDocument {
    static var readableContentTypes: [UTType] {
        [.markdown]
    }

    var text: String

    init(text: String = "") {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }

        text = try MarkdownFileCodec.decode(data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = try MarkdownFileCodec.encode(text)
        return FileWrapper(regularFileWithContents: data)
    }
}

private extension UTType {
    static let markdown = UTType(importedAs: "net.daringfireball.markdown")
}
