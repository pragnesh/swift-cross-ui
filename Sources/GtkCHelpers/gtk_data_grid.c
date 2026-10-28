#include "gtk_data_grid.h"

#include <stdlib.h>

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
    float xalign;
    GtkWidget *grid;
} ColumnBinding;

static void cell_right_clicked(GtkGestureClick *gesture, gint n_press, gdouble x, gdouble y, gpointer data);

static void setup_cell(GtkSignalListItemFactory *factory, GObject *object, gpointer data) {
    ColumnBinding *binding = data;
    GtkInscription *cell = GTK_INSCRIPTION(gtk_inscription_new(NULL));
    gtk_inscription_set_xalign(cell, binding->xalign);
    gtk_inscription_set_text_overflow(cell, GTK_INSCRIPTION_OVERFLOW_ELLIPSIZE_END);
    gtk_inscription_set_min_lines(cell, 1);

    GtkGesture *right_click = gtk_gesture_click_new();
    gtk_gesture_single_set_button(GTK_GESTURE_SINGLE(right_click), GDK_BUTTON_SECONDARY);
    g_signal_connect(right_click, "pressed", G_CALLBACK(cell_right_clicked), binding);
    gtk_widget_add_controller(GTK_WIDGET(cell), GTK_EVENT_CONTROLLER(right_click));

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
    // Remember the row for the right-click menu (cells are recycled).
    g_object_set_data(G_OBJECT(cell), "gtk-data-grid-row", GUINT_TO_POINTER(row->index + 1));
    binding->bind(binding->context, row->index, binding->column, GTK_INSCRIPTION(cell));
}

static void free_binding(gpointer data, GClosure *closure) {
    g_free(data);
}

// MARK: Grid

typedef struct {
    GtkDataGridCopyFunc copy;
    void *context;
    GMenu *menu;
    /// The cell the menu was opened on.
    gint menu_column;
} CopyState;

static void copy_state_free(gpointer data) {
    CopyState *state = data;
    g_clear_object(&state->menu);
    g_free(state);
}

typedef struct {
    GtkDataGridSortFunc sort;
    void *context;
    /// Set while the app applies a sort, so it isn't reported back.
    gboolean applying;
} SortState;

static GtkColumnView *grid_view(GtkWidget *grid) {
    return GTK_COLUMN_VIEW(g_object_get_data(G_OBJECT(grid), "gtk-data-grid-view"));
}

static GtkDataGridRows *grid_rows(GtkWidget *grid) {
    return GTK_DATA_GRID_ROWS(g_object_get_data(G_OBJECT(grid), "gtk-data-grid-rows"));
}

static GtkSelectionModel *grid_selection(GtkWidget *grid) {
    return gtk_column_view_get_model(grid_view(grid));
}

/// Runs a copy command on the selected rows and puts the text on the
/// clipboard.
static void grid_copy(GtkWidget *grid, gint command, gint column) {
    CopyState *state = g_object_get_data(G_OBJECT(grid), "gtk-data-grid-copy");
    if (state == NULL || state->copy == NULL) {
        return;
    }
    GtkBitset *selected = gtk_selection_model_get_selection(grid_selection(grid));
    guint count = (guint)gtk_bitset_get_size(selected);
    guint *rows = g_new(guint, count > 0 ? count : 1);
    GtkBitsetIter iter;
    guint value;
    guint index = 0;
    if (gtk_bitset_iter_init_first(&iter, selected, &value)) {
        do {
            rows[index++] = value;
        } while (index < count && gtk_bitset_iter_next(&iter, &value));
    }
    gtk_bitset_unref(selected);

    char *text = count > 0 ? state->copy(state->context, command, rows, count, column) : NULL;
    g_free(rows);
    if (text != NULL) {
        gdk_clipboard_set_text(gtk_widget_get_clipboard(grid), text);
        free(text);
    }
}

static void copy_action_activated(GSimpleAction *action, GVariant *parameter, gpointer data) {
    GtkWidget *grid = data;
    CopyState *state = g_object_get_data(G_OBJECT(grid), "gtk-data-grid-copy");
    if (state != NULL) {
        grid_copy(grid, g_variant_get_int32(parameter), state->menu_column);
    }
}

