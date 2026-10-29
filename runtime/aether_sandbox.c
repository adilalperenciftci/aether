// aether_sandbox.c: the grant levels each thread is inside, and the check.
//
// The levels used to live in the generated code of each program and
// library (a stack per translation unit), with one process-wide pointer to
// the checker an enforce installed and cleared (#2955). A thread leaving
// its enforce cleared the pointer while another thread was inside one, so
// that thread ran unchecked, or called the pointer after it was cleared and
// crashed (D1); and a library's export called from inside another's
// enforce checked against its own, empty stack, or replaced the outer
// checker and then cleared it (D2). Now each thread's levels are here,
// once per runtime image, and nothing is installed: the check reads the
// calling thread's levels, behind a count of threads that have any.

#if !defined(_WIN32) && !defined(_GNU_SOURCE)
#  define _GNU_SOURCE   /* RTLD_DEFAULT in glibc's <dlfcn.h> */
#endif
#include "aether_sandbox.h"

#ifdef AETHER_HAS_SANDBOX
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "aether_sandbox_path.h"
#include "actors/aether_panic.h"
#include "aether_resource_caps.h"

#if defined(_WIN32)
#  ifndef WIN32_LEAN_AND_MEAN
#    define WIN32_LEAN_AND_MEAN
#  endif
#  include <windows.h>
#elif defined(__unix__) || defined(__APPLE__)
#  include <dlfcn.h>
#  if defined(__APPLE__)
#    include <mach-o/dyld.h>
#  elif defined(__linux__) || defined(__FreeBSD__) || defined(__NetBSD__) || defined(__OpenBSD__)
#    include <link.h>
#    define AETHER_SANDBOX_PHDR 1
#  endif
#endif

/* A grant list is a std.list of (category, pattern) pairs, each element a
 * plain C string or an Aether string (a helper that keeps its `string`
 * parameter stores its own copy). */
extern int list_size(void*);
extern void* list_get_raw(void*, int);
extern const char* aether_string_data(const void*);
extern void aether_sandbox_audit(const char* category, const char* resource, int allowed);

// ---------------------------------------------------------------------------
// Runtime images that share a thread's levels (#2955, D2)
// ---------------------------------------------------------------------------
//
// A library built without --shared-runtime carries its own copy of the
// runtime, and on macOS and Windows that copy stays apart from the
// program's: its levels are its own. Called from inside another copy's
// enforce block (through a host service), it cannot read that block's
// grants, so it must not allow what they would refuse. Every copy counts
// the levels each thread has in all of them in one place, the rendezvous of
// the first copy it finds in the process (the earliest loaded that exports
// one), so a copy sees when this thread is inside levels it cannot read,
// and refuses (aether_sandbox_check_slow). On one runtime image all of this
// is one copy, and the count is its own.

/* The rendezvous's layout (#2957): its version and its size come first, so
 * a copy reads nothing else of one laid out otherwise. Version 1 had no
 * size. */
#define AETHER_SANDBOX_RV_VERSION 2

typedef struct AetherSandboxRendezvous {
    uint32_t version;
    uint32_t size;                // sizeof(AetherSandboxRendezvous)
    atomic_int* threads;          // threads with a level in force, in any copy
    int (*levels)(int delta);     // this thread's levels in every copy: adds delta, returns the total
} AetherSandboxRendezvous;

static atomic_int g_threads;
static AETHER_TLS_SHARED int t_total;

static int rv_levels(int delta) {
    int before = t_total;
    int after = before + delta;
    if (after < 0) after = 0;
    t_total = after;
    /* Read only by this thread's own checks: another thread seeing a stale
     * count takes the slow path and finds nothing of its own, or skips a
     * level that is not its own. */
    if (before == 0 && after > 0) atomic_fetch_add_explicit(&g_threads, 1, memory_order_relaxed);
    else if (before > 0 && after == 0) atomic_fetch_sub_explicit(&g_threads, 1, memory_order_relaxed);
    return after;
}

static const AetherSandboxRendezvous g_own_rv = {
    AETHER_SANDBOX_RV_VERSION, (uint32_t)sizeof(AetherSandboxRendezvous), &g_threads, rv_levels
};

/* Looked up by name in the other copies, so exported from each. */
#if defined(__GNUC__) || defined(__clang__)
__attribute__((visibility("default"), used))
#endif
const AetherSandboxRendezvous* aether_sandbox_rendezvous(void) {
    return &g_own_rv;
}

