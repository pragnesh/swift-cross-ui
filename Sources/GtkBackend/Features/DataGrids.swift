import CGtk
import Gtk
import GtkCHelpers
@_spi(Backends) import SwiftCrossUI

/// Holds a data grid's cell provider so the C bind callback can reach it.
final class DataGridSource {
    var cell: @MainActor (_ row: Int, _ column: Int) -> String? = { _, _ in nil }
}

/// A GtkColumnView-based grid (see `gtk_data_grid.c`).
final class DataGridWidget: Widget {
    let source = DataGridSource()
    var columns: [DataGridColumn] = []
    var rowCount = 0
    var contentRevision: Int?
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

extension GtkBackend: BackendFeatures.DataGrids {
    public func createDataGrid() -> Widget {
        DataGridWidget(gtk_data_grid_new())
    }

    public func updateDataGrid(
        _ dataGrid: Widget,
        columns: [DataGridColumn],
        rowCount: Int,
        contentRevision: Int,
        cell: @escaping @MainActor (_ row: Int, _ column: Int) -> String?,
        environment: EnvironmentValues
    ) {
        let grid = dataGrid as! DataGridWidget
        grid.source.cell = cell

        if columns != grid.columns {
            grid.columns = columns
            let titles = columns.map { strdup($0.title) }
            defer { titles.forEach { free($0) } }
            let widths = columns.map { gint($0.width) }
            titles.map { UnsafePointer($0) }.withUnsafeBufferPointer { titleBuffer in
                widths.withUnsafeBufferPointer { widthBuffer in
                    gtk_data_grid_set_columns(
                        grid.widgetPointer,
                        titleBuffer.baseAddress,
                        widthBuffer.baseAddress,
                        guint(columns.count),
                        bindDataGridCell,
                        // The widget owns the source, so it outlives the columns.
                        Unmanaged.passUnretained(grid.source).toOpaque()
                    )
                }
            }
        }

        if rowCount != grid.rowCount || contentRevision != grid.contentRevision {
            let isNewContent = contentRevision != grid.contentRevision
            grid.rowCount = rowCount
            grid.contentRevision = contentRevision
            gtk_data_grid_reload(grid.widgetPointer, guint(rowCount), isNewContent ? 1 : 0)
        }
    }
}
