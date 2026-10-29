/* A C host of steps.ae (#3392, #3396), the library linked in. Run on the
 * runtime the tree was built with: threads, or the cooperative scheduler
 * (make ci-coop), where an export's ask steps the actor on this thread,
 * inside the call.
 *
 *   spin: 0 outcome 2, the spinner finished: yes
 *   catch: 1 outcome 0
 *   teller: "" outcome 0
 *   after a kill: catch 1 outcome 0
 */
#include <stdio.h>
#include <stdint.h>
#include "libaether.h"
#include "aether_host.h"   /* aether_set_caller */
#ifdef _WIN32
#include <windows.h>
#define host_sleep_ms(ms) Sleep(ms)
#else
#include <unistd.h>
#define host_sleep_ms(ms) usleep((ms) * 1000)
#endif

extern int32_t aether_ask_spin(int32_t ms);
extern int32_t aether_spun(void);
extern int32_t aether_catches(void);
extern const void* aether_teller_sees(void);
extern int32_t aether_kill_holder(void);
extern const char* aether_string_data(const void* s);
extern void aether_steps_string_release(const void* s);

int main(void) {
    aether_set_caller("alice", NULL, NULL, 0, 0);
    aether_set_call_deadline(20);
    int v = aether_ask_spin(60);
    int out = aether_last_outcome();
    printf("spin: %d outcome %d, the spinner finished: %s\n", v, out, aether_spun() == 1 ? "yes" : "no");
    aether_set_call_deadline(0);

    int c = aether_catches();
    printf("catch: %d outcome %d\n", c, aether_last_outcome());

    const void* s = aether_teller_sees();
    printf("teller: \"%s\" outcome %d\n", s ? aether_string_data(s) : "(null)", aether_last_outcome());
    if (s) aether_steps_string_release(s);

    /* A kill whose drop runs past the call's deadline (on the cooperative
     * runtime it finalizes there and then): the next call's try catches
     * its own panic. */
    aether_set_call_deadline(1);
    host_sleep_ms(5);
    (void)aether_kill_holder();
    aether_set_call_deadline(0);
    int c2 = aether_catches();
    printf("after a kill: catch %d outcome %d\n", c2, aether_last_outcome());
    fflush(stdout);
    return 0;
}
