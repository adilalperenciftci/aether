/* C side of the closure_handback_pattern_extern regression: stash() keeps
 * the closure it is given, with no reference of its own (an unannotated
 * extern parameter is a keep), and fire() calls it later. */

typedef struct {
    void (*fn)(void);
    void* env;
} AeClosure;

static AeClosure saved;

void stash(AeClosure boxed) {
    saved = boxed;
}

int fire(void) {
    if (!saved.fn) return -1;
    return ((int (*)(void*))saved.fn)(saved.env);
}