static const AetherSandboxRendezvous* _Atomic g_rv = NULL;
/* aether_sandbox_in_force is aether_panic.c's, where the step barrier reads
 * it without linking this file (#3393). */

/* A step's part (aether_step_barrier.h, #3393), reached through
 * aether_panic.c's pointers, set with the unwind's below. */
static int sandbox_step_hide(int saved[2]);
static void sandbox_step_show(const int saved[2]);
extern int (*_Atomic aether_step_sandbox_hide)(int saved[2]);
extern void (*_Atomic aether_step_sandbox_show)(const int saved[2]);

typedef const AetherSandboxRendezvous* (*rendezvous_fn)(void);

#define RV_SYMBOL "aether_sandbox_rendezvous"

/* The first loaded image that exports one (aether_rendezvous_find, in
 * aether_resource_caps.c, which the execution accounts share). */
void* aether_rendezvous_find(const char* symbol);

static const AetherSandboxRendezvous* find_rendezvous(void) {
    void* p = aether_rendezvous_find(RV_SYMBOL);
    if (!p) return NULL;
    rendezvous_fn f;
    memcpy(&f, &p, sizeof(f));
    return f();
}

/* aether_panic.c's: how a panic ends the levels pushed inside the frame it
 * leaves. Set here, before any level of this copy can exist (every push
 * looks for the copies first), so that a program that never enforces does
 * not link this file for its panics. */
extern void (*_Atomic aether_panic_sandbox_unwind)(int frames);

static const AetherSandboxRendezvous* rv(void) {
    const AetherSandboxRendezvous* r = atomic_load_explicit(&g_rv, memory_order_acquire);
    if (r) return r;
    /* Before g_rv is published: a thread that sees g_rv set sees this. */
    atomic_store_explicit(&aether_panic_sandbox_unwind, aether_sandbox_unwind_to_frame,
                          memory_order_relaxed);
    /* Before aether_sandbox_in_force, which the step barrier reads first. */
    atomic_store_explicit(&aether_step_sandbox_hide, sandbox_step_hide, memory_order_relaxed);
    atomic_store_explicit(&aether_step_sandbox_show, sandbox_step_show, memory_order_relaxed);
    const AetherSandboxRendezvous* found = find_rendezvous();
    if (found && found != &g_own_rv &&
        (found->version != AETHER_SANDBOX_RV_VERSION ||
         found->size != (uint32_t)sizeof(AetherSandboxRendezvous))) {
        /* Another layout (another Aether): only its version and size were
         * read. This copy counts its own levels apart, as copies that never
         * found each other do, and says so once. */
        fprintf(stderr,
                "aether: sandbox: this runtime copy cannot share sandbox levels with the one "
                "loaded first (levels version %u, %u bytes, against %u, %u): the levels that "
                "copy enforces are not seen here; build the libraries with one Aether "
                "version, or with --shared-runtime\n",
                (unsigned)AETHER_SANDBOX_RV_VERSION, (unsigned)sizeof(AetherSandboxRendezvous),
                (unsigned)found->version, (unsigned)found->size);
        found = NULL;
    }
    if (!found) found = &g_own_rv;
    const AetherSandboxRendezvous* expected = NULL;
    atomic_compare_exchange_strong_explicit(&g_rv, &expected, found,
                                            memory_order_acq_rel, memory_order_acquire);
    r = atomic_load_explicit(&g_rv, memory_order_acquire);
    atomic_store_explicit(&aether_sandbox_in_force, r->threads, memory_order_release);
    /* A step looks at the count from now on: its one word says so. */
    atomic_fetch_or_explicit(&aether_caps_slow, AETHER_CAPS_SLOW_SANDBOX, memory_order_release);
    return r;
}

// ---------------------------------------------------------------------------
// This thread's levels
// ---------------------------------------------------------------------------

typedef struct {
    void* grants;        // borrowed from the pusher; NULL allows (or a barrier)
    const void* image;   // the enforce site's generated code, NULL for any other push
    int site;
    int skip_to;         // a trusted call's barrier: the level it resumes below; -1 otherwise
    int frame;           // the try frames live at the push (aether_try_depth)
} SandboxLevel;

