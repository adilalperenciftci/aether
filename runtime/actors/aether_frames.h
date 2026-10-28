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
} AetherExecRecord;

#define AETHER_OUTCOME_TEXT_MAX 1024

struct AetherUnwindEntry;   /* aether_unwind.c's */

typedef struct {
    AetherJmpFrame   frames[AETHER_PANIC_MAX_DEPTH];
    int              depth;    /* live frames; the innermost is frames[depth-1] */
    AetherExecRecord exec[AETHER_PANIC_MAX_DEPTH];
    int              exec_depth;
    int              outcome;  /* the last execution's, aether_last_outcome() */
    char             outcome_text[AETHER_OUTCOME_TEXT_MAX];
    /* The allocation journal (aether_unwind.c): its entries are tagged with
     * the frame depth they were made at. */
    struct AetherUnwindEntry* journal;
    int              journal_count;
    int              journal_capacity;
} AetherFrames;

/* Defined in aether_unwind.c, which every program links (the generated code
 * journals), so a program that never catches does not pull aether_panic.o. */
extern AETHER_TLS_SHARED AetherFrames aether_frames;

#endif /* AETHER_FRAMES_H */
