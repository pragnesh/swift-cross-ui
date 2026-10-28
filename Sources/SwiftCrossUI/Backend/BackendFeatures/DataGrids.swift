extension BackendFeatures {
    /// Backend methods for virtualized, read-only data grids.
    ///
    /// These are used by ``DataGrid``.
    @MainActor
    public protocol DataGrids: Core {
        /// Creates an empty data grid. It scrolls by itself and should create
        /// widgets only for the cells that are visible.
        func createDataGrid() -> Widget

        /// Updates a data grid.
        ///
        /// - Parameters:
        ///   - dataGrid: The grid to update.
        ///   - columns: The grid's columns. When they change, the grid's
        ///     columns are rebuilt.
        ///   - rowCount: The number of rows.
        ///   - contentRevision: Changes whenever the cell contents change;
        ///     the backend then redisplays every visible cell and scrolls
        ///     back to the top.
        ///   - sort: The order to show in the column headers.
        ///   - onSort: Called when the user clicks a header to sort; `nil`
        ///     means the headers aren't clickable.
        ///   - copyCommands: Titles for a cell's right-click menu.
        ///   - onCopy: The text to copy for a command or the copy shortcut
        ///     applied to the selected rows; `nil` disables copying.
        ///   - cell: The text of the cell at `row`, `column`, or `nil` for a
        ///     null value. Called only for cells being displayed.
        ///   - environment: The current environment.
        func updateDataGrid(
            _ dataGrid: Widget,
            columns: [DataGridColumn],
            rowCount: Int,
            contentRevision: Int,
            sort: DataGridSort?,
            onSort: (@MainActor (DataGridSort) -> Void)?,
            copyCommands: [String],
            onCopy: (@MainActor (DataGridCopyRequest) -> String?)?,
            cell: @escaping @MainActor (_ row: Int, _ column: Int) -> String?,
            environment: EnvironmentValues
        )
    }
}
