import CGtk
import Gtk
@_spi(Backends) import SwiftCrossUI

extension GtkBackend: BackendFeatures.TextViews {
    public func size(
        of text: String,
        whenDisplayedIn widget: Widget,
        proposedWidth: Int?,
        proposedHeight: Int?,
        environment: EnvironmentValues
    ) -> SIMD2<Int> {
        // Layout measures the same strings with the same proposals and style
        // many times per update (probing passes, stacks, scroll views), and
        // each measurement creates a Pango context and shapes the whole
        // string. The result depends only on these inputs, so memoize it.
        let key = TextSizeCache.Key(
            text: text,
            proposedWidth: proposedWidth,
            proposedHeight: proposedHeight,
            isTextEditor: widget is TextView,
            style: Self.cssProperties(for: environment).map { "\($0.key):\($0.value)" },
            lineLimit: environment.lineLimitSettings.map {
                TextSizeCache.LineLimit(limit: $0.limit, reservesSpace: $0.reservesSpace)
            }
        )
        if let size = textSizeCache.sizes[key] {
            return size
        }
        let size = measureText(
            text,
            whenDisplayedIn: widget,
            proposedWidth: proposedWidth,
            proposedHeight: proposedHeight,
            environment: environment
        )
        textSizeCache.store(size, for: key)
        return size
    }

    private func measureText(
        _ text: String,
        whenDisplayedIn widget: Widget,
        proposedWidth: Int?,
        proposedHeight: Int?,
        environment: EnvironmentValues
    ) -> SIMD2<Int> {
        let ellipsize: EllipsizeMode
        if let widget = widget as? CustomLabel {
            ellipsize = widget.ellipsize
        } else if widget as? TextView != nil {
            // We don't ellipsize multi-line text editors
            ellipsize = .none
        } else {
            logger.warning(
                "\(#function) called with unexpected widget type \(type(of: widget))"
            )
            ellipsize = .none
        }

        let pango = Pango(for: widget)
        let (width, height) = pango.getTextSize(
            text,
            ellipsize: proposedHeight == nil ? .none : ellipsize,
            proposedWidth: proposedWidth.map(Double.init),
            proposedHeight: proposedHeight.map(Double.init)
        )

        var imposedHeight = height

        if let lineLimitSettings = environment.lineLimitSettings {
            let multilineString = [String](repeating: "a", count: lineLimitSettings.limit)
                .joined(separator: "\n")
            updateTextView(
                measurementCustomLabel,
                content: "",
                environment: environment
            )

            let pango = Pango(for: measurementCustomLabel)

            let (_, heightLimit) = pango.getTextSize(
                multilineString,
                ellipsize: .none,
                proposedWidth: nil,
                proposedHeight: nil
            )

            if heightLimit < imposedHeight || lineLimitSettings.reservesSpace {
                imposedHeight = heightLimit
            }
        }

        return SIMD2(width, imposedHeight)
    }

    public func createTextView() -> Widget {
        let textView = CustomLabel(string: "")
        textView.horizontalAlignment = .start
        textView.wrap = true
        textView.lineWrapMode = .wordCharacter
        textView.ellipsize = .end
        textView.yalign = 0.0
        return textView
    }

    public func updateTextView(
        _ textView: Widget,
        content: String,
        environment: EnvironmentValues
    ) {
        let textView = textView as! CustomLabel
        textView.label = content
        textView.justify =
            switch environment.multilineTextAlignment {
                case .leading:
                    Justification.left
                case .center:
                    Justification.center
                case .trailing:
                    Justification.right
            }

        textView.selectable = environment.isTextSelectionEnabled
        // One mutation: each change to `css` reloads the widget's CSS provider
        // (and none at all when the style is unchanged).
        textView.css.set(properties: Self.cssProperties(for: environment), clear: true)
    }
}

/// Memoized results of ``GtkBackend/size(of:whenDisplayedIn:proposedWidth:proposedHeight:environment:)``.
///
/// Keys include everything SwiftCrossUI uses to style the measured label. Like
/// the rest of GtkBackend, it doesn't track system font or theme changes
/// (those need a restart to be picked up consistently anyway).
struct TextSizeCache {
    struct LineLimit: Hashable {
        var limit: Int
        var reservesSpace: Bool
    }

    struct Key: Hashable {
        var text: String
        var proposedWidth: Int?
        var proposedHeight: Int?
        var isTextEditor: Bool
        /// The CSS applied to the measured widget, which determines its font.
        var style: [String]
        var lineLimit: LineLimit?
    }

    /// Bounds memory use; text that changes keeps producing new keys.
    static let capacity = 4096

    private(set) var sizes: [Key: SIMD2<Int>] = [:]

    mutating func store(_ size: SIMD2<Int>, for key: Key) {
        if sizes.count >= Self.capacity {
            sizes.removeAll(keepingCapacity: true)
        }
        sizes[key] = size
    }
}
