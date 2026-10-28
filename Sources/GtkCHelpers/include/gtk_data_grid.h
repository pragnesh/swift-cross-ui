#ifndef GTK_DATA_GRID_H
#define GTK_DATA_GRID_H

#include <gtk/gtk.h>

G_BEGIN_DECLS

/// Fills a visible cell: called when the row at `row` scrolls into view (or
/// the grid is reloaded). `cell` is recycled between rows, so the callback
/// must set everything it customises.
typedef void (*GtkDataGridBindFunc)(void *context, guint row, guint column, GtkInscription *cell);

/// Called when the user clicks a column header to sort: `column` and
/// `ascending` describe the requested order. The grid doesn't reorder rows
/// itself; it only shows the indicator.
typedef void (*GtkDataGridSortFunc)(void *context, guint column, gboolean ascending);

/// Returns the text to copy (malloc'd; the grid frees it) for copy command
/// `command` (-1 for the Ctrl+C shortcut) applied to `rows` (the selected
/// rows, ascending) and `column` (the right-clicked column, or -1).
typedef char *(*GtkDataGridCopyFunc)(
    void *context, gint command, const guint *rows, guint row_count, gint column);

/// A virtualized, read-only table: a GtkColumnView in a GtkScrolledWindow
/// whose rows are created lazily, so only visible cells exist and cost
/// anything. Returns the scrolled window.
GtkWidget *gtk_data_grid_new(void);

/// Replaces the columns. `titles`, `widths` (initial widths in pixels;
/// columns stay resizable) and `xaligns` (0 = left … 1 = right) have `count`
/// entries. `bind` is called with `context` for every cell that gets
/// displayed.
void gtk_data_grid_set_columns(
    GtkWidget *grid,
    const char *const *titles,
    const int *widths,
    const float *xaligns,
    guint count,
    GtkDataGridBindFunc bind,
    void *context
);

/// Makes column headers clickable for sorting; `sort` is called with
/// `context` when the user picks an order. Applies to the current columns,
/// so call it after `gtk_data_grid_set_columns`.
void gtk_data_grid_enable_sorting(GtkWidget *grid, GtkDataGridSortFunc sort, void *context);

/// Shows `column` (or no column, with -1) as the sorted one without calling
/// the sort function.
void gtk_data_grid_show_sort(GtkWidget *grid, gint column, gboolean ascending);

/// Enables copying: Ctrl+C copies the selected rows (command -1), and
/// right-clicking a cell offers `titles` as a menu. `copy` provides the text.
void gtk_data_grid_enable_copy(
    GtkWidget *grid,
    const char *const *titles,
    guint count,
    GtkDataGridCopyFunc copy,
    void *context
);

/// Sets the number of rows and rebinds every visible cell. With
/// `scroll_to_top`, also scrolls back to the first row.
void gtk_data_grid_reload(GtkWidget *grid, guint row_count, gboolean scroll_to_top);

G_END_DECLS

#endif
