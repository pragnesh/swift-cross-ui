#ifndef GTK_TEXT_VIEW_SUBMIT_H
#define GTK_TEXT_VIEW_SUBMIT_H

#include <gtk/gtk.h>

G_BEGIN_DECLS

typedef void (*GtkTextViewSubmitFunc)(void *context);

/// Calls `submit` with `context` when Ctrl+Enter is pressed in `view`,
/// instead of inserting a line break. Replaces any previous handler;
/// `destroy` is called with `context` when the handler is replaced or the
/// view is destroyed. Pass NULL `submit` to remove the handler.
void gtk_text_view_set_submit_handler(
    GtkTextView *view,
    GtkTextViewSubmitFunc submit,
    void *context,
    GDestroyNotify destroy
);

G_END_DECLS

#endif
