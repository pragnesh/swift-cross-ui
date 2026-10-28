extension BackendFeatures {
    /// Backend methods for submitting a text editor's contents with a
    /// keyboard shortcut (Ctrl+Enter / Cmd+Return).
    ///
    /// These are used by ``TextEditor``'s `onCommandReturn` handler. It's a
    /// separate feature so backends without it still support ``TextEditor``.
    @MainActor
    public protocol TextEditorSubmitting: Core {
        /// Calls `action` when the shortcut is pressed in `textEditor`
        /// (instead of inserting a line break), with the editor's text,
        /// selection and cursor at that moment. `nil` removes the handler.
        func setSubmitHandler(
            ofTextEditor textEditor: Widget,
            to action: (@MainActor (TextEditorSubmission) -> Void)?
        )
    }
}

/// A text editor's contents when it was submitted.
///
/// Offsets count Unicode scalars (`text.unicodeScalars`).
public struct TextEditorSubmission: Hashable, Sendable {
    public var text: String
    /// The selected range, or `nil` when nothing is selected.
    public var selection: Range<Int>?
    /// The cursor position.
    public var cursor: Int

    public init(text: String, selection: Range<Int>?, cursor: Int) {
        self.text = text
        self.selection = selection
        self.cursor = cursor
    }

    /// The selected text, or `nil` when nothing is selected.
    public var selectedText: String? {
        guard let selection, !selection.isEmpty else { return nil }
        let scalars = Array(text.unicodeScalars)
        guard selection.upperBound <= scalars.count else { return nil }
        var result = String.UnicodeScalarView()
        result.append(contentsOf: scalars[selection])
        return String(result)
    }
}
