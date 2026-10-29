/* aether_frames.h: the per-thread frames a panic unwinds to, shared by the
 * runtime files that keep them (aether_panic.c, aether_unwind.c,
 * aether_exec.c). Runtime-internal: generated code never names this
 * thread-local (a Windows DLL cannot import one); it reaches the frames only
 * through the functions in aether_panic.h and aether_exec.h.
 *
 * One block per thread, so a try frame or an execution frame costs one
 * thread-local lookup, not one per file: the frames, the executions among
 * them (#2955, #2956), and the depth the allocation journal tags entries
 * with, which is the frame depth itself. */

#ifndef AETHER_FRAMES_H
#define AETHER_FRAMES_H

#include <stdint.h>
#include "aether_panic.h"

/* What an execution keeps to give back when it returns (aether_exec.c). */
typedef struct {
    int64_t deadline_at_ns;    /* the deadline in force when it was entered */
    int     deadline_tripped;  /*   (a nested execution's only) */
    int64_t next_at_ns;        /* the deadline a host service it called set */
    int     next_tripped;      /*   for the executions entered from there */
    int     next_set;
    int     sandbox_depth;     /* this thread's sandbox levels at entry */
    int     has_view;          /* aether_host.c kept its caller info */
    int     stop;              /* why a C-backed std loop stopped early */
    uint64_t serial;           /* this thread's count of executions, its token */
    struct AetherExecAccount* account;  /* the account in use when it began (#2954) */
    int     account_timed;              /*   the ACTIVE accounts it began timing (#3409) */
    int     account_deadline;           /* it took its account's deadline */
} AetherExecRecord;

/* Where another thread asks for an execution of this one to stop
 * (aether_exec_cancel): the serial of the execution to cancel, 0 for none.
 * Made the first time a token is asked for on a thread and kept for the
 * process, so a token never points at freed memory. */
typedef struct AetherCancelCell {
    _Atomic uint64_t pending;
    struct AetherCancelCell* next;
} AetherCancelCell;

#define AETHER_OUTCOME_TEXT_MAX 1024

struct AetherUnwindEntry;   /* aether_unwind.c's */

typedef struct {
    AetherJmpFrame   frames[AETHER_PANIC_MAX_DEPTH];
    int              depth;    /* live frames; the innermost is frames[depth-1] */
    AetherExecRecord exec[AETHER_PANIC_MAX_DEPTH];
    int              exec_depth;
    /* The executions below are the code's an actor step runs inside
     * (#3392): put aside for the step, which runs outside every one of them
     * (aether_step_put_aside_execs below). Only those above it run here. */
    int              exec_floor;
    int              outcome;  /* the last execution's, aether_last_outcome() */
    char             outcome_text[AETHER_OUTCOME_TEXT_MAX];
    int              interrupting; /* the outcome an interruption on its way carries */
    uint64_t         serial;   /* executions entered on this thread */
    AetherCancelCell* cell;
    struct AetherExecAccount* account; /* in use on this thread (aether_exec_use, #2954) */
    /* The allocation journal (aether_unwind.c): its entries are tagged with
     * the frame depth they were made at. */
    struct AetherUnwindEntry* journal;
    int              journal_count;
    int              journal_capacity;
} AetherFrames;

/* This thread's block. The block is a `static` thread-local of
 * aether_unwind.c, the one file that owns it (with the try frames' push and
 * pop and the journal, the paths every step and every try takes); every
 * other file reaches it through this function and never names the
 * thread-local.
 *
 * The rule for the runtime's thread-locals: an extern thread-local is a
 * scalar written whole; an aggregate stays static to its file, reached by
 * accessor. Generated code goes further and names none (a Windows DLL cannot
 * import a thread-local). An extern aggregate was miscompiled by GCC 16.2
 * for x86_64-w64-mingw32 at -O2: two adjacent stores into it, merged into
 * one, were addressed through the variable's non-thread address and landed
 * in the thread-local template, not the calling thread's block. A scalar
 * read or written whole (an int, a pointer: current_core_id,
 * g_current_step_actor) has no adjacent store to merge with. The send buffer
 * (aether_send_buffer.c) follows the same rule. */
AetherFrames* aether_frames_here(void);

/* What an actor step puts aside of the executions it runs inside (#3392,
 * #3396; the rule is aether_step_barrier.h's): the floor below which the
 * executions are not the step's, an interruption on its way through them,
 * and, through aether_exec.c, the call's deadline and its caller info. */
typedef struct {
    int     exec_floor;
    int     interrupting;
    int     execs_part;     /* aether_exec.c took its part (the hook was set) */
    int64_t deadline_at_ns;
    int     deadline_tripped;
    void*   caller;         /* aether_host.c's: the setting, put away */
} AetherExecAside;

/* Set by aether_exec.c at its first execution: puts aside (hide 1) or gives
 * back (hide 0) the deadline and the caller info, which live in files only
 * a library call links. */
extern void (*_Atomic aether_step_execs_hook)(AetherExecAside* s, int hide);

/* An actor step begins and ends (aether_step_barrier.h): the executions
 * running on this thread are put aside, 1 when there were any (or an
 * interruption on its way), and given back. The step's try frame is pushed
 * with them, in one look at this thread's block. */
AetherJmpFrame* aether_step_push(AetherExecAside* s, int* hid);
void aether_step_give_back_execs(const AetherExecAside* s);

#endif /* AETHER_FRAMES_H */
