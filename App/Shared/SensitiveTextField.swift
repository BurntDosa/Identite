import SwiftUI
import IDCore

// All native exports are blocked except explicit Copy/Cut through the owned clipboard.
#if os(macOS)
struct SensitiveTextField: NSViewRepresentable {
    let title: String
    @Binding var text: String
    var input: FieldInput = .digits
    var uppercase = false
    var canCopy: (() -> Bool)?

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        let cell = SensitiveTextFieldCell(textCell: "")
        cell.wraps = input == .multiline
        cell.isScrollable = input != .multiline
        field.cell = cell
        field.maximumNumberOfLines = input == .multiline ? 8 : 1
        field.placeholderString = title
        field.isBordered = false
        field.isEditable = true
        field.isSelectable = true
        field.drawsBackground = false
        field.setAccessibilityLabel(title)
        return field
    }
    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        if let cell = field.cell as? SensitiveTextFieldCell {
            cell.canCopy = canCopy
            cell.didEdit = { context.coordinator.parent.text = $0 }
        }
        if field.stringValue != text { field.stringValue = text }
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSTextField, context: Context) -> CGSize? {
        let width = proposal.width ?? 100
        let height = nsView.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: width, height: .greatestFiniteMagnitude)).height
        return CGSize(width: width, height: max(input == .multiline ? 60 : 0, height ?? nsView.intrinsicContentSize.height))
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    final class Coordinator: NSObject {
        var parent: SensitiveTextField
        init(_ parent: SensitiveTextField) { self.parent = parent }
    }
}

final class SensitiveTextFieldCell: NSTextFieldCell {
    private let editor = SensitiveFieldEditor()
    var canCopy: (() -> Bool)? { didSet { editor.canCopy = canCopy } }
    var didEdit: ((String) -> Void)? { didSet { editor.didEdit = didEdit } }
    override func fieldEditor(for controlView: NSView) -> NSTextView? {
        editor.isFieldEditor = true
        editor.isMultiline = wraps
        editor.isRichText = false
        editor.allowsUndo = true
        editor.isAutomaticSpellingCorrectionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false
        editor.writingToolsBehavior = .none
        return editor
    }
}

final class SensitiveFieldEditor: NSTextView {
    var canCopy: (() -> Bool)?
    var didEdit: ((String) -> Void)?
    var isMultiline = false
    override func didChangeText() {
        super.didChangeText()
        didEdit?(string)
    }
    // Field-editor undo must also publish the restored value to the SwiftUI binding.
    @objc func undo(_ sender: Any?) { undoManager?.undo(); didChangeText() }
    @objc func redo(_ sender: Any?) { undoManager?.redo(); didChangeText() }
    override func insertNewline(_ sender: Any?) {
        if isMultiline { insertText("\n", replacementRange: selectedRange()) }
        else { super.insertNewline(sender) }
    }
    override func copy(_ sender: Any?) {
        guard canCopy?() == true, selectedRange().length > 0 else { return }
        SecureClipboard.copy((string as NSString).substring(with: selectedRange()))
    }
    override func cut(_ sender: Any?) {
        guard canCopy?() == true, selectedRange().length > 0 else { return }
        copy(sender)
        breakUndoCoalescing()
        insertText("", replacementRange: selectedRange())
        breakUndoCoalescing()
    }
    override var writablePasteboardTypes: [NSPasteboard.PasteboardType] { [] }
    override func writeSelection(to pasteboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool { false }
    override func writeSelection(to pasteboard: NSPasteboard, types: [NSPasteboard.PasteboardType]) -> Bool { false }
    override func validRequestor(forSendType sendType: NSPasteboard.PasteboardType?,
                                 returnType: NSPasteboard.PasteboardType?) -> Any? { nil }
    override func dragSelection(with event: NSEvent, offset: NSSize, slideBack: Bool) -> Bool { false }
    override func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        if [#selector(copy(_:)), #selector(cut(_:))].contains(item.action) {
            return canCopy?() == true && selectedRange().length > 0
        }
        guard [#selector(paste(_:)), #selector(selectAll(_:)), #selector(delete(_:)),
               NSSelectorFromString("undo:"), NSSelectorFromString("redo:")].contains(item.action) else { return false }
        return super.validateUserInterfaceItem(item)
    }
    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        for (title, action) in [("Cut", #selector(cut(_:))), ("Copy", #selector(copy(_:))),
                                ("Paste", #selector(paste(_:))), ("Select All", #selector(selectAll(_:)))] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            if validateUserInterfaceItem(item) { menu.addItem(item) }
        }
        return menu
    }
}
#else
struct SensitiveTextField: UIViewRepresentable {
    let title: String
    @Binding var text: String
    var input: FieldInput = .digits
    var uppercase = false
    var canCopy: (() -> Bool)?

