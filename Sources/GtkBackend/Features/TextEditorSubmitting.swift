import CGtk
import Gtk
import GtkCHelpers
@_spi(Backends) import SwiftCrossUI

/// Owns a text editor's submit action while GTK holds a pointer to it.
private final class TextEditorSubmitBox {
    var action: @MainActor (TextEditorSubmission) -> Void
    let view: UnsafeMutablePointer<GtkTextView>

    init(
        action: @escaping @MainActor (TextEditorSubmission) -> Void,
        view: UnsafeMutablePointer<GtkTextView>
    ) {
        self.action = action
        self.view = view
    }
}

private struct WeakSubmitBox {
    weak var box: TextEditorSubmitBox?
}

/// The installed handlers, by text view (weak: GTK owns the boxes).
@MainActor private var submitBoxes: [ObjectIdentifier: WeakSubmitBox] = [:]

private let submitTextEditor: GtkTextViewSubmitFunc = { context in
    MainActor.assumeIsolated {
        guard let context else { return }
        let box = Unmanaged<TextEditorSubmitBox>.fromOpaque(context).takeUnretainedValue()
        let buffer = gtk_text_view_get_buffer(box.view)

        var start = GtkTextIter()
        var end = GtkTextIter()
        gtk_text_buffer_get_bounds(buffer, &start, &end)
        let raw = gtk_text_buffer_get_text(buffer, &start, &end, 1)
        let text = raw.map { String(cString: $0) } ?? ""
        g_free(raw)

        var selectionStart = GtkTextIter()
        var selectionEnd = GtkTextIter()
        let selection: Swift.Range<Int>?
        if gtk_text_buffer_get_selection_bounds(buffer, &selectionStart, &selectionEnd) != 0 {
            selection =
                Int(gtk_text_iter_get_offset(&selectionStart))..<Int(gtk_text_iter_get_offset(&selectionEnd))
        } else {
            selection = nil
        }

        var cursor = GtkTextIter()
        gtk_text_buffer_get_iter_at_mark(buffer, &cursor, gtk_text_buffer_get_insert(buffer))

        box.action(
            TextEditorSubmission(
                text: text, selection: selection, cursor: Int(gtk_text_iter_get_offset(&cursor))))
    }
}

private let releaseTextEditorSubmitBox: GDestroyNotify = { context in
    guard let context else { return }
    Unmanaged<TextEditorSubmitBox>.fromOpaque(context).release()
}

extension GtkBackend: BackendFeatures.TextEditorSubmitting {
    public func setSubmitHandler(
        ofTextEditor textEditor: Widget,
        to action: (@MainActor (TextEditorSubmission) -> Void)?
    ) {
        let textView = textEditor as! Gtk.TextView
        let view = textView.widgetPointer.withMemoryRebound(to: GtkTextView.self, capacity: 1) { $0 }
        guard let action else {
            if submitBoxes.removeValue(forKey: ObjectIdentifier(textView)) != nil {
                gtk_text_view_set_submit_handler(view, nil, nil, nil)
            }
            return
        }
        // Called on every update: swap the action instead of reinstalling.
        if let box = submitBoxes[ObjectIdentifier(textView)]?.box {
            box.action = action
            return
        }
        let box = TextEditorSubmitBox(action: action, view: view)
        submitBoxes[ObjectIdentifier(textView)] = WeakSubmitBox(box: box)
        // GTK keeps the box alive until the handler is removed or the view goes.
        gtk_text_view_set_submit_handler(
            view, submitTextEditor, Unmanaged.passRetained(box).toOpaque(),
            releaseTextEditorSubmitBox)
    }
}
