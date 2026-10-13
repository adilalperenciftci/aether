/* C side of the closure_ptr_cell_c_string regression: reads a `ptr` as the
 * C string it should be and reports what it saw. */
#include <string.h>

static char seen[64];

int see(const void* p) {
    if (!p) {
        strcpy(seen, "(null)");
        return -1;
    }
    strncpy(seen, (const char*)p, sizeof(seen) - 1);
    seen[sizeof(seen) - 1] = 0;
    return (int)strlen(seen);
}

int seen_is(const char* want) {
    return strcmp(seen, want) == 0;
}
