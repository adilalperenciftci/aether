/* A C host of kinds.ae (#3377). Each export fails one allocation the
 * generated code makes and must come back with the zero value and
 * AETHER_OUT_OF_MEMORY instead of dereferencing NULL; the program's own
 * malloc returns NULL to the script and the call ends when it returns; the
 * library takes the next call. The library's C is linked into this program
 * (one runtime). */
#include <stdio.h>
#include "libaether.h"

extern int aether_k_cell(int);
extern int aether_k_ref(int);
extern int aether_k_lazy(int);
extern int aether_k_env(int);
extern int aether_k_box(int);
extern int aether_k_heap(int);
extern int aether_k_malloc(int);
extern int aether_plain(int);

typedef int (*export_fn)(int);

int main(void) {
    static const struct { const char* name; export_fn fn; } kinds[] = {
        { "cell", aether_k_cell }, { "ref", aether_k_ref }, { "lazy", aether_k_lazy },
        { "env", aether_k_env }, { "box", aether_k_box }, { "heap", aether_k_heap },
        { "malloc", aether_k_malloc }, { "plain", aether_plain },
    };
    for (size_t i = 0; i < sizeof(kinds) / sizeof(kinds[0]); i++) {
        int r = kinds[i].fn(3);
        printf("%s %d outcome %d \"%s\"\n", kinds[i].name, r, aether_last_outcome(),
               aether_last_outcome_text());
    }
    fflush(stdout);
    return 0;
}
