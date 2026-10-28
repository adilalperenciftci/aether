/* emcc_record.c: stands in for Emscripten's emcc in
 * test_wasm_runtime_sources.sh. It answers --version (ae's pre-flight),
 * then prints every .c file it was handed, one per line, and exits 1
 * because it compiled nothing. A compiled program rather than a script, so
 * that ae can start it on Windows too (_spawnvp runs an .exe, not a #!). */
#include <stdio.h>
#include <string.h>

int main(int argc, char** argv) {
    if (argc > 1 && strcmp(argv[1], "--version") == 0) {
        puts("emcc (stub) 0.0");
        return 0;
    }
    for (int i = 1; i < argc; i++) {
        size_t n = strlen(argv[i]);
        if (n >= 2 && strcmp(argv[i] + n - 2, ".c") == 0) printf("SRC %s\n", argv[i]);
    }
    return 1;
}
