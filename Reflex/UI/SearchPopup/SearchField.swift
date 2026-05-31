import SwiftUI
import AppKit

/// NSTextField wrapper that intercepts arrow keys / Enter / Escape so the
/// popup view model can drive selection + dismissal.
struct SearchField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var cursorColor: NSColor = .textColor
    var onMoveUp: () -> Void
    var onMoveDown: () -> Void
    var onEnter: () -> Void
    var onCommandEnter: () -> Void
    var onShiftEnter: () -> Void
    var onEscape: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let field = InterceptingTextField()
        field.placeholderString = placeholder
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 20, weight: .regular)
        field.delegate = context.coordinator
        field.target = context.coordinator
        field.action = #selector(Coordinator.onAction(_:))
        field.cell?.usesSingleLineMode = true
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.onMoveUp = onMoveUp
        field.onMoveDown = onMoveDown
        field.onEnter = onEnter
        field.onCommandEnter = onCommandEnter
        field.onShiftEnter = onShiftEnter
        field.onEscape = onEscape
        field.cursorColor = cursorColor
        DispatchQueue.main.async {
            field.window?.makeFirstResponder(field)
        }
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        if let f = nsView as? InterceptingTextField {
            f.onMoveUp = onMoveUp
            f.onMoveDown = onMoveDown
            f.onEnter = onEnter
            f.onCommandEnter = onCommandEnter
            f.onShiftEnter = onShiftEnter
            f.onEscape = onEscape
            f.cursorColor = cursorColor
            // Re-apply live if the preference changes while the field is active.
            if let editor = f.currentEditor() as? NSTextView {
                editor.insertionPointColor = cursorColor
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: SearchField
        init(_ parent: SearchField) { self.parent = parent }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        // Arrow keys (and Return/Escape) are consumed by the field editor
        // (NSTextView) before NSTextField.keyDown runs, so intercept them here.
        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.moveUp(_:)):
                parent.onMoveUp()
                return true
            case #selector(NSResponder.moveDown(_:)):
                parent.onMoveDown()
                return true
            case #selector(NSResponder.insertNewline(_:)),
                 #selector(NSResponder.insertLineBreak(_:)),
                 #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
                // The field editor collapses all Return variants onto the same
                // selector — inspect the current event's modifiers to distinguish
                // plain Enter (play) from Cmd+Enter (queue) and Shift+Enter (play).
                let flags = NSApp.currentEvent?.modifierFlags.intersection(.deviceIndependentFlagsMask) ?? []
                if flags.contains(.command) {
                    parent.onCommandEnter()
                } else if flags.contains(.shift) {
                    parent.onShiftEnter()
                } else {
                    parent.onEnter()
                }
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                parent.onEscape()
                return true
            default:
                return false
            }
        }

        @objc func onAction(_ sender: Any?) {}
    }
}

private final class InterceptingTextField: NSTextField {
    var onMoveUp: (() -> Void)?
    var onMoveDown: (() -> Void)?
    var onEnter: (() -> Void)?
    var onCommandEnter: (() -> Void)?
    var onShiftEnter: (() -> Void)?
    var onEscape: (() -> Void)?
    var cursorColor: NSColor = .textColor

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if let editor = currentEditor() as? NSTextView {
            editor.insertionPointColor = cursorColor
        }
        return result
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 126: // up
            onMoveUp?()
            return
        case 125: // down
            onMoveDown?()
            return
        case 36, 76: // return, keypad enter
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if flags.contains(.command) {
                onCommandEnter?()
            } else if flags.contains(.shift) {
                onShiftEnter?()
            } else {
                onEnter?()
            }
            return
        case 53: // escape
            onEscape?()
            return
        default:
            break
        }
        super.keyDown(with: event)
    }
}
