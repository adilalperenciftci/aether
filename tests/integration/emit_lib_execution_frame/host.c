/* A C host of frames.ae (#2955, #2956). Prints, for an export that panics
 * and for an outer export whose host service runs an inner export that
 * returns, refuses or panics, what each call returned and how it ended:
 *
 *   boom 0 outcome 1 "boom 1"; plain 7 outcome 0; again 1 outcome 0
 *   which W: inner R outcome O "TEXT"; outer B outcome O
 *
 * B is the outer export's view after the service: 1 its caller info is its
 * own, 2 its loop is not cut by the inner call's deadline, 4 its sandbox
 * levels are as they were; 7 is all three.
 *
 * HOST_STATIC: the library's generated C is linked into this program, one
 * runtime. Otherwise argv[1] is the library, loaded at run time, and the
 * host API is the library's own runtime's: in the library, or in the shared
 * runtime argv[2] names. */
#include <stdio.h>
#include <stdint.h>
#include <string.h>

typedef int (*int_fn)(int);
typedef int (*outcome_fn)(void);
typedef const char* (*text_fn)(void);
typedef int (*set_caller_fn)(const char*, const char**, const char**, size_t, int64_t);
typedef void (*deadline_fn)(int64_t);
typedef void (*service_fn)(int);
typedef void (*hooks_set_fn)(service_fn);

static int_fn boom_fn, plain_fn, inner_fn, outer_fn;
static outcome_fn last_outcome_fn;
static text_fn last_text_fn;
static set_caller_fn set_caller_fn_;
static deadline_fn set_deadline_fn;

static int inner_ret, inner_outcome;
static char inner_text[128];

/* The trusted host service the outer export calls: an inner call for
 * another caller, with a deadline of its own. */
static void service(int which) {
    set_caller_fn_("inner", NULL, NULL, 0, 0);
    set_deadline_fn(1);
    inner_ret = inner_fn(which);
    inner_outcome = last_outcome_fn();
    snprintf(inner_text, sizeof(inner_text), "%s", last_text_fn());
}

#ifdef HOST_STATIC
#include "libaether.h"
#include "aether_host.h"
extern int aether_boom(int);
extern int aether_plain(int);
extern int aether_inner(int);
extern int aether_outer(int);
extern void hooks_set(service_fn);

static int load(int argc, char** argv) {
    (void)argc; (void)argv;
    boom_fn = aether_boom;
    plain_fn = aether_plain;
    inner_fn = aether_inner;
    outer_fn = aether_outer;
    last_outcome_fn = aether_last_outcome;
    last_text_fn = aether_last_outcome_text;
    set_caller_fn_ = aether_set_caller;
    set_deadline_fn = aether_set_call_deadline;
    hooks_set(service);
    return 0;
}
#else
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
static lib_t lib_open(const char* path) { return dlopen(path, RTLD_NOW | RTLD_GLOBAL); }
static void* lib_sym(lib_t h, const char* name) { return dlsym(h, name); }
#endif

#define BIND(var, from, name) do { void* p_ = lib_sym(from, name); \
    if (!p_) { printf("missing %s\n", name); return 1; } memcpy(&var, &p_, sizeof(p_)); } while (0)

/* argv[2], when given, is the shared runtime the library runs on: the host
 * API is there. */
static int load(int argc, char** argv) {
    if (argc < 2) { printf("usage: host <library> [<shared runtime>]\n"); return 1; }
    lib_t lib = lib_open(argv[1]);
    if (!lib) { printf("cannot load %s\n", argv[1]); return 1; }
    lib_t rt = argc > 2 ? lib_open(argv[2]) : lib;
    if (!rt) { printf("cannot load %s\n", argv[2]); return 1; }
    hooks_set_fn hooks;
    BIND(boom_fn, lib, "aether_boom");
    BIND(plain_fn, lib, "aether_plain");
    BIND(inner_fn, lib, "aether_inner");
    BIND(outer_fn, lib, "aether_outer");
    BIND(last_outcome_fn, rt, "aether_last_outcome");
    BIND(last_text_fn, rt, "aether_last_outcome_text");
    BIND(set_caller_fn_, rt, "aether_set_caller");
    BIND(set_deadline_fn, rt, "aether_set_call_deadline");
    BIND(hooks, lib, "hooks_set");
    hooks(service);
    return 0;
}
#endif

int main(int argc, char** argv) {
    if (load(argc, argv) != 0) return 1;
    int b = boom_fn(1);
    int bo = last_outcome_fn();
    char bt[128];
    snprintf(bt, sizeof(bt), "%s", last_text_fn());
    /* A frameless export right after a failed call: its own outcome. */
    int p = plain_fn(3);
    int po = last_outcome_fn();
    int again = boom_fn(0);
    printf("boom %d outcome %d \"%s\"; plain %d outcome %d; again %d outcome %d\n", b, bo, bt, p, po,
           again, last_outcome_fn());
    for (int which = 0; which < 3; which++) {
        set_caller_fn_("outer", NULL, NULL, 0, 0);
        set_deadline_fn(0);
        inner_ret = -9;
        inner_outcome = -9;
        inner_text[0] = '\0';
        int bits = outer_fn(which);
        printf("which %d: inner %d outcome %d \"%s\"; outer %d outcome %d\n",
               which, inner_ret, inner_outcome, inner_text, bits, last_outcome_fn());
    }
    fflush(stdout);
    return 0;
}
