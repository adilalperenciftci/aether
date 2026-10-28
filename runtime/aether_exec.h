/* aether_exec.h: an execution, one call from a host into a library export
 * until it returns (#2955, #2956).
 *
 * Every aether_<name> export stub runs its function inside an execution
 * frame:
 *
 *     AetherJmpFrame* x = aether_exec_enter();
 *     if (AETHER_SIGSETJMP(x->buf, 1)) { aether_exec_failed(); return zero; }
 *     r = f(args);
 *     aether_exec_leave();
 *     return r;
 *
 * The frame is a panic frame, so a panic the export does not catch ends
 * the execution instead of the process, and it keeps what a nested
 * execution may change on this thread (the caller info a host service
 * sets, the deadline, the sandbox levels), putting it back however the
 * execution ends. Each execution leaves an outcome the caller reads with
 * aether_last_outcome() (libaether.h): a zero value with an outcome other
 * than AETHER_OK is not a result. */

#ifndef AETHER_EXEC_H
#define AETHER_EXEC_H

#include <stdint.h>
#include "actors/aether_panic.h"

#ifdef __cplusplus
extern "C" {
#endif

#ifndef AETHER_OK
#define AETHER_OK             0
#define AETHER_PANICKED       1
#define AETHER_DEADLINE       2
#define AETHER_CANCELLED      3
#define AETHER_MEMORY_CAP     4
#define AETHER_OUT_OF_MEMORY  5
#endif

/* The deepest executions nest on one thread: each is a panic frame. */
#define AETHER_EXEC_MAX_DEPTH AETHER_PANIC_MAX_DEPTH

AetherJmpFrame* aether_exec_enter(void);
void aether_exec_leave(void);
void aether_exec_failed(void);

#if AETHER_EXEC_BUILTIN_SJLJ
/* The stub's form where the compiler has __builtin_setjmp (aether_panic.h):
 * the context saved in the stub's own `void* buf[5]`, before entering.
 *
 *     void* b[5];
 *     if (__builtin_setjmp(b)) { aether_exec_failed(); return zero; }
 *     aether_exec_enter_at(b);
 *     r = f(args);
 *     aether_exec_leave();
 */
void aether_exec_enter_at(void** buf);
#endif

/* Executions running on this thread (0 outside any). */
int aether_exec_depth(void);

/* aether_host.c keeps a copy of the caller info the execution at `depth`
 * was entered with (aether_host.h): it is put back when that one returns. */
void aether_exec_mark_view(int depth);

/* A deadline a host service sets while an execution runs: for the
 * executions it enters from there, until the running one returns. */
void aether_exec_set_next_deadline(int64_t ms);

/* The stub of an export that can neither panic, allocate, loop nor call
 * anything has no frame: it records the OK outcome only. */
void aether_exec_ok(void);

int aether_last_outcome(void);
const char* aether_last_outcome_text(void);

/* The outcome of a call into a library with a runtime of its own, as the
 * importer's runtime records it, so std.host's last_outcome() sees it. */
void aether_exec_note_outcome(int outcome, const char* text);

#ifdef __cplusplus
}
#endif

#endif /* AETHER_EXEC_H */
