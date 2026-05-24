import SwiftUI
import AppKit

struct PasteableTextField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String = ""
    var isSecure: Bool = false

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .bezelBorder

        let textView = KeyHandlingTextView()
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.font = .systemFont(ofSize: 13)
        textView.textContainerInset = NSSize(width: 4, height: 4)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.delegate = context.coordinator
        textView.string = text
        textView.isSecure = isSecure

        scrollView.documentView = textView

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        if let textView = nsView.documentView as? KeyHandlingTextView {
            if textView.string != text {
                textView.string = text
            }
            if textView.isSecure != isSecure {
                textView.isSecure = isSecure
                textView.needsDisplay = true
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: PasteableTextField

        init(_ parent: PasteableTextField) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            if let textView = notification.object as? NSTextView {
                parent.text = textView.string
            }
        }
    }
}

class KeyHandlingTextView: NSTextView {
    var isSecure: Bool = false {
        didSet {
            needsDisplay = true
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.type == .keyDown && event.modifierFlags.contains(.command) {
            if event.charactersIgnoringModifiers == "v" {
                if let pasteString = NSPasteboard.general.string(forType: .string) {
                    self.insertText(pasteString, replacementRange: self.selectedRange())
                    return true
                }
            }
        }
        return super.performKeyEquivalent(with: event)
    }

    override func draw(_ dirtyRect: NSRect) {
        if isSecure && !string.isEmpty {
            let asterisks = String(repeating: "*", count: min(string.count, 40))
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font ?? NSFont.systemFont(ofSize: 13),
                .foregroundColor: NSColor.textColor
            ]
            asterisks.draw(at: NSPoint(x: 4, y: 4), withAttributes: attrs)
        } else {
            super.draw(dirtyRect)
        }
    }
}