typedef struct {
    SandboxLevel level[AETHER_SANDBOX_MAX_LEVELS];
    int depth;
    /* The levels below are the code's an actor step runs inside (#3393):
     * put aside for the step, which is checked against its own alone. */
    int floor;
    const void* pending_image;
    int pending_site;
} SandboxThread;

static AETHER_TLS_SHARED SandboxThread t_sbx;

static void push_level(SandboxThread* t, void* grants, const void* image, int site, int skip_to) {
    const AetherSandboxRendezvous* r = rv();
    if (t->depth >= AETHER_SANDBOX_MAX_LEVELS) {
        /* Left out, the level's grants would not apply, and its pop would
         * take an outer level off instead (a widening, both ways). */
        aether_panic("sandbox: more than 64 nested levels (enforce blocks, trusted calls, host run_sandboxed calls) on one thread");
        return;
    }
    SandboxLevel* v = &t->level[t->depth];
    v->grants = grants;
    v->image = image;
    v->site = site;
    v->skip_to = skip_to;
    v->frame = aether_try_depth();
    t->depth++;
    r->levels(1);
}

void aether_sandbox_push(void* grants) {
    SandboxThread* t = &t_sbx;
    const void* image = t->pending_image;
    int site = t->pending_site;
    t->pending_image = NULL;
    t->pending_site = 0;
    push_level(t, grants, image, site, -1);
}

void aether_sandbox_pop(void) {
    SandboxThread* t = &t_sbx;
    if (t->depth <= t->floor) return;   /* none of its own: an enclosing step's are not its to take */
    t->depth--;
    rv()->levels(-1);
}

int aether_sandbox_depth(void) {
    return t_sbx.depth;
}

void aether_sandbox_restore(int depth) {
    SandboxThread* t = &t_sbx;
    if (depth < t->floor) depth = t->floor;
    if (depth >= t->depth) return;
    int left = t->depth - depth;
    t->depth = depth;
    rv()->levels(-left);
}

void aether_sandbox_tag_site(const void* image, int site) {
    SandboxThread* t = &t_sbx;
    t->pending_image = image;
    t->pending_site = site;
}

/* A trusted call runs with the authority of the code that wrote the
 * enforce: a barrier level whose skip_to names the level that enforce
 * pushed, which the check jumps from to below it, so the levels between
 * (the block's grants, and any enforce inside it) do not apply. Never
 * higher: the site is looked for only among the levels in force (not ones
 * an earlier barrier hides), and one found nowhere (a block that escaped
 * its enforce, a level a panic left) pushes nothing. A barrier only ever
 * adds a level above the ones it hides, so nothing pushed inside reaches
 * them. */
int aether_sandbox_trust_enter(const void* image, int site) {
    SandboxThread* t = &t_sbx;
    int saved = t->depth;
    if (!image) return saved;
    for (int l = t->depth - 1; l >= t->floor; l--) {
        if (t->level[l].skip_to >= 0) { l = t->level[l].skip_to; continue; }
        if (t->level[l].image == image && t->level[l].site == site) {
            push_level(t, NULL, NULL, 0, l);
            break;
        }
    }
    return saved;
}

void aether_sandbox_unwind_to_frame(int frames) {
    SandboxThread* t = &t_sbx;
    t->pending_image = NULL;
    t->pending_site = 0;
    int d = t->depth;
    while (d > t->floor && t->level[d - 1].frame >= frames) d--;
    aether_sandbox_restore(d);
}

/* A step begins (aether_step_barrier.h, #3393): the levels of the code it
 * runs inside, in this copy and in every other on this thread, are put
 * aside, so the step is checked as its actor is on a thread of its own,
 * against nothing but the levels it pushes itself. 0 when the thread had
 * none. A step that ends gives them back, its own levels gone first (its
 * pops, or its panic's unwind, took them; any left are taken here). */
static int sandbox_step_hide(int saved[2]) {
    SandboxThread* t = &t_sbx;
    const AetherSandboxRendezvous* r = rv();
    int total = r->levels(0);
    if (total == 0 && t->depth == t->floor) return 0;
    saved[0] = t->floor;
    saved[1] = total;
    t->floor = t->depth;
    if (total) r->levels(-total);
    return 1;
}

static void sandbox_step_show(const int saved[2]) {
    SandboxThread* t = &t_sbx;
    aether_sandbox_restore(t->floor);
    t->floor = saved[0];
    const AetherSandboxRendezvous* r = rv();
    int now = r->levels(0);
    if (saved[1] != now) r->levels(saved[1] - now);
}

