/* The C half of examples/04-interop/02-own-c/main.ae, compiled into the
 * program by its @source line. */
#include <stddef.h>
#include <stdint.h>

/* FNV-1a over a string's bytes. */
uint32_t shim_fnv1a(const char* text) {
    uint32_t h = 2166136261u;
    for (const unsigned char* p = (const unsigned char*)text; *p; p++) {
        h ^= *p;
        h *= 16777619u;
    }
    return h;
}

/* Writes n values into memory the caller owns. */
void shim_fill_squares(int* out, int n) {
    for (int i = 0; i < n; i++) {
        out[i] = i * i;
    }
}

/* A string C keeps: static storage, so it outlives the call. */
const char* shim_version(void) {
    return "shim 1.2";
}

struct shim_point {
    int x;
    int y;
};

/* Reads and writes a struct through the pointer it is given. */
void shim_mirror(struct shim_point* p) {
    int t = p->x;
    p->x = p->y;
    p->y = t;
}
