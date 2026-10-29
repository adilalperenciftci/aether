/* #3413: the probe's C handle. handle_close is the drop of an owned type;
 * every close is counted, so the probe can tell a drop that never ran from
 * one that ran twice. Drops of an actor's bindings run on its thread. */
#include <stdatomic.h>
#include <stdlib.h>

#include "handle.h"

struct Handle {
    int id;
};

static atomic_int g_closed;

void* handle_open(int id) {
    Handle* h = (Handle*)malloc(sizeof(Handle));
    if (h) h->id = id;
    return h;
}

int handle_close(Handle* h) {
    if (!h) return -1;
    free(h);
    atomic_fetch_add(&g_closed, 1);
    return 0;
}

int handle_closed(void) {
    return atomic_load(&g_closed);
}
