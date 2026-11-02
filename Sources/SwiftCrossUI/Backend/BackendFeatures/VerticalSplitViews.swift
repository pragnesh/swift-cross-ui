extension BackendFeatures {
    /// Backend methods for vertical split views.
    ///
    /// These are used by ``VSplitView``.
    @MainActor
    public protocol VerticalSplitViews: Core {
        /// Creates a split view with one child above the other and a draggable
        /// divider between them. The top child keeps its height when the
        /// split view is resized; the bottom child takes the difference.
        ///
        /// - Parameters:
        ///   - topChild: The widget to show above the divider.
        ///   - bottomChild: The widget to show below the divider.
        ///   - topHeight: The top child's initial height.
        func createVerticalSplitView(
            topChild: Widget,
            bottomChild: Widget,
            topHeight: Int
        ) -> Widget

        /// Sets the function to be called when the divider moves.
        ///
        /// - Parameters:
        ///   - splitView: The split view.
        ///   - action: The action to perform when the panes are resized.
        func setResizeHandler(
            ofVerticalSplitView splitView: Widget,
            to action: @escaping () -> Void
        )

        /// Gets the height of a vertical split view's top pane.
        ///
        /// - Parameter splitView: The split view.
        /// - Returns: The top pane's height.
        func topHeight(ofVerticalSplitView splitView: Widget) -> Int

        /// Sets the minimum and maximum height of a vertical split view's top
        /// pane.
        ///
        /// - Parameters:
        ///   - splitView: The split view.
        ///   - minimumHeight: The minimum height of the top pane.
        ///   - maximumHeight: The maximum height of the top pane.
        func setTopHeightBounds(
            ofVerticalSplitView splitView: Widget,
            minimum minimumHeight: Int,
            maximum maximumHeight: Int
        )
    }
}