// ---------------------------------------------------------------------------
// The check
// ---------------------------------------------------------------------------

static int grants_allow(void* grants, const char* category, const char* resource) {
    if (!grants) return 1;
    int n = list_size(grants);
    if (n == 0) return 0;
    for (int i = 0; i + 1 < n; i += 2) {
        const void* cat_v = list_get_raw(grants, i);
        const void* pat_v = list_get_raw(grants, i + 1);
        if (!cat_v || !pat_v) continue;
        const char* cat = aether_string_data(cat_v);
        const char* pat = aether_string_data(pat_v);
        if (!cat || !pat) continue;
        if (cat[0] == '*' && pat[0] == '*') return 1;
        if (strcmp(cat, category) == 0 && aether_grant_match(category, pat, resource)) return 1;
    }
    return 0;
}

static atomic_int g_foreign_reported;

/* 1 allowed, 0 refused, -1 nothing in force on this thread. */
static int decide(const char* category, const char* resource) {
    SandboxThread* t = &t_sbx;
    int total = rv()->levels(0);
    if (total == 0 && t->depth == t->floor) return -1;
    if (total > t->depth - t->floor) {
        /* Levels of another copy of the runtime are in force on this
         * thread, and their grants cannot be read from here. */
        if (!atomic_exchange_explicit(&g_foreign_reported, 1, memory_order_relaxed))
            fprintf(stderr,
                    "aether: sandbox: this thread is inside an enforce block of another copy of "
                    "the runtime (a library built without --shared-runtime), whose grants this "
                    "copy cannot read; refusing %s %s. Build the libraries with --shared-runtime "
                    "to nest sandboxes across them. (reported once)\n",
                    category ? category : "", resource ? resource : "");
        aether_sandbox_audit(category, resource, 0);
        return 0;
    }
    /* From the top down, a trusted call's barrier jumping over the levels
     * it hides. With none left in force the check is the one an unsandboxed
     * program makes: allowed, and not audited. */
    int allowed = 1;
    int in_force = 0;
    for (int l = t->depth - 1; l >= t->floor; l--) {
        if (t->level[l].skip_to >= 0) { l = t->level[l].skip_to; continue; }
        in_force = 1;
        if (!grants_allow(t->level[l].grants, category, resource)) { allowed = 0; break; }
    }
    if (!in_force) return 1;
    aether_sandbox_audit(category, resource, allowed);
    return allowed;
}

// The check sees an fs path where it leads (aether_sandbox_path.h). A path
// that cannot be resolved is refused, not matched as written.
int aether_sandbox_check_slow(const char* category, const char* resource) {
    const AetherSandboxRendezvous* r = rv();
    if (atomic_load_explicit(r->threads, memory_order_relaxed) == 0) return 1;
    if (!category) category = "";
    if (resource && category[0] == 'f' && category[1] == 's' &&
        (category[2] == '\0' || category[2] == '_')) {
        if (r->levels(0) == 0 && t_sbx.depth == t_sbx.floor) return 1;
        char resolved[PATH_MAX];
        if (!aether_sandbox_canon_path(resource, resolved, sizeof(resolved))) return 0;
        return decide(category, resolved) != 0;
    }
    return decide(category, resource) != 0;
}

int aether_sandbox_levels_here(void) {
    int total = rv()->levels(0);
    int own = t_sbx.depth - t_sbx.floor;
    return total > own ? total : own;
}

int aether_sandbox_check_resolved(const char* category, const char* resource) {
    const AetherSandboxRendezvous* r = rv();
    if (atomic_load_explicit(r->threads, memory_order_relaxed) == 0) return -1;
    return decide(category ? category : "", resource);
}

// A grant's pattern in the form the checks compare against: an fs pattern's
// fixed directory resolved (std.sandbox's grant_fs_* call this), anything
// else copied. Returns a malloc'd string the grant list owns.
char* aether_sandbox_grant_pattern(const char* category, const char* pattern) {
    if (!pattern) return NULL;
    if (category && category[0] == 'f' && category[1] == 's') {
        char resolved[PATH_MAX];
        if (aether_sandbox_canon_pattern(pattern, resolved, sizeof(resolved))) return strdup(resolved);
    }
    return strdup(pattern);
}
#endif
