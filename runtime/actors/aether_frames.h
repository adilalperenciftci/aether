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
    int              outcome;  /* the last execution's, aether_last_outcome() */
    char             outcome_text[AETHER_OUTCOME_TEXT_MAX];
    int              interrupting; /* the outcome an interruption on its way carries */
    uint64_t         serial;   /* executions entered on this thread */
    AetherCancelCell* cell;
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
 * g_current_step_actor) has no adjacent store to merge with. */
AetherFrames* aether_frames_here(void);

#endif /* AETHER_FRAMES_H */
