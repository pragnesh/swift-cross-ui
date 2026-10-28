#include "gtk_data_grid.h"

// MARK: Row objects

/// A row of the grid; only knows its index.
#define GTK_TYPE_DATA_GRID_ROW (gtk_data_grid_row_get_type())
G_DECLARE_FINAL_TYPE(GtkDataGridRow, gtk_data_grid_row, GTK, DATA_GRID_ROW, GObject)

struct _GtkDataGridRow {
    GObject parent_instance;
    guint index;
};

G_DEFINE_FINAL_TYPE(GtkDataGridRow, gtk_data_grid_row, G_TYPE_OBJECT)

static void gtk_data_grid_row_init(GtkDataGridRow *self) {}
static void gtk_data_grid_row_class_init(GtkDataGridRowClass *klass) {}

// MARK: Lazy row model

/// A GListModel of `n_items` rows whose items are created on demand, so a
/// million-row result costs nothing until rows are displayed.
#define GTK_TYPE_DATA_GRID_ROWS (gtk_data_grid_rows_get_type())
G_DECLARE_FINAL_TYPE(GtkDataGridRows, gtk_data_grid_rows, GTK, DATA_GRID_ROWS, GObject)

struct _GtkDataGridRows {
    GObject parent_instance;
    guint n_items;
};

static GType gtk_data_grid_rows_get_item_type(GListModel *model) {
    return GTK_TYPE_DATA_GRID_ROW;
}

static guint gtk_data_grid_rows_get_n_items(GListModel *model) {
    return GTK_DATA_GRID_ROWS(model)->n_items;
}

static gpointer gtk_data_grid_rows_get_item(GListModel *model, guint position) {
    if (position >= GTK_DATA_GRID_ROWS(model)->n_items) {
        return NULL;
    }
    GtkDataGridRow *row = g_object_new(GTK_TYPE_DATA_GRID_ROW, NULL);
    row->index = position;
    return row;
}

static void gtk_data_grid_rows_list_model_init(GListModelInterface *iface) {
    iface->get_item_type = gtk_data_grid_rows_get_item_type;
    iface->get_n_items = gtk_data_grid_rows_get_n_items;
    iface->get_item = gtk_data_grid_rows_get_item;
}

G_DEFINE_FINAL_TYPE_WITH_CODE(
    GtkDataGridRows, gtk_data_grid_rows, G_TYPE_OBJECT,
    G_IMPLEMENT_INTERFACE(G_TYPE_LIST_MODEL, gtk_data_grid_rows_list_model_init)
)

static void gtk_data_grid_rows_init(GtkDataGridRows *self) {}
static void gtk_data_grid_rows_class_init(GtkDataGridRowsClass *klass) {}

// MARK: Cell factories

typedef struct {
    GtkDataGridBindFunc bind;
    void *context;
    guint column;
} ColumnBinding;

static void setup_cell(GtkSignalListItemFactory *factory, GObject *object, gpointer data) {
    GtkInscription *cell = GTK_INSCRIPTION(gtk_inscription_new(NULL));
    gtk_inscription_set_text_overflow(cell, GTK_INSCRIPTION_OVERFLOW_ELLIPSIZE_END);
    gtk_inscription_set_min_lines(cell, 1);
    gtk_list_item_set_child(GTK_LIST_ITEM(object), GTK_WIDGET(cell));
}

static void bind_cell(GtkSignalListItemFactory *factory, GObject *object, gpointer data) {
    ColumnBinding *binding = data;
    GtkListItem *item = GTK_LIST_ITEM(object);
    GtkDataGridRow *row = gtk_list_item_get_item(item);
    GtkWidget *cell = gtk_list_item_get_child(item);
    if (row == NULL || cell == NULL) {
        return;
    }
    binding->bind(binding->context, row->index, binding->column, GTK_INSCRIPTION(cell));
}

static void free_binding(gpointer data, GClosure *closure) {
    g_free(data);
}

// MARK: Grid

static GtkColumnView *grid_view(GtkWidget *grid) {
    return GTK_COLUMN_VIEW(g_object_get_data(G_OBJECT(grid), "gtk-data-grid-view"));
}

static GtkDataGridRows *grid_rows(GtkWidget *grid) {
    return GTK_DATA_GRID_ROWS(g_object_get_data(G_OBJECT(grid), "gtk-data-grid-rows"));
}