static gboolean copy_shortcut(GtkWidget *widget, GVariant *args, gpointer data) {
    grid_copy(GTK_WIDGET(data), -1, -1);
    return TRUE;
}

static void popover_closed(GtkPopover *popover, gpointer data) {
    // Unparent after the menu's action has run.
    g_idle_add_once((GSourceOnceFunc)gtk_widget_unparent, popover);
}

static void cell_right_clicked(GtkGestureClick *gesture, gint n_press, gdouble x, gdouble y, gpointer data) {
    ColumnBinding *binding = data;
    GtkWidget *grid = binding->grid;
    CopyState *state = g_object_get_data(G_OBJECT(grid), "gtk-data-grid-copy");
    GtkWidget *cell = gtk_event_controller_get_widget(GTK_EVENT_CONTROLLER(gesture));
    guint row = GPOINTER_TO_UINT(g_object_get_data(G_OBJECT(cell), "gtk-data-grid-row"));
    if (state == NULL || state->menu == NULL || row == 0) {
        return;
    }
    gtk_gesture_set_state(GTK_GESTURE(gesture), GTK_EVENT_SEQUENCE_CLAIMED);

    // Right-clicking outside the selection selects just that row.
    GtkSelectionModel *selection = grid_selection(grid);
    if (!gtk_selection_model_is_selected(selection, row - 1)) {
        gtk_selection_model_select_item(selection, row - 1, TRUE);
    }
    state->menu_column = (gint)binding->column;

    GtkWidget *popover = gtk_popover_menu_new_from_model(G_MENU_MODEL(state->menu));
    gtk_widget_set_parent(popover, cell);
    gtk_popover_set_has_arrow(GTK_POPOVER(popover), FALSE);
    GdkRectangle point = { (int)x, (int)y, 1, 1 };
    gtk_popover_set_pointing_to(GTK_POPOVER(popover), &point);
    g_signal_connect(popover, "closed", G_CALLBACK(popover_closed), NULL);
    gtk_popover_popup(GTK_POPOVER(popover));
}

void gtk_data_grid_enable_copy(
    GtkWidget *grid,
    const char *const *titles,
    guint count,
    GtkDataGridCopyFunc copy,
    void *context
) {
    CopyState *state = g_object_get_data(G_OBJECT(grid), "gtk-data-grid-copy");
    if (state == NULL) {
        state = g_new0(CopyState, 1);
        g_object_set_data_full(G_OBJECT(grid), "gtk-data-grid-copy", state, copy_state_free);

        GSimpleActionGroup *actions = g_simple_action_group_new();
        GSimpleAction *action = g_simple_action_new("copy", G_VARIANT_TYPE_INT32);
        g_signal_connect(action, "activate", G_CALLBACK(copy_action_activated), grid);
        g_action_map_add_action(G_ACTION_MAP(actions), G_ACTION(action));
        g_object_unref(action);
        gtk_widget_insert_action_group(grid, "datagrid", G_ACTION_GROUP(actions));
        g_object_unref(actions);

        GtkEventController *shortcuts = gtk_shortcut_controller_new();
        gtk_shortcut_controller_add_shortcut(
            GTK_SHORTCUT_CONTROLLER(shortcuts),
            gtk_shortcut_new(
                gtk_keyval_trigger_new(GDK_KEY_c, GDK_CONTROL_MASK),
                gtk_callback_action_new(copy_shortcut, grid, NULL)));
        gtk_widget_add_controller(grid, shortcuts);
    }
    state->copy = copy;
    state->context = context;

    g_clear_object(&state->menu);
    state->menu = g_menu_new();
    for (guint index = 0; index < count; index++) {
        GMenuItem *item = g_menu_item_new(titles[index], NULL);
        g_menu_item_set_action_and_target_value(
            item, "datagrid.copy", g_variant_new_int32((gint32)index));
        g_menu_append_item(state->menu, item);
        g_object_unref(item);
    }
}

