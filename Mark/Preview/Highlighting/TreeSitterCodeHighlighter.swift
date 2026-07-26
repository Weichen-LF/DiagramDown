//
//  TreeSitterCodeHighlighter.swift
//  DiagramDown
//

import AppKit
import CryptoKit
import Foundation
import SwiftTreeSitter
import SwiftTreeSitterLayer
import SwiftUI

actor TreeSitterCodeHighlighter: CodeHighlighting {
    static let shared = TreeSitterCodeHighlighter()

    private struct CacheEntry {
        let value: AttributedString
        let cost: Int
        var lastAccess: UInt64
    }

    private let registry = TreeSitterLanguageRegistry()
    private var definitions: [CodeLanguage: TreeSitterLanguageDefinition] = [:]
    private var unavailable = Set<CodeLanguage>()
    private var cache: [String: CacheEntry] = [:]
    private var cacheCost = 0
    private var accessCounter: UInt64 = 0
    private let maximumCacheCost = 32 * 1_024 * 1_024
    private let maximumHighlightBytes = 2 * 1_024 * 1_024

    func cacheStatistics() -> PreviewCacheStatistics {
        PreviewCacheStatistics(
            entryCount: cache.count,
            estimatedBytes: cacheCost
        )
    }

    func purgeCaches() {
        cache.removeAll(keepingCapacity: false)
        cacheCost = 0
        accessCounter = 0
    }

    func highlight(
        source: String,
        language: CodeLanguage?,
        theme: CodeTheme
    ) async -> AttributedString {
        let plain = plainText(source, theme: theme)
        guard source.utf8.count <= maximumHighlightBytes,
              let language,
              language != .mermaid,
              language != .d2,
              let definition = definition(for: language) else {
            return plain
        }

        let key = cacheKey(
            source: source,
            language: language,
            grammarVersion: definition.grammarVersion,
            theme: theme
        )
        if var entry = cache[key] {
            accessCounter &+= 1
            entry.lastAccess = accessCounter
            cache[key] = entry
            return entry.value
        }

        do {
            try Task.checkCancellation()
            let layer = try LanguageLayer(
                languageConfig: definition.configuration,
                configuration: .init(maximumLanguageDepth: 0)
            )
            layer.replaceContent(with: source)
            let ranges = try layer.highlights(
                in: NSRange(location: 0, length: source.utf16.count),
                provider: source.predicateTextProvider
            )
            try Task.checkCancellation()

            let highlighted = apply(
                ranges: ranges,
                to: source,
                theme: theme
            )
            store(highlighted, source: source, forKey: key)
            return highlighted
        } catch {
            return plain
        }
    }

    private func definition(
        for language: CodeLanguage
    ) -> TreeSitterLanguageDefinition? {
        if let cached = definitions[language] {
            return cached
        }
        guard !unavailable.contains(language) else {
            return nil
        }

        do {
            guard let definition = try registry.definition(for: language) else {
                unavailable.insert(language)
                return nil
            }
            definitions[language] = definition
            return definition
        } catch {
            unavailable.insert(language)
            return nil
        }
    }

    private func plainText(
        _ source: String,
        theme: CodeTheme
    ) -> AttributedString {
        var result = AttributedString(source)
        result.foregroundColor = theme.foreground
        result.font = Font.system(
            size: 13,
            weight: .regular,
            design: .monospaced
        )
        return result
    }

    private func apply(
        ranges: [NamedRange],
        to source: String,
        theme: CodeTheme
    ) -> AttributedString {
        var result = plainText(source, theme: theme)
        let sorted = ranges.sorted {
            if $0.range.length == $1.range.length {
                return $0.nameComponents.count < $1.nameComponents.count
            }
            return $0.range.length > $1.range.length
        }

        for namedRange in sorted {
            let token = SyntaxCaptureNormalizer.token(for: namedRange.name)
            guard token != .plain,
                  let style = theme.styles[token],
                  namedRange.range.location >= 0,
                  namedRange.range.length >= 0,
                  NSMaxRange(namedRange.range) <= source.utf16.count,
                  let sourceRange = Range(namedRange.range, in: source),
                  let lower = AttributedString.Index(
                      sourceRange.lowerBound,
                      within: result
                  ),
                  let upper = AttributedString.Index(
                      sourceRange.upperBound,
                      within: result
                  ) else {
                continue
            }

            result[lower..<upper].foregroundColor = style.color
            let weight: Font.Weight = style.bold ? .semibold : .regular
            let font = Font.system(
                size: 13,
                weight: weight,
                design: .monospaced
            )
            result[lower..<upper].font = style.italic ? font.italic() : font
        }
        return result
    }

    private func cacheKey(
        source: String,
        language: CodeLanguage,
        grammarVersion: String,
        theme: CodeTheme
    ) -> String {
        let descriptor = [
            MarkdownParserService.digest(source),
            language.rawValue,
            grammarVersion,
            "queries-v1",
            theme.id,
            "highlighter-v1",
        ].joined(separator: "\u{0}")
        return MarkdownParserService.digest(descriptor)
    }

    private func store(
        _ value: AttributedString,
        source: String,
        forKey key: String
    ) {
        let cost = max(source.utf16.count * 4, 1)
        accessCounter &+= 1
        cache[key] = CacheEntry(
            value: value,
            cost: cost,
            lastAccess: accessCounter
        )
        cacheCost += cost

        while cacheCost > maximumCacheCost,
              let oldest = cache.min(by: {
                  $0.value.lastAccess < $1.value.lastAccess
              }) {
            cacheCost -= oldest.value.cost
            cache.removeValue(forKey: oldest.key)
        }
    }
}
