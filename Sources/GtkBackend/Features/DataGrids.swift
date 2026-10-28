import CGtk
import Gtk
import GtkCHelpers
@_spi(Backends) import SwiftCrossUI

/// Holds a data grid's cell provider so the C bind callback can reach it.
final class DataGridSource {
    var cell: @MainActor (_ row: Int, _ column: Int) -> String? = { _, _ in nil }
    var onSort: (@MainActor (DataGridSort) -> Void)?
    var onCopy: (@MainActor (DataGridCopyRequest) -> String?)?
}

/// A GtkColumnView-based grid (see `gtk_data_grid.c`).
final class DataGridWidget: Widget {
    let source = DataGridSource()
    var columns: [DataGridColumn] = []
    var rowCount = 0
    var contentRevision: Int?
    var isSortable = false
    var sort: DataGridSort?
    var copyCommands: [String]?
}

/// Fills a cell as it's displayed. Cells are recycled, so the null styling
/// is set or cleared every time.
private let bindDataGridCell: GtkDataGridBindFunc = { context, row, column, cell in
    MainActor.assumeIsolated {
        guard let context, let cell else { return }
        let source = Unmanaged<DataGridSource>.fromOpaque(context).takeUnretainedValue()
        let text = source.cell(Int(row), Int(column))
        gtk_inscription_set_text(cell, text ?? "NULL")
        let widget = UnsafeMutablePointer<GtkWidget>(cell)
        if text == nil {
            gtk_widget_add_css_class(widget, "dim-label")
        } else {
            gtk_widget_remove_css_class(widget, "dim-label")
        }
    }
}

/// Reports a header click to the grid's sort handler.
private let sortDataGrid: GtkDataGridSortFunc = { context, column, ascending in
    MainActor.assumeIsolated {
        guard let context else { return }
        let source = Unmanaged<DataGridSource>.fromOpaque(context).takeUnretainedValue()
        source.onSort?(DataGridSort(column: Int(column), ascending: ascending != 0))
    }
}

/// Asks the grid's copy handler for the text to copy (malloc'd for C).
private let copyFromDataGrid: GtkDataGridCopyFunc = { context, command, rows, rowCount, column in
    MainActor.assumeIsolated {
        guard let context else { return nil }
        let source = Unmanaged<DataGridSource>.fromOpaque(context).takeUnretainedValue()
        let request = DataGridCopyRequest(
            command: command >= 0 ? Int(command) : nil,
            rows: (0..<Int(rowCount)).map { Int(rows![$0]) },
            column: column >= 0 ? Int(column) : nil
        )
        return source.onCopy?(request).flatMap { strdup($0) }
    }
}

extension GtkBackend: BackendFeatures.DataGrids {
    public func createDataGrid() -> Widget {
        DataGridWidget(gtk_data_grid_new())
    }

    public func updateDataGrid(
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
    ) {
        let grid = dataGrid as! DataGridWidget
        grid.source.cell = cell
        grid.source.onSort = onSort
        grid.source.onCopy = onCopy

        let isSortable = onSort != nil
        if columns != grid.columns || isSortable != grid.isSortable {
            grid.columns = columns
            grid.isSortable = isSortable
            grid.sort = nil
            let titles = columns.map { strdup($0.title) }
            defer { titles.forEach { free($0) } }
            let widths = columns.map { gint($0.width) }
            let xaligns: [Float] = columns.map {
                switch $0.alignment {
                    case .leading: 0
                    case .center: 0.5
                    case .trailing: 1
                }
            }
            titles.map { UnsafePointer($0) }.withUnsafeBufferPointer { titleBuffer in
                widths.withUnsafeBufferPointer { widthBuffer in
                    xaligns.withUnsafeBufferPointer { xalignBuffer in
                        gtk_data_grid_set_columns(
                            grid.widgetPointer,
                            titleBuffer.baseAddress,
                            widthBuffer.baseAddress,
                            xalignBuffer.baseAddress,
                            guint(columns.count),
                            bindDataGridCell,
                            // The widget owns the source, so it outlives the columns.
                            Unmanaged.passUnretained(grid.source).toOpaque()
                        )
                    }
                }
            }
            if isSortable {
                gtk_data_grid_enable_sorting(
                    grid.widgetPointer, sortDataGrid,
                    Unmanaged.passUnretained(grid.source).toOpaque())
            }
        }

        if onCopy != nil && copyCommands != grid.copyCommands {
            grid.copyCommands = copyCommands
            let titles = copyCommands.map { strdup($0) }
            defer { titles.forEach { free($0) } }
            titles.map { UnsafePointer($0) }.withUnsafeBufferPointer { titleBuffer in
                gtk_data_grid_enable_copy(
                    grid.widgetPointer, titleBuffer.baseAddress, guint(copyCommands.count),
                    copyFromDataGrid, Unmanaged.passUnretained(grid.source).toOpaque())
            }
        }

        if isSortable && sort != grid.sort {
            grid.sort = sort
            gtk_data_grid_show_sort(
                grid.widgetPointer, gint(sort?.column ?? -1), (sort?.ascending ?? true) ? 1 : 0)
        }

        if rowCount != grid.rowCount || contentRevision != grid.contentRevision {
            let isNewContent = contentRevision != grid.contentRevision
            grid.rowCount = rowCount
            grid.contentRevision = contentRevision
            gtk_data_grid_reload(grid.widgetPointer, guint(rowCount), isNewContent ? 1 : 0)
        }
    }
}
