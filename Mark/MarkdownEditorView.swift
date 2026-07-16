//
//  MarkdownEditorView.swift
//  DiagramDown
//

import AppKit
import SwiftUI

struct MarkdownEditorView: NSViewRepresentable {
    @Binding var text: String
    @Binding var scrollPosition: ScrollSyncPosition
    let scrollTarget: ScrollSyncTarget

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, scrollPosition: $scrollPosition)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true

        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.string = text
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.containerSize = NSSize(
            width: scrollView.contentSize.width,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = true
        textView.textContainerInset = NSSize(width: 18, height: 16)
        textView.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false

        scrollView.documentView = textView
        context.coordinator.attach(scrollView: scrollView, textView: textView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.updateBindings(
            text: $text,
            scrollPosition: $scrollPosition
        )

        guard let textView = scrollView.documentView as? NSTextView else {
            return
        }

        if textView.string != text {
            let selection = textView.selectedRange()
            context.coordinator.isApplyingExternalChange = true
            textView.string = text
            textView.setSelectedRange(selection.clamped(toUTF16Length: text.utf16.count))
            context.coordinator.isApplyingExternalChange = false
            context.coordinator.invalidateLineStarts()
        }

        context.coordinator.apply(scrollTarget: scrollTarget)
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        coordinator.invalidate()
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding private var text: String
        @Binding private var scrollPosition: ScrollSyncPosition
        private weak var scrollView: NSScrollView?
        private weak var textView: NSTextView?
        private var boundsObserver: NSObjectProtocol?
        private var lineStartOffsets: [Int]?
        private var scrollGeneration: UInt64 = 0
        private var appliedTargetGeneration: UInt64 = 0
        private var isApplyingScrollTarget = false
        var isApplyingExternalChange = false

        init(
            text: Binding<String>,
            scrollPosition: Binding<ScrollSyncPosition>
        ) {
            _text = text
            _scrollPosition = scrollPosition
        }

        func attach(scrollView: NSScrollView, textView: NSTextView) {
            self.scrollView = scrollView
            self.textView = textView
            scrollView.contentView.postsBoundsChangedNotifications = true
            boundsObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: scrollView.contentView,
                queue: .main
            ) { [weak self] _ in
                guard self?.isApplyingScrollTarget == false else {
                    return
                }
                self?.publishScrollPosition()
            }
        }

        func updateBindings(
            text: Binding<String>,
            scrollPosition: Binding<ScrollSyncPosition>
        ) {
            _text = text
            _scrollPosition = scrollPosition
        }

        func invalidate() {
            if let boundsObserver {
                NotificationCenter.default.removeObserver(boundsObserver)
                self.boundsObserver = nil
            }
        }

        func invalidateLineStarts() {
            lineStartOffsets = nil
        }

        func textDidChange(_ notification: Notification) {
            guard !isApplyingExternalChange,
                  let textView = notification.object as? NSTextView else {
                return
            }

            text = textView.string
            invalidateLineStarts()
        }

        func apply(scrollTarget: ScrollSyncTarget) {
            guard scrollTarget.generation != 0,
                  scrollTarget.generation != appliedTargetGeneration,
                  let scrollView,
                  let textView else {
                return
            }

            appliedTargetGeneration = scrollTarget.generation
            let offsets = resolvedLineStartOffsets(for: textView.string)
            let roundedLineIndex = min(
                max(Int(scrollTarget.sourceLine.rounded()) - 1, 0),
                offsets.count - 1
            )
            let characterIndex = offsets[roundedLineIndex]

            guard let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else {
                textView.scrollRangeToVisible(NSRange(location: characterIndex, length: 0))
                return
            }

            layoutManager.ensureLayout(for: textContainer)
            let textLength = (textView.string as NSString).length
            let maximumY = max(textView.bounds.height - scrollView.contentView.bounds.height, 0)
            let targetY: CGFloat
            if scrollTarget.usesProgressFallback {
                targetY = CGFloat(min(max(scrollTarget.progress, 0), 1)) * maximumY
            } else {
                let clampedLine = min(
                    max(scrollTarget.sourceLine, 1),
                    Double(offsets.count)
                )
                let lowerLineIndex = min(
                    max(Int(floor(clampedLine)) - 1, 0),
                    offsets.count - 1
                )
                let upperLineIndex = min(lowerLineIndex + 1, offsets.count - 1)
                let fraction = CGFloat(clampedLine - floor(clampedLine))
                let lowerY = verticalPosition(
                    forLineAt: lowerLineIndex,
                    offsets: offsets,
                    textLength: textLength,
                    textView: textView,
                    layoutManager: layoutManager,
                    textContainer: textContainer,
                    maximumY: maximumY
                )
                let upperY = verticalPosition(
                    forLineAt: upperLineIndex,
                    offsets: offsets,
                    textLength: textLength,
                    textView: textView,
                    layoutManager: layoutManager,
                    textContainer: textContainer,
                    maximumY: maximumY
                )
                targetY = lowerY + (upperY - lowerY) * fraction
            }

            let targetPoint = NSPoint(
                x: scrollView.contentView.bounds.minX,
                y: min(max(targetY, 0), maximumY)
            )
            isApplyingScrollTarget = true
            if scrollTarget.animated,
               abs(scrollView.contentView.bounds.minY - targetPoint.y) > 1 {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.18
                    context.allowsImplicitAnimation = true
                    scrollView.contentView.animator().setBoundsOrigin(targetPoint)
                } completionHandler: { [weak self, weak scrollView] in
                    guard let self,
                          self.appliedTargetGeneration == scrollTarget.generation else {
                        return
                    }
                    if let scrollView {
                        scrollView.reflectScrolledClipView(scrollView.contentView)
                    }
                    self.isApplyingScrollTarget = false
                }
            } else {
                scrollView.contentView.scroll(to: targetPoint)
                scrollView.reflectScrolledClipView(scrollView.contentView)
                DispatchQueue.main.async { [weak self] in
                    guard let self,
                          self.appliedTargetGeneration == scrollTarget.generation else {
                        return
                    }
                    self.isApplyingScrollTarget = false
                }
            }
        }

        private func verticalPosition(
            forLineAt lineIndex: Int,
            offsets: [Int],
            textLength: Int,
            textView: NSTextView,
            layoutManager: NSLayoutManager,
            textContainer: NSTextContainer,
            maximumY: CGFloat
        ) -> CGFloat {
            let characterIndex = offsets[lineIndex]
            guard textLength > 0, characterIndex < textLength else {
                return maximumY
            }

            let glyphRange = layoutManager.glyphRange(
                forCharacterRange: NSRange(location: characterIndex, length: 1),
                actualCharacterRange: nil
            )
            let glyphRect = layoutManager.boundingRect(
                forGlyphRange: glyphRange,
                in: textContainer
            )
            return max(textView.textContainerOrigin.y + glyphRect.minY - 12, 0)
        }

        private func publishScrollPosition() {
            guard let scrollView,
                  let textView,
                  let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else {
                return
            }

            layoutManager.ensureLayout(for: textContainer)
            let visibleRect = scrollView.contentView.bounds
            let glyphCount = layoutManager.numberOfGlyphs
            let characterIndex: Int
            if glyphCount == 0 {
                characterIndex = 0
            } else {
                let containerPoint = NSPoint(
                    x: 0,
                    y: max(visibleRect.minY - textView.textContainerOrigin.y, 0)
                )
                let glyphIndex = min(
                    layoutManager.glyphIndex(for: containerPoint, in: textContainer),
                    glyphCount - 1
                )
                characterIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
            }

            let offsets = resolvedLineStartOffsets(for: textView.string)
            let sourceLine = sourceLine(for: characterIndex, offsets: offsets)
            let maximumY = max(textView.bounds.height - visibleRect.height, 0)
            let progress = maximumY > 0
                ? min(max(visibleRect.minY / maximumY, 0), 1)
                : 0

            scrollGeneration &+= 1
            scrollPosition = ScrollSyncPosition(
                sourceLine: sourceLine,
                progress: progress,
                generation: scrollGeneration
            )
        }

        private func resolvedLineStartOffsets(for source: String) -> [Int] {
            if let lineStartOffsets {
                return lineStartOffsets
            }

            let nsSource = source as NSString
            var result = [0]
            if nsSource.length > 0 {
                for index in 0..<nsSource.length where nsSource.character(at: index) == 10 {
                    result.append(index + 1)
                }
            }
            lineStartOffsets = result
            return result
        }

        private func sourceLine(for characterIndex: Int, offsets: [Int]) -> Int {
            var lowerBound = 0
            var upperBound = offsets.count
            while lowerBound < upperBound {
                let middle = (lowerBound + upperBound) / 2
                if offsets[middle] <= characterIndex {
                    lowerBound = middle + 1
                } else {
                    upperBound = middle
                }
            }
            return max(lowerBound, 1)
        }
    }
}

private extension NSRange {
    func clamped(toUTF16Length length: Int) -> NSRange {
        let location = min(location, length)
        let maximumLength = max(length - location, 0)
        return NSRange(location: location, length: min(self.length, maximumLength))
    }
}
