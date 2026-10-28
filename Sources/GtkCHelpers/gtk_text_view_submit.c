#include "gtk_text_view_submit.h"

typedef struct {
    GtkTextViewSubmitFunc submit;
    void *context;
    GDestroyNotify destroy;
} SubmitHandler;

static void submit_handler_free(gpointer data) {
    SubmitHandler *handler = data;
    if (handler->destroy != NULL) {
        handler->destroy(handler->context);
    }
    g_free(handler);
}

static gboolean submit_shortcut(GtkWidget *widget, GVariant *args, gpointer data) {
    SubmitHandler *handler = data;
    handler->submit(handler->context);
    return TRUE;
}

void gtk_text_view_set_submit_handler(
    GtkTextView *view,
    GtkTextViewSubmitFunc submit,
    void *context,
    GDestroyNotify destroy
) {
    GtkEventController *previous = g_object_get_data(G_OBJECT(view), "gtk-text-view-submit");
    if (previous != NULL) {
        // Frees the previous handler (via the callback action's destroy notify).
        gtk_widget_remove_controller(GTK_WIDGET(view), previous);
        g_object_set_data(G_OBJECT(view), "gtk-text-view-submit", NULL);
    }
    if (submit == NULL) {
        if (destroy != NULL) {
            destroy(context);
        }
        return;
    }

    SubmitHandler *handler = g_new(SubmitHandler, 1);
    handler->submit = submit;
    handler->context = context;
    handler->destroy = destroy;

    GtkEventController *controller = gtk_shortcut_controller_new();
    // Capture phase: run before the text view inserts a line break.
    gtk_event_controller_set_propagation_phase(controller, GTK_PHASE_CAPTURE);
    // One action shared by both shortcuts; it owns (and frees) the handler.
    GtkShortcutAction *action = gtk_callback_action_new(submit_shortcut, handler, submit_handler_free);
    gtk_shortcut_controller_add_shortcut(
        GTK_SHORTCUT_CONTROLLER(controller),
        gtk_shortcut_new(gtk_keyval_trigger_new(GDK_KEY_Return, GDK_CONTROL_MASK), g_object_ref(action)));
    gtk_shortcut_controller_add_shortcut(
        GTK_SHORTCUT_CONTROLLER(controller),
        gtk_shortcut_new(gtk_keyval_trigger_new(GDK_KEY_KP_Enter, GDK_CONTROL_MASK), action));
    gtk_widget_add_controller(GTK_WIDGET(view), controller);
    g_object_set_data(G_OBJECT(view), "gtk-text-view-submit", controller);
}
