/// A column of a ``DataGrid``.
public struct DataGridColumn: Hashable, Sendable {
    /// The column header.
    public var title: String
    /// The column's initial width (the user can resize it).
    public var width: Int
    /// How cell text is aligned (e.g. `.trailing` for numbers).
    public var alignment: HorizontalAlignment

    public init(_ title: String, width: Int = 120, alignment: HorizontalAlignment = .leading) {
        self.title = title
        self.width = width
        self.alignment = alignment
    }
}

/// The order a ``DataGrid`` is sorted by.
public struct DataGridSort: Hashable, Sendable {
    public var column: Int
    public var ascending: Bool

    public init(column: Int, ascending: Bool) {
        self.column = column
        self.ascending = ascending
    }
}

/// What a ``DataGrid`` asks to copy.
public struct DataGridCopyRequest: Hashable, Sendable {
    /// The index into the grid's copy commands, or `nil` for the keyboard
    /// shortcut (Ctrl+C).
    public var command: Int?
    /// The selected rows, ascending.
    public var rows: [Int]
    /// The column that was right-clicked (`nil` for the keyboard shortcut).
    public var column: Int?

    public init(command: Int?, rows: [Int], column: Int?) {
        self.command = command
        self.rows = rows
        self.column = column
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
    var sort: DataGridSort?
    var onSort: (@MainActor (DataGridSort) -> Void)?
    var copyCommands: [String]
    var onCopy: (@MainActor (DataGridCopyRequest) -> String?)?
    var cell: @MainActor (_ row: Int, _ column: Int) -> String?

    /// Creates a data grid.
    ///
    /// - Parameters:
    ///   - columns: The grid's columns.
    ///   - rowCount: The number of rows.
    ///   - contentRevision: Change this whenever the cell contents change
    ///     (e.g. a new query result), so displayed cells are refreshed.
    ///   - sort: The order the rows are in, shown in the column headers.
    ///   - onSort: Called when the user clicks a column header to sort. The
    ///     grid doesn't reorder rows itself: provide sorted content (and the
    ///     new `sort`). Headers aren't clickable without it.
    ///   - copyCommands: Titles for the cells' right-click menu.
    ///   - onCopy: Returns the text to put on the clipboard for a copy
    ///     command (or Ctrl+C) applied to the selected rows. Rows can be
    ///     selected with Shift/Ctrl-click; without `onCopy` nothing is copied.
    ///   - cell: The text of the cell at `row`, `column`, or `nil` for a null
    ///     value (displayed dimmed as "NULL").
    public init(
        columns: [DataGridColumn],
        rowCount: Int,
        contentRevision: Int,
        sort: DataGridSort? = nil,
        onSort: (@MainActor (DataGridSort) -> Void)? = nil,
        copyCommands: [String] = [],
        onCopy: (@MainActor (DataGridCopyRequest) -> String?)? = nil,
        cell: @escaping @MainActor (_ row: Int, _ column: Int) -> String?
    ) {
        self.columns = columns
        self.rowCount = rowCount
        self.contentRevision = contentRevision
        self.sort = sort
        self.onSort = onSort
        self.copyCommands = copyCommands
        self.onCopy = onCopy
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
            sort: sort,
            onSort: onSort,
            copyCommands: copyCommands,
            onCopy: onCopy,
            cell: cell,
            environment: environment
        )
        backend.setSize(of: widget, to: layout.size.vector)
    }
}
