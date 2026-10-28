#ifndef GTK_DATA_GRID_H
#define GTK_DATA_GRID_H

#include <gtk/gtk.h>

G_BEGIN_DECLS

/// Fills a visible cell: called when the row at `row` scrolls into view (or
/// the grid is reloaded). `cell` is recycled between rows, so the callback
/// must set everything it customises.
typedef void (*GtkDataGridBindFunc)(void *context, guint row, guint column, GtkInscription *cell);

/// A virtualized, read-only table: a GtkColumnView in a GtkScrolledWindow
/// whose rows are created lazily, so only visible cells exist and cost
/// anything. Returns the scrolled window.
GtkWidget *gtk_data_grid_new(void);

/// Replaces the columns. `titles` and `widths` (initial widths in pixels;
/// columns stay resizable) have `count` entries. `bind` is called with
/// `context` for every cell that gets displayed.
void gtk_data_grid_set_columns(
    GtkWidget *grid,
    const char *const *titles,
    const int *widths,
    guint count,
    GtkDataGridBindFunc bind,
    void *context
);

/// Sets the number of rows and rebinds every visible cell. With
/// `scroll_to_top`, also scrolls back to the first row.
void gtk_data_grid_reload(GtkWidget *grid, guint row_count, gboolean scroll_to_top);

G_END_DECLS

#endif