GtkWidget *gtk_data_grid_new(void) {
    GtkDataGridRows *rows = g_object_new(GTK_TYPE_DATA_GRID_ROWS, NULL);

    // Rows can be selected (Shift/Ctrl-click) for copying. The selection
    // model and the view take ownership of the references passed in.
    GtkMultiSelection *selection = gtk_multi_selection_new(G_LIST_MODEL(g_object_ref(rows)));

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
    const float *xaligns,
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
        binding->xalign = xaligns[index];
        binding->grid = grid;

        // Both handlers share the binding; the "bind" connection frees it.
        GtkListItemFactory *factory = gtk_signal_list_item_factory_new();
        g_signal_connect(factory, "setup", G_CALLBACK(setup_cell), binding);
        g_signal_connect_data(
            factory, "bind", G_CALLBACK(bind_cell), binding, free_binding, 0);

        // The column takes ownership of the factory.
        GtkColumnViewColumn *column = gtk_column_view_column_new(titles[index], factory);
        gtk_column_view_column_set_resizable(column, TRUE);
        gtk_column_view_column_set_fixed_width(column, widths[index]);
        g_object_set_data(G_OBJECT(column), "gtk-data-grid-column", GUINT_TO_POINTER(index + 1));
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

static void sorter_changed(GtkSorter *sorter, GtkSorterChange change, gpointer data) {
    SortState *state = data;
    if (state->applying || state->sort == NULL) {
        return;
    }
    GtkColumnViewSorter *view_sorter = GTK_COLUMN_VIEW_SORTER(sorter);
    GtkColumnViewColumn *column = gtk_column_view_sorter_get_primary_sort_column(view_sorter);
    if (column == NULL) {
        return;
    }
    guint index = GPOINTER_TO_UINT(g_object_get_data(G_OBJECT(column), "gtk-data-grid-column"));
    if (index == 0) {
        return;  // the filler column
    }
    GtkSortType order = gtk_column_view_sorter_get_primary_sort_order(view_sorter);
    state->sort(state->context, index - 1, order == GTK_SORT_ASCENDING);
}

static SortState *grid_sort_state(GtkWidget *grid) {
    SortState *state = g_object_get_data(G_OBJECT(grid), "gtk-data-grid-sort");
    if (state == NULL) {
        state = g_new0(SortState, 1);
        g_object_set_data_full(G_OBJECT(grid), "gtk-data-grid-sort", state, g_free);
        GtkSorter *sorter = gtk_column_view_get_sorter(grid_view(grid));
        g_signal_connect(sorter, "changed", G_CALLBACK(sorter_changed), state);
    }
    return state;
}

void gtk_data_grid_enable_sorting(GtkWidget *grid, GtkDataGridSortFunc sort, void *context) {
    SortState *state = grid_sort_state(grid);
    state->sort = sort;
    state->context = context;

    // A sorter that keeps every row where it is: it only makes the header
    // clickable and shows the indicator. The app does the actual sorting.
    GListModel *columns = gtk_column_view_get_columns(grid_view(grid));
    for (guint index = 0; index < g_list_model_get_n_items(columns); index++) {
        GtkColumnViewColumn *column = g_list_model_get_item(columns, index);
        if (g_object_get_data(G_OBJECT(column), "gtk-data-grid-column") != NULL) {
            GtkCustomSorter *sorter = gtk_custom_sorter_new(NULL, NULL, NULL);
            gtk_column_view_column_set_sorter(column, GTK_SORTER(sorter));
            g_object_unref(sorter);
        }
        g_object_unref(column);
    }
}

void gtk_data_grid_show_sort(GtkWidget *grid, gint column, gboolean ascending) {
    SortState *state = grid_sort_state(grid);
    GtkColumnView *view = grid_view(grid);
    GtkColumnViewColumn *target = NULL;
    if (column >= 0) {
        target = g_list_model_get_item(gtk_column_view_get_columns(view), (guint)column);
    }
    state->applying = TRUE;
    gtk_column_view_sort_by_column(
        view, target, ascending ? GTK_SORT_ASCENDING : GTK_SORT_DESCENDING);
    state->applying = FALSE;
    if (target != NULL) {
        g_object_unref(target);
    }
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
