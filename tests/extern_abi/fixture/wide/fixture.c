/* The C definitions the self-test's externs bind. Never built. */
#include <stddef.h>
#include <stdint.h>

void* fx_len(void* data, size_t n) { (void)n; return data; }
long fx_count(void) { return 0; }
int fx_pair(int a, int b, int c) { return a + b + c; }
void* fx_handle(void* p) { return p; }
void fx_sym_impl(int n) { (void)n; }

double fx_good(int a, int64_t b, const char* s, size_t n,
               double f) {
    (void)a; (void)b; (void)s; (void)n;
    return f;
}
int fx_fmt(const char* fmt, ...) { (void)fmt; return 0; }
void fx_cb(int (*cb)(int), void* ud, _Bool b) { (void)cb; (void)ud; (void)b; }
static int fx_hidden(int n) { return n; }
