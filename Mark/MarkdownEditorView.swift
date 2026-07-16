//
//  MarkdownEditorView.swift
//  Mark
//

import AppKit
import SwiftUI

struct MarkdownEditorView: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
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
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView,
              textView.string != text else {
            return
        }

        let selection = textView.selectedRange()
        context.coordinator.isApplyingExternalChange = true
        textView.string = text
        textView.setSelectedRange(selection.clamped(toUTF16Length: text.utf16.count))
        context.coordinator.isApplyingExternalChange = false
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding private var text: String
        var isApplyingExternalChange = false

        init(text: Binding<String>) {
            _text = text
        }

        func textDidChange(_ notification: Notification) {
            guard !isApplyingExternalChange,
                  let textView = notification.object as? NSTextView else {
                return
            }

            text = textView.string
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
