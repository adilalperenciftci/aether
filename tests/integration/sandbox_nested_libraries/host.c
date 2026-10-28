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
 * loaded at run time. */
#include <stdio.h>

typedef void (*note_fn)(int which, int got);
typedef void (*service_fn)(void);
typedef void (*hooks_set_fn)(note_fn, service_fn);
typedef int (*export_fn)(void);

static export_fn outer_fn, inner_read_fn, inner_granted_fn;
static int notes[3] = { -1, -1, -1 };

static void note(int which, int got) {
    if (which >= 0 && which < 3) notes[which] = got;
}

static void service(void) {
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
#else
#include <dlfcn.h>
typedef void* lib_t;
/* Global, as a host that links a library at build time has it. */
static lib_t lib_open(const char* path) { return dlopen(path, RTLD_NOW | RTLD_GLOBAL); }
static void* lib_sym(lib_t h, const char* name) { return dlsym(h, name); }
#endif

static int load(int argc, char** argv) {
    if (argc < 3) { printf("usage: host <outer> <inner>\n"); return 1; }
    lib_t outer = lib_open(argv[1]);
    lib_t inner = lib_open(argv[2]);
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

int main(int argc, char** argv) {
    if (load(argc, argv) != 0) return 1;
    int before = inner_read_fn();
    outer_fn();
    int after = inner_read_fn();
    printf("before %d inner %d granted %d outer %d after %d\n",
           before, notes[0], notes[1], notes[2], after);
    fflush(stdout);
    return 0;
}
