import CGtk
import Gtk
@_spi(Backends) import SwiftCrossUI

extension GtkBackend: BackendFeatures.VerticalSplitViews {
    public func createVerticalSplitView(
        topChild: Widget,
        bottomChild: Widget,
        topHeight: Int
    ) -> Widget {
        let widget = Paned(orientation: .vertical)
        widget.startChild = wrapInCustomRootContainer(topChild)
        widget.endChild = wrapInCustomRootContainer(bottomChild)
        widget.shrinkStartChild = false
        widget.shrinkEndChild = false
        widget.resizeStartChild = false

        widget.position = topHeight
        return widget
    }

    public func setResizeHandler(
        ofVerticalSplitView splitView: Widget,
        to action: @escaping () -> Void
    ) {
        let splitView = splitView as! Paned
        splitView.notifyPosition = { _ in
            action()
        }
    }

    public func topHeight(ofVerticalSplitView splitView: Widget) -> Int {
        let splitView = splitView as! Paned
        return splitView.position
    }

    public func setTopHeightBounds(
        ofVerticalSplitView splitView: Widget,
        minimum minimumHeight: Int,
        maximum maximumHeight: Int
    ) {
        let splitView = splitView as! Paned
        show(widget: splitView.startChild!)
        let height = splitView.getNaturalSize().height
        splitView.startChild?.setSizeRequest(width: 0, height: minimumHeight)
        splitView.endChild?.setSizeRequest(width: 0, height: height - maximumHeight)
    }
}
