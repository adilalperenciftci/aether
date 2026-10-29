/* The externs the two libraries call, forwarded to the host, which sets
 * them per library (each DLL or shared object has its own copy). */
typedef void (*note_fn)(int which, int got);
typedef void (*service_fn)(void);

static note_fn g_note;
static service_fn g_service;

void hooks_set(note_fn note, service_fn service) {
    g_note = note;
    g_service = service;
}

void host_note(int which, int got) {
    if (g_note) g_note(which, got);
}

void host_service(void) {
    if (g_service) g_service();
}
