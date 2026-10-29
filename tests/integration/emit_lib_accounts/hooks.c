/* The library's host_service extern, forwarded to the host, which sets it. */
typedef void (*service_fn)(int which);

static service_fn g_service;

void hooks_set(service_fn service) {
    g_service = service;
}

void host_service(int which) {
    if (g_service) g_service(which);
}
