/*
 * A C host for a library whose export returns a string (#2931): it finds the
 * release in the library's catalog, reads each result through
 * aether_string_data / aether_string_length, and gives it back. Run under
 * leaks(1) on macOS, which finds any result not given back.
 */

#include <stdio.h>
#include <string.h>
#include <stdint.h>
#include "aether_lib_meta.h"

#ifdef _WIN32
#include <windows.h>
static void* lib_open(const char* path) { return (void*)LoadLibraryA(path); }
static void* lib_sym(void* h, const char* name) {
    return (void*)GetProcAddress((HMODULE)h, name);
}
#else
#include <dlfcn.h>
static void* lib_open(const char* path) { return dlopen(path, RTLD_NOW); }
static void* lib_sym(void* h, const char* name) { return dlsym(h, name); }
#endif

typedef const AetherLibMeta* (*meta_fn)(void);
typedef const void* (*greet_fn)(const char*);
typedef const char* (*data_fn)(const void*);
typedef size_t (*length_fn)(const void*);
typedef void (*release_fn)(const void*);

int main(int argc, char** argv) {
    if (argc < 2) { fprintf(stderr, "usage: %s <libtext>\n", argv[0]); return 2; }
    void* h = lib_open(argv[1]);
    if (!h) { fprintf(stderr, "FAIL: cannot load %s\n", argv[1]); return 1; }
    meta_fn meta = (meta_fn)lib_sym(h, "aether_lib_meta");
    if (!meta || !meta()->string_release) { fprintf(stderr, "FAIL: no string_release in the catalog\n"); return 1; }
    greet_fn greet = (greet_fn)lib_sym(h, "aether_greet");
    data_fn data = (data_fn)lib_sym(h, "aether_string_data");
    length_fn length = (length_fn)lib_sym(h, "aether_string_length");
    release_fn release = (release_fn)lib_sym(h, meta()->string_release);
    if (!greet || !data || !length || !release) { fprintf(stderr, "FAIL: a symbol is missing\n"); return 1; }
    for (int i = 0; i < 1000; i++) {
        const void* s = greet("host");
        if (length(s) != 7 || memcmp(data(s), "hi host", 7) != 0) {
            fprintf(stderr, "FAIL: call %d returned \"%.*s\"\n", i, (int)length(s), data(s));
            return 1;
        }
        release(s);
    }
    printf("host: %s OK\n", meta()->string_release);
    return 0;
}
