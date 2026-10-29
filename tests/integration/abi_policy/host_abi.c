/* A C host of abi_lib.ae (#2957). Built twice: with the library's C compiled
 * as the runtime it links was (the same runtime ABI), and with it compiled
 * -DAETHER_DEBUG_MAILBOX, a flag that changes a layout generated C reads,
 * against a runtime built without it. Then every call returns its zero
 * value with AETHER_INCOMPATIBLE (6), none of the library's code runs, and
 * the preflight and the outcome's text name both runtime ABIs.
 *
 *   the same runtime:      check 0 / bump: 42 outcome 0 / greet: a string
 *                          outcome 0 / ran 2
 *   another runtime ABI:   check -1, names both: yes / bump: 0 outcome 6,
 *                          names both: yes / greet: (null) outcome 6 / ran 0
 */
#include <stdio.h>
#include <string.h>
#include <stdint.h>
#include "libaether.h"

extern int32_t aether_bump(int32_t n);
extern const void* aether_greet(void);
extern int aether_abi_lib_check(const char** why);
extern const char* aether_runtime_abi(void);
extern void aether_abi_lib_string_release(const void* s);

static int g_ran;
void host_ran(void) { g_ran++; }

static int names_both(const char* text) {
    return text && strstr(text, aether_runtime_abi()) && strstr(text, "+debug-mailbox");
}

int main(void) {
    const char* why = NULL;
    int c = aether_abi_lib_check(&why);
    if (c == 0) printf("check 0\n");
    else printf("check %d, names both: %s\n", c, names_both(why) ? "yes" : "no");
    int32_t b = aether_bump(41);
    int o = aether_last_outcome();
    if (o == AETHER_OK) printf("bump: %d outcome 0\n", b);
    else printf("bump: %d outcome %d, names both: %s\n", b, o, names_both(aether_last_outcome_text()) ? "yes" : "no");
    const void* g = aether_greet();
    printf("greet: %s outcome %d\n", g ? "a string" : "(null)", aether_last_outcome());
    if (g) aether_abi_lib_string_release(g);
    printf("ran %d\n", g_ran);
    fflush(stdout);
    return 0;
}
