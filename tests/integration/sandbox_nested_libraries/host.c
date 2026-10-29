/* A C host of the two libraries (#2955). The outer library's export enforces
 * a deny-all grant list and calls the host service below, which calls the
 * inner library's exports on the same thread. Prints what each read of PATH
 * got (1 read, 0 refused):
 *
 *   before  the inner library, before any enforce
 *   inner   the inner library, inside the outer block
 *   granted the inner library inside its own grant_all enforce, inside the
 *           outer block: nesting narrows, so still refused
 *   outer   the outer block's own code after the service returned
 *   after   the inner library, once the outer block has ended
 *
 * HOST_STATIC: both libraries' generated C linked into this program with one
 * runtime. Otherwise argv[1] and argv[2] are the outer and inner libraries,
 * loaded at run time. With argv[3] "mixed" (#3442) the inner one is loaded
 * first and local (RTLD_LOCAL), and reads PATH at once, so its copy finds
 * the copies first; the outer one is loaded after it, global: its lookup
 * from the program's handle sees the global scope, where the outer library
 * is, and must still agree on the inner one, the first in load order.
 *
 * HOST_OUTER_LINKED (#3445): the outer library's C linked into this program
 * with a runtime of its own, an executable that exports nothing (Windows,
 * or Linux without -rdynamic), and argv[1] the inner library. The program
 * runs the outer block once before it loads the inner library, so its copy
 * looks the copies up alone and keeps the levels; the inner library's copy,
 * loaded after, must still find them, or its code inside the deny-all block
 * is allowed everything. */
#include <stdio.h>

typedef void (*note_fn)(int which, int got);
typedef void (*service_fn)(void);
typedef void (*hooks_set_fn)(note_fn, service_fn);
typedef int (*export_fn)(void);

static export_fn outer_fn, inner_read_fn, inner_granted_fn;
static int notes[3] = { -1, -1, -1 };
static int g_mixed = 0, g_before = -1;   /* argv[3] "mixed" and its early read */

static void note(int which, int got) {
    if (which >= 0 && which < 3) notes[which] = got;
}

static void service(void) {
    if (!inner_read_fn) return;   /* HOST_OUTER_LINKED's first block, alone */
    notes[0] = inner_read_fn();
    inner_granted_fn();
}

#ifdef HOST_STATIC
extern int aether_outer(void);
extern int aether_inner_read(void);
extern int aether_inner_read_granted(void);
extern void hooks_set(note_fn, service_fn);

static int load(int argc, char** argv) {
    (void)argc; (void)argv;
    outer_fn = aether_outer;
    inner_read_fn = aether_inner_read;
    inner_granted_fn = aether_inner_read_granted;
    hooks_set(note, service);
    return 0;
}
#else
#include <string.h>
#ifdef _WIN32
#include <windows.h>
typedef HMODULE lib_t;
static lib_t lib_open(const char* path) { return LoadLibraryA(path); }
static void* lib_sym(lib_t h, const char* name) {
    FARPROC p = GetProcAddress(h, name);
    void* v;
    memcpy(&v, &p, sizeof(v));
    return v;
}
static lib_t lib_open_local(const char* path) { return LoadLibraryA(path); }
#else
#include <dlfcn.h>
typedef void* lib_t;
/* Global, as a host that links a library at build time has it. */
static lib_t lib_open(const char* path) { return dlopen(path, RTLD_NOW | RTLD_GLOBAL); }
static lib_t lib_open_local(const char* path) { return dlopen(path, RTLD_NOW | RTLD_LOCAL); }
static void* lib_sym(lib_t h, const char* name) { return dlsym(h, name); }
#endif

#ifdef HOST_OUTER_LINKED
extern int aether_outer(void);
extern void hooks_set(note_fn, service_fn);

static int load(int argc, char** argv) {
    if (argc < 2) { printf("usage: host <inner>\n"); return 1; }
    outer_fn = aether_outer;
    hooks_set(note, service);
    outer_fn();   /* this copy looks the copies up, alone */
    lib_t inner = lib_open(argv[1]);
    if (!inner) { printf("cannot load the inner library\n"); return 1; }
    void* r = lib_sym(inner, "aether_inner_read");
    void* g = lib_sym(inner, "aether_inner_read_granted");
    void* hi = lib_sym(inner, "hooks_set");
    if (!r || !g || !hi) { printf("missing symbols\n"); return 1; }
    memcpy(&inner_read_fn, &r, sizeof(r));
    memcpy(&inner_granted_fn, &g, sizeof(g));
    hooks_set_fn set_inner;
    memcpy(&set_inner, &hi, sizeof(hi));
    set_inner(note, service);
    return 0;
}
#else
static int load(int argc, char** argv) {
    if (argc < 3) { printf("usage: host <outer> <inner> [mixed]\n"); return 1; }
    g_mixed = argc > 3 && strcmp(argv[3], "mixed") == 0;
    lib_t inner = NULL;
    if (g_mixed) {
        inner = lib_open_local(argv[2]);
        void* r0 = inner ? lib_sym(inner, "aether_inner_read") : NULL;
        if (!r0) { printf("cannot load the inner library\n"); return 1; }
        memcpy(&inner_read_fn, &r0, sizeof(r0));
        g_before = inner_read_fn();   /* this copy looks the copies up now */
    }
    lib_t outer = lib_open(argv[1]);
    if (!g_mixed) inner = lib_open(argv[2]);
    if (!outer || !inner) { printf("cannot load the libraries\n"); return 1; }
    void* o = lib_sym(outer, "aether_outer");
    void* r = lib_sym(inner, "aether_inner_read");
    void* g = lib_sym(inner, "aether_inner_read_granted");
    void* ho = lib_sym(outer, "hooks_set");
    void* hi = lib_sym(inner, "hooks_set");
    if (!o || !r || !g || !ho || !hi) { printf("missing symbols\n"); return 1; }
    memcpy(&outer_fn, &o, sizeof(o));
    memcpy(&inner_read_fn, &r, sizeof(r));
    memcpy(&inner_granted_fn, &g, sizeof(g));
    hooks_set_fn set_outer, set_inner;
    memcpy(&set_outer, &ho, sizeof(ho));
    memcpy(&set_inner, &hi, sizeof(hi));
    set_outer(note, service);
    set_inner(note, service);
    return 0;
}
#endif
#endif

int main(int argc, char** argv) {
    if (load(argc, argv) != 0) return 1;
    int before = g_mixed ? g_before : inner_read_fn();
    outer_fn();
    int after = inner_read_fn();
    printf("before %d inner %d granted %d outer %d after %d\n",
           before, notes[0], notes[1], notes[2], after);
    fflush(stdout);
    return 0;
}
