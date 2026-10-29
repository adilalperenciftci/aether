/* A host with no runtime of its own (#3437): loads argv[1], a library
 * exporting a sandbox rendezvous of another layout (foreign_sbx.c), global,
 * then argv[2], sbx_copy.c's library with a runtime copy, local, and runs
 * that copy's checks. The foreign rendezvous is then the first a copy finds
 * on every platform. */
#include <stdio.h>
#include <string.h>
#ifdef _WIN32
#include <windows.h>
static void* load_global(const char* p) { return (void*)LoadLibraryA(p); }
static void* load_local(const char* p) { return (void*)LoadLibraryA(p); }
static void* sym(void* h, const char* n) {
    FARPROC f = GetProcAddress((HMODULE)h, n);
    void* v;
    memcpy(&v, &f, sizeof(v));
    return v;
}
#else
#include <dlfcn.h>
static void* load_global(const char* p) { return dlopen(p, RTLD_NOW | RTLD_GLOBAL); }
static void* load_local(const char* p) { return dlopen(p, RTLD_NOW | RTLD_LOCAL); }
static void* sym(void* h, const char* n) { return dlsym(h, n); }
#endif

typedef int (*calls_fn)(void);
typedef void (*run_fn)(calls_fn);

int main(int argc, char** argv) {
    if (argc < 3) { printf("usage: sbx_driver <foreign rendezvous> <copy>\n"); return 2; }
    void* f = load_global(argv[1]);
    void* c = f ? load_local(argv[2]) : NULL;
    void* pc = f ? sym(f, "foreign_sbx_calls") : NULL;
    void* pr = c ? sym(c, "sbx_run") : NULL;
    if (!pc || !pr) { printf("cannot load the libraries\n"); return 2; }
    calls_fn calls;
    run_fn run;
    memcpy(&calls, &pc, sizeof(pc));
    memcpy(&run, &pr, sizeof(pr));
    run(calls);
    return 0;
}
