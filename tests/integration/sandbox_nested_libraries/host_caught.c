/* A host with the panic of a runtime of its own and no sandbox, which loads
 * caught.ae's library, built with a runtime of its own (#3438). On Linux it
 * is linked -rdynamic, as `ae build` links a program: the library's calls
 * to the panic and the try frames bind to this program's (ELF
 * interposition), and the library's sandbox, the only one, must reach them
 * through this program's pointers, or a panic caught inside its enforce
 * block leaves the nested level in force. Prints what each read got
 * (1 read, 0 refused).
 *
 * With argv[2], another library with a sandbox of its own (inner.ae's),
 * loaded too: the first runs its block, the second enforces after it (its
 * copy looks the copies up last), and the first runs its block again. Both
 * run this program's panic: one slot of hooks, which the last copy to look
 * set, served only the second, and the first's caught panic left its level
 * in force; each copy now adds its own (#3438). */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef void (*note_fn)(int which, int got);
typedef void (*service_fn)(void);
typedef void (*hooks_set_fn)(note_fn, service_fn);
typedef int (*export_fn)(void);

/* The panic of this program's copy, which has no sandbox. */
extern void aether_panic(const char* reason);
void (*volatile keep_panic)(const char*) = aether_panic;

static int notes[3] = { -1, -1, -1 };
static void note(int which, int got) {
    if (which >= 0 && which < 3) notes[which] = got;
}
static void service(void) {}

#ifdef _WIN32
#include <windows.h>
static void* lib_open(const char* path) { return (void*)LoadLibraryA(path); }
static void* lib_sym(void* h, const char* name) {
    FARPROC p = GetProcAddress((HMODULE)h, name);
    void* v;
    memcpy(&v, &p, sizeof(v));
    return v;
}
#else
#include <dlfcn.h>
static void* lib_open(const char* path) { return dlopen(path, RTLD_NOW | RTLD_LOCAL); }
static void* lib_sym(void* h, const char* name) { return dlsym(h, name); }
#endif

int main(int argc, char** argv) {
    if (argc < 2) { printf("usage: host_caught <library>\n"); return 1; }
#ifdef _WIN32
    _putenv("CAUGHT_PROBE=1");
#else
    setenv("CAUGHT_PROBE", "1", 1);
#endif
    void* lib = lib_open(argv[1]);
    void* c = lib ? lib_sym(lib, "aether_caught") : NULL;
    void* h = lib ? lib_sym(lib, "hooks_set") : NULL;
    if (!c || !h) { printf("cannot load %s\n", argv[1]); return 1; }
    export_fn caught;
    hooks_set_fn set;
    memcpy(&caught, &c, sizeof(c));
    memcpy(&set, &h, sizeof(h));
    set(note, service);
    caught();
    printf("after the catch PATH %d probe %d; after the block probe %d\n", notes[0], notes[1], notes[2]);
    if (argc > 2) {
        void* other = lib_open(argv[2]);
        void* g = other ? lib_sym(other, "aether_inner_read_granted") : NULL;
        void* oh = other ? lib_sym(other, "hooks_set") : NULL;
        if (!g || !oh) { printf("cannot load %s\n", argv[2]); return 1; }
        export_fn granted;
        hooks_set_fn set_other;
        memcpy(&granted, &g, sizeof(g));
        memcpy(&set_other, &oh, sizeof(oh));
        set_other(note, service);
        granted();   /* the other copy enforces: it looks the copies up now */
        notes[0] = notes[1] = notes[2] = -1;
        caught();
        printf("again, after another copy looked: after the catch PATH %d probe %d; after the block probe %d\n",
               notes[0], notes[1], notes[2]);
    }
    fflush(stdout);
    return 0;
}
