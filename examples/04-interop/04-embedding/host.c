/* The C program of examples/04-interop/04-embedding: it calls the
 * functions greeter.ae exports, as run.sh links them. */
#include <stdint.h>
#include <stdio.h>

int32_t aether_add(int32_t a, int32_t b);
double aether_average(int64_t total, int32_t count);
const void* aether_greet(const char* name);

/* The runtime's string accessors and the library's release function. */
const char* aether_string_data(const void* s);
size_t aether_string_length(const void* s);
void aether_greeter_string_release(const void* s);

int main(void) {
    printf("add(2, 40) = %d\n", aether_add(2, 40));
    printf("average(10, 4) = %g\n", aether_average(10, 4));
    const void* s = aether_greet("C");
    printf("%.*s\n", (int)aether_string_length(s), aether_string_data(s));
    aether_greeter_string_release(s);
    return 0;
}
