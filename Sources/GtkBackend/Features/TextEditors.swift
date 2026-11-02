import CGtk
import Gtk
@_spi(Backends) import SwiftCrossUI

extension GtkBackend: BackendFeatures.TextEditors {
    public func createTextEditor() -> Widget {
        let textView = Gtk.TextView()
        textView.wrapMode = .wordCharacter
        return TextEditorWidget(textView: textView)
    }

    public func updateTextEditor(
        _ textEditor: Widget,
        environment: EnvironmentValues,
        onChange: @escaping (String) -> Void
    ) {
        let textEditor = (textEditor as! TextEditorWidget).textView
        textEditor.buffer.changed = { buffer in
            onChange(buffer.text)
        }

        textEditor.css.set(
            properties: Self.cssProperties(for: environment, isControl: false)
                + [CSSProperty(key: "background", value: "none")],
            clear: true
        )
    }

    public func setContent(ofTextEditor textEditor: Widget, to content: String) {
        let textEditor = (textEditor as! TextEditorWidget).textView

        textEditor.buffer.withBlockedSignal(named: "changed") {
            textEditor.buffer.text = content
        }
    }

    public func getContent(ofTextEditor textEditor: Widget) -> String {
        let textEditor = (textEditor as! TextEditorWidget).textView
        return textEditor.buffer.text
    }
}

/// A text view in a scrolled window, so text taller than the editor
/// scrolls instead of being clipped. Lines wrap, so it only scrolls
/// vertically.
final class TextEditorWidget: Widget {
    let textView: Gtk.TextView

    init(textView: Gtk.TextView) {
        self.textView = textView
        super.init(gtk_scrolled_window_new())
        gtk_scrolled_window_set_policy(opaquePointer, GTK_POLICY_NEVER, GTK_POLICY_AUTOMATIC)
        gtk_scrolled_window_set_child(opaquePointer, textView.widgetPointer)
        textView.parentWidget = self
    }
}