GtkWidget *gtk_data_grid_new(void) {
    GtkDataGridRows *rows = g_object_new(GTK_TYPE_DATA_GRID_ROWS, NULL);

    // Single selection, nothing selected initially. The selection model and
    // the view take ownership of the references passed in.
    GtkSingleSelection *selection = gtk_single_selection_new(G_LIST_MODEL(g_object_ref(rows)));
    gtk_single_selection_set_autoselect(selection, FALSE);
    gtk_single_selection_set_can_unselect(selection, TRUE);

    GtkWidget *view = gtk_column_view_new(GTK_SELECTION_MODEL(selection));
    gtk_column_view_set_show_row_separators(GTK_COLUMN_VIEW(view), TRUE);
    gtk_column_view_set_show_column_separators(GTK_COLUMN_VIEW(view), TRUE);
    gtk_column_view_set_reorderable(GTK_COLUMN_VIEW(view), FALSE);
    gtk_widget_add_css_class(view, "data-table");

    GtkWidget *scrolled = gtk_scrolled_window_new();
    gtk_scrolled_window_set_child(GTK_SCROLLED_WINDOW(scrolled), view);

    g_object_set_data(G_OBJECT(scrolled), "gtk-data-grid-view", view);
    // The scrolled window keeps the row model alive.
    g_object_set_data_full(G_OBJECT(scrolled), "gtk-data-grid-rows", rows, g_object_unref);
    return scrolled;
}

void gtk_data_grid_set_columns(
    GtkWidget *grid,
    const char *const *titles,
    const int *widths,
    guint count,
    GtkDataGridBindFunc bind,
    void *context
) {
    GtkColumnView *view = grid_view(grid);

    GListModel *columns = gtk_column_view_get_columns(view);
    while (g_list_model_get_n_items(columns) > 0) {
        GtkColumnViewColumn *column = g_list_model_get_item(columns, 0);
        gtk_column_view_remove_column(view, column);
        g_object_unref(column);
    }

    for (guint index = 0; index < count; index++) {
        ColumnBinding *binding = g_new(ColumnBinding, 1);
        binding->bind = bind;
        binding->context = context;
        binding->column = index;

        GtkListItemFactory *factory = gtk_signal_list_item_factory_new();
        g_signal_connect(factory, "setup", G_CALLBACK(setup_cell), NULL);
        g_signal_connect_data(
            factory, "bind", G_CALLBACK(bind_cell), binding, free_binding, 0);

        // The column takes ownership of the factory.
        GtkColumnViewColumn *column = gtk_column_view_column_new(titles[index], factory);
        gtk_column_view_column_set_resizable(column, TRUE);
        gtk_column_view_column_set_fixed_width(column, widths[index]);
        gtk_column_view_append_column(view, column);
        g_object_unref(column);
    }

    // An empty column that takes up the leftover width. Without it GTK gives
    // that space to the last real column, which then can't be resized.
    GtkListItemFactory *filler_factory = gtk_signal_list_item_factory_new();
    GtkColumnViewColumn *filler = gtk_column_view_column_new(NULL, filler_factory);
    gtk_column_view_column_set_expand(filler, TRUE);
    gtk_column_view_column_set_resizable(filler, FALSE);
    gtk_column_view_append_column(view, filler);
    g_object_unref(filler);
}

void gtk_data_grid_reload(GtkWidget *grid, guint row_count, gboolean scroll_to_top) {
    GtkDataGridRows *rows = grid_rows(grid);
    guint previous = rows->n_items;
    rows->n_items = row_count;
    // Replacing every item rebinds all visible cells.
    g_list_model_items_changed(G_LIST_MODEL(rows), 0, previous, row_count);

    if (scroll_to_top) {
        GtkAdjustment *vertical =
            gtk_scrolled_window_get_vadjustment(GTK_SCROLLED_WINDOW(grid));
        gtk_adjustment_set_value(vertical, gtk_adjustment_get_lower(vertical));
        GtkAdjustment *horizontal =
            gtk_scrolled_window_get_hadjustment(GTK_SCROLLED_WINDOW(grid));
        gtk_adjustment_set_value(horizontal, gtk_adjustment_get_lower(horizontal));
    }
}
