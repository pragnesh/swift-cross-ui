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
        ///   - cell: The text of the cell at `row`, `column`, or `nil` for a
        ///     null value. Called only for cells being displayed.
        ///   - environment: The current environment.
        func updateDataGrid(
            _ dataGrid: Widget,
            columns: [DataGridColumn],
            rowCount: Int,
            contentRevision: Int,
            cell: @escaping @MainActor (_ row: Int, _ column: Int) -> String?,
            environment: EnvironmentValues
        )
    }
}