    func makeUIView(context: Context) -> UIView {
        if input == .multiline {
            let view = SensitiveNativeTextView()
            view.accessibilityLabel = title
            view.font = .preferredFont(forTextStyle: .body)
            view.adjustsFontForContentSizeCategory = true
            view.backgroundColor = .clear
            view.textContainerInset = .zero
            view.textContainer.lineFragmentPadding = 0
            view.isScrollEnabled = false
            view.autocorrectionType = .no
            view.spellCheckingType = .no
            view.writingToolsBehavior = .none
            view.textDragInteraction?.isEnabled = false
            view.delegate = context.coordinator
            return view
        }
        let field = SensitiveNativeField()
        field.placeholder = title
        field.accessibilityLabel = title
        field.font = .preferredFont(forTextStyle: .body)
        field.adjustsFontForContentSizeCategory = true
        // UIKit excludes keyboard extensions from phonePad; a revealed CVV remains editable with system keys.
        field.keyboardType = input == .digits ? (canCopy == nil ? .phonePad : .numberPad) : .default
        field.autocapitalizationType = uppercase ? .allCharacters : .none
        field.autocorrectionType = .no
        field.spellCheckingType = .no
        field.writingToolsBehavior = .none
        field.textDragInteraction?.isEnabled = false
        field.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .editingChanged)
        return field
    }
    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.parent = self
        if let field = view as? SensitiveNativeField {
            field.canCopy = canCopy
            if field.text != text { field.text = text }
        } else if let field = view as? SensitiveNativeTextView {
            field.canCopy = canCopy
            if field.text != text { field.text = text }
        }
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIView, context: Context) -> CGSize? {
        let width = proposal.width ?? 100
        let height = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
        return CGSize(width: width, height: max(input == .multiline ? 60 : 0, height))
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    @MainActor final class Coordinator: NSObject, UITextViewDelegate {
        var parent: SensitiveTextField
        init(_ parent: SensitiveTextField) { self.parent = parent }
        @objc func changed(_ field: UITextField) { parent.text = field.text ?? "" }
        func textViewDidChange(_ textView: UITextView) { parent.text = textView.text }
    }
}

final class SensitiveNativeField: UITextField {
    var canCopy: (() -> Bool)?
    override func copy(_ sender: Any?) {
        guard canCopy?() == true, let range = selectedTextRange, let value = text(in: range), !value.isEmpty else { return }
        SecureClipboard.copy(value)
    }
    override func cut(_ sender: Any?) {
        guard canCopy?() == true, let range = selectedTextRange, !range.isEmpty else { return }
        copy(sender); replace(range, withText: ""); sendActions(for: .editingChanged)
    }
    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if [#selector(copy(_:)), #selector(cut(_:))].contains(action) {
            return canCopy?() == true && selectedTextRange?.isEmpty == false
        }
        guard [#selector(paste(_:)), #selector(select(_:)), #selector(selectAll(_:)), #selector(delete(_:))].contains(action) else { return false }
        return super.canPerformAction(action, withSender: sender)
    }
}

final class SensitiveNativeTextView: UITextView {
    var canCopy: (() -> Bool)?
    override func copy(_ sender: Any?) {
        guard canCopy?() == true, let range = selectedTextRange, let value = text(in: range), !value.isEmpty else { return }
        SecureClipboard.copy(value)
    }
    override func cut(_ sender: Any?) {
        guard canCopy?() == true, let range = selectedTextRange, !range.isEmpty else { return }
        copy(sender); replace(range, withText: ""); delegate?.textViewDidChange?(self)
    }
    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if [#selector(copy(_:)), #selector(cut(_:))].contains(action) {
            return canCopy?() == true && selectedTextRange?.isEmpty == false
        }
        guard [#selector(paste(_:)), #selector(select(_:)), #selector(selectAll(_:)), #selector(delete(_:))].contains(action) else { return false }
        return super.canPerformAction(action, withSender: sender)
    }
}
#endif
