/* A C host of steps.ae (#3392, #3396), the library linked in. Run on the
 * runtime the tree was built with: threads, or the cooperative scheduler
 * (make ci-coop), where an export's ask steps the actor on this thread,
 * inside the call.
 *
 *   spin: 0 outcome 2, the spinner finished: yes
 *   catch: 1 outcome 0
 *   teller: "" outcome 0
 *   a kill: the call's outcome is its drop's: yes
 *   after a kill: catch 1 outcome 0
 *   a cancelled kill: the call's outcome is its drop's: yes
 *   an interrupted kill: outcome 2, in a try: outcome 2, caught 0
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
extern int32_t aether_slow_dropped_in_call(void);
extern int32_t aether_interrupted_kill(void);
extern int32_t aether_interrupted_kill_in_try(void);
extern int32_t aether_swallowed(void);
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
     * runtime it finalizes there and then): the call ends with the deadline
     * when the drop ran inside it, and normally when the drop ran on a
     * core's thread; the next call's try catches its own panic. */
    aether_set_call_deadline(1);
    host_sleep_ms(5);
    (void)aether_kill_holder();
    int ko = aether_last_outcome();
    aether_set_call_deadline(0);
    int in_call = aether_slow_dropped_in_call();
    fprintf(stderr, "a kill: outcome %d, its drop inside the call: %d\n", ko, in_call);
    printf("a kill: the call's outcome is its drop's: %s\n",
           ko == (in_call ? AETHER_DEADLINE : AETHER_OK) ? "yes" : "no");
    int c2 = aether_catches();
    printf("after a kill: catch %d outcome %d\n", c2, aether_last_outcome());

    /* #3415: the same kill in a call cancelled before it starts, so the
     * drop's loop is the call's first safe point. A passed deadline also
     * trips a flag the call's end reads; a cancel does not, so the call ends
     * cancelled only through the stop the drop's containment frame notes for
     * it, and a fix that dropped the interruption ended it normally. Where
     * the drop runs on a core's thread the call reaches no safe point and
     * ends normally. */
    (void)aether_exec_cancel(aether_exec_token());
    (void)aether_kill_holder();
    int kc = aether_last_outcome();
    int kc_in_call = aether_slow_dropped_in_call();
    fprintf(stderr, "a cancelled kill: outcome %d, its drop inside the call: %d\n", kc, kc_in_call);
    printf("a cancelled kill: the call's outcome is its drop's: %s\n",
           kc == (kc_in_call ? AETHER_CANCELLED : AETHER_OK) ? "yes" : "no");

    /* #3415: a defer the deadline's unwind runs kills an actor, and the
     * drop of its queued message panics: the call still ends with its
     * deadline, and a try on the way passes the deadline on. */
    aether_set_call_deadline(1);
    host_sleep_ms(5);
    (void)aether_interrupted_kill();
    int ik = aether_last_outcome();
    (void)aether_interrupted_kill_in_try();
    int ikt = aether_last_outcome();
    aether_set_call_deadline(0);
    printf("an interrupted kill: outcome %d, in a try: outcome %d, caught %d\n", ik, ikt,
           (int)aether_swallowed());
    fflush(stdout);
    return 0;
}
