/* C-side closure-retention sink for the
 * closure_extern_retains_no_uaf regression. Models the canonical
 * "callback registry" extern callsite: register_cb() stores a boxed
 * closure pointer; fire_cb() invokes it later. register_cb is
 * declared `@retain`, so the call hands it a reference of its own and
 * the env outlives the caller's release. */

typedef struct {
    void (*fn)(void);
    void* env;
} AeClosure;

static AeClosure saved;

void register_cb(AeClosure boxed) {
    saved = boxed;
}

void fire_cb(void) {
    if (saved.fn) {
        ((void (*)(void*))saved.fn)(saved.env);
    }
}
