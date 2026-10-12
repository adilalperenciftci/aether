/* The C side of own.ae (#2677): it takes plain function pointers. */
void apply(void (*handler)(int), int v) { handler(v); }
int apply_twice(int (*handler)(int), int v) { return handler(handler(v)); }
