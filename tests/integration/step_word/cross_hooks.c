/* The library's way to the host (cross.ae): the functions the host sets,
 * and a count of Looker's runs, read inside the block once the send that
 * stepped it has returned. */
static void (*g_enter)(void) = 0;
static void (*g_leave)(void) = 0;
static int g_looked = 0;

void cross_set_host(void (*enter)(void), void (*leave)(void)) {
    g_enter = enter;
    g_leave = leave;
}

void cross_host_enter(void) {
    if (g_enter) g_enter();
}

void cross_host_leave(void) {
    if (g_leave) g_leave();
}

void cross_note_look(void) {
    g_looked++;
}

int cross_looked(void) {
    return g_looked;
}
