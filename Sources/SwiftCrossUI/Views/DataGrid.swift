/// A column of a ``DataGrid``.
public struct DataGridColumn: Hashable, Sendable {
    /// The column header.
    public var title: String
    /// The column's initial width (the user can resize it).
    public var width: Int

    public init(_ title: String, width: Int = 120) {
        self.title = title
        self.width = width
    }
}

/// A scrolling, virtualized grid of text for large tabular data.
///
/// Unlike ``Table``, cells aren't views: the grid asks for the text of a cell
/// only when that cell is displayed, so the cost of showing it doesn't grow
/// with the number of rows. It takes up all the space it's offered and never
/// measures its contents, so updating it doesn't re-lay-out its surroundings.
public struct DataGrid: ElementaryView {
    private static let idealSize = ViewSize(200, 200)

    var columns: [DataGridColumn]
    var rowCount: Int
    var contentRevision: Int
    var cell: @MainActor (_ row: Int, _ column: Int) -> String?

    /// Creates a data grid.
    ///
    /// - Parameters:
    ///   - columns: The grid's columns.
    ///   - rowCount: The number of rows.
    ///   - contentRevision: Change this whenever the cell contents change
    ///     (e.g. a new query result), so displayed cells are refreshed.
    ///   - cell: The text of the cell at `row`, `column`, or `nil` for a null
    ///     value (displayed dimmed as "NULL").
    public init(
        columns: [DataGridColumn],
        rowCount: Int,
        contentRevision: Int,
        cell: @escaping @MainActor (_ row: Int, _ column: Int) -> String?
    ) {
        self.columns = columns
        self.rowCount = rowCount
        self.contentRevision = contentRevision
        self.cell = cell
    }

    @CastBackend<BackendFeatures.DataGrids>(returnsWidget: true)
    func asWidget<Backend: BaseAppBackend>(backend: Backend) -> Backend.Widget {
        backend.createDataGrid()
    }

    func computeLayout<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        proposedSize: ProposedViewSize,
        environment: EnvironmentValues,
        backend: Backend
    ) -> ViewLayoutResult {
        ViewLayoutResult
            .leafView(size: proposedSize.replacingUnspecifiedDimensions(by: Self.idealSize))
            .with(\.isNeverFocusable, false)
    }

    @CastBackend<BackendFeatures.DataGrids>
    func commit<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        layout: ViewLayoutResult,
        environment: EnvironmentValues,
        backend: Backend
    ) {
        backend.updateDataGrid(
            widget,
            columns: columns,
            rowCount: rowCount,
            contentRevision: contentRevision,
            cell: cell,
            environment: environment
        )
        backend.setSize(of: widget, to: layout.size.vector)
    }
}
