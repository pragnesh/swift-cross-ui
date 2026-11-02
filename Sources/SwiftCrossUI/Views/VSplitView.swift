/// Two views stacked vertically with a divider the user can drag.
///
/// The top view keeps its height when the split view is resized; the bottom
/// view takes the rest. Neither pane shrinks below its minimum height.
public struct VSplitView<Top: View, Bottom: View>: TypeSafeView, View {
    typealias Children = VSplitViewChildren<Top, Bottom>

    public var body: TupleView2<Top, Bottom>

    /// The top pane's height when the split view is created.
    private var initialTopHeight: Int

    /// Creates a vertical split view.
    ///
    /// - Parameters:
    ///   - topHeight: The top pane's initial height.
    ///   - top: The content above the divider.
    ///   - bottom: The content below the divider.
    public init(
        topHeight: Int = 200,
        @ViewBuilder top: () -> Top,
        @ViewBuilder bottom: () -> Bottom
    ) {
        body = TupleView2(top(), bottom())
        initialTopHeight = topHeight
    }

    func children<Backend: BaseAppBackend>(
        backend: Backend,
        snapshots: [ViewGraphSnapshotter.NodeSnapshot]?,
        environment: EnvironmentValues
    ) -> Children {
        VSplitViewChildren(
            wrapping: body.children(
                backend: backend,
                snapshots: snapshots,
                environment: environment
            ),
            backend: backend
        )
    }

    @CastBackend<BackendFeatures.VerticalSplitViews>(returnsWidget: true)
    func asWidget<Backend: BaseAppBackend>(
        _ children: Children,
        backend: Backend
    ) -> Backend.Widget {
        backend.createVerticalSplitView(
            topChild: children.topPaneContainer.into(),
            bottomChild: children.bottomPaneContainer.into(),
            topHeight: initialTopHeight
        )
    }

    @CastBackend<BackendFeatures.VerticalSplitViews>
    func computeLayout<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        children: Children,
        proposedSize: ProposedViewSize,
        environment: EnvironmentValues,
        backend: Backend
    ) -> ViewLayoutResult {
        let topHeight = Double(backend.topHeight(ofVerticalSplitView: widget))

        children.minimumTopHeight =
            children.topChild.computeLayout(
                with: body.view0,
                proposedSize: ProposedViewSize(proposedSize.width, 0),
                environment: environment
            ).size.height
        children.minimumBottomHeight =
            children.bottomChild.computeLayout(
                with: body.view1,
                proposedSize: ProposedViewSize(proposedSize.width, 0),
                environment: environment
            ).size.height

        let topResult = children.topChild.computeLayout(
            with: body.view0,
            proposedSize: ProposedViewSize(
                proposedSize.width,
                proposedSize.height == nil ? nil : topHeight
            ),
            environment: environment
        )
        let bottomResult = children.bottomChild.computeLayout(
            with: body.view1,
            proposedSize: ProposedViewSize(
                proposedSize.width,
                proposedSize.height.map { $0 - max(topHeight, topResult.size.height) }
            ),
            environment: environment
        )

        var size = ViewSize(
            max(topResult.size.width, bottomResult.size.width),
            topResult.size.height + bottomResult.size.height
        )
        if let proposedWidth = proposedSize.width {
            size.width = max(size.width, proposedWidth)
        }
        if let proposedHeight = proposedSize.height {
            size.height = max(size.height, proposedHeight)
        }

        return ViewLayoutResult(
            size: size,
            childResults: [topResult, bottomResult]
        )
    }

    @CastBackend<BackendFeatures.VerticalSplitViews>
    func commit<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        children: Children,
        layout: ViewLayoutResult,
        environment: EnvironmentValues,
        backend: Backend
    ) {
        backend.setResizeHandler(ofVerticalSplitView: widget) {
            environment.onResize(.zero)
        }

        let topHeight = backend.topHeight(ofVerticalSplitView: widget)
        let topResult = children.topChild.commit()
        let bottomResult = children.bottomChild.commit()

        backend.setSize(of: widget, to: layout.size.vector)
        backend.setTopHeightBounds(
            ofVerticalSplitView: widget,
            minimum: LayoutSystem.roundSize(children.minimumTopHeight),
            maximum: LayoutSystem.roundSize(
                max(
                    children.minimumTopHeight,
                    layout.size.height - children.minimumBottomHeight
                )
            )
        )

        // Center pane children
        backend.setPosition(
            ofChildAt: 0,
            in: children.topPaneContainer.into(),
            to: SIMD2(
                layout.size.vector.x - topResult.size.vector.x,
                topHeight - topResult.size.vector.y
            ) / 2
        )
        backend.setPosition(
            ofChildAt: 0,
            in: children.bottomPaneContainer.into(),
            to: SIMD2(
                layout.size.vector.x - bottomResult.size.vector.x,
                layout.size.vector.y - topHeight - bottomResult.size.vector.y
            ) / 2
        )
    }
}

class VSplitViewChildren<Top: View, Bottom: View>: ViewGraphNodeChildren {
    var paneChildren: TupleView2<Top, Bottom>.Children
    var topPaneContainer: AnyWidget
    var bottomPaneContainer: AnyWidget
    var minimumTopHeight: Double = 0
    var minimumBottomHeight: Double = 0

    init<Backend: BaseAppBackend>(
        wrapping children: TupleView2<Top, Bottom>.Children,
        backend: Backend
    ) {
        self.paneChildren = children

        let topPaneContainer = backend.createContainer()
        backend.insert(paneChildren.child0.widget.into(), into: topPaneContainer, at: 0)
        let bottomPaneContainer = backend.createContainer()
        backend.insert(paneChildren.child1.widget.into(), into: bottomPaneContainer, at: 0)

        self.topPaneContainer = AnyWidget(topPaneContainer)
        self.bottomPaneContainer = AnyWidget(bottomPaneContainer)
    }

    var erasedNodes: [ErasedViewGraphNode] {
        paneChildren.erasedNodes
    }

    var widgets: [AnyWidget] {
        [topPaneContainer, bottomPaneContainer]
    }

    var topChild: AnyViewGraphNode<Top> {
        paneChildren.child0
    }

    var bottomChild: AnyViewGraphNode<Bottom> {
        paneChildren.child1
    }
}
