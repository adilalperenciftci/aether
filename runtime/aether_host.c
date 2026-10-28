/*
 * aether_host.c — Implementation of the host-callback dispatch table.
 *
 * Single linear-search registry capped at AETHER_HOST_MAX_EVENTS. Linear
 * search keeps the data layout obvious and is fine for small N — most
 * namespaces declare 5-20 events, not hundreds. If a namespace ever
 * needs more, the cap can be raised; a hash table would be premature.
 */

#include "aether_host.h"
#include "utils/aether_compiler.h"
#include "aether_exec.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifndef AETHER_HOST_MAX_EVENTS
#define AETHER_HOST_MAX_EVENTS 64
#endif

typedef struct {
    /* event_name is a borrowed pointer — the caller (typically the host
     * Java/Python/Go SDK) owns the storage for the lifetime of the
     * registration. The generated host SDKs use string literals, so
     * lifetime is the program's lifetime in practice. */
    const char* event_name;
    aether_event_handler_t handler;
} EventEntry;

static EventEntry g_events[AETHER_HOST_MAX_EVENTS];
static int        g_event_count = 0;

static int find_event_index(const char* name) {
    if (!name) return -1;
    for (int i = 0; i < g_event_count; i++) {
        if (g_events[i].event_name &&
            strcmp(g_events[i].event_name, name) == 0) {
            return i;
        }
    }
    return -1;
}

int aether_event_register(const char* event_name, aether_event_handler_t handler) {
    if (!event_name || !handler) return -1;

    /* Replace existing entry if the name is already registered. */
    int existing = find_event_index(event_name);
    if (existing >= 0) {
        g_events[existing].handler = handler;
        return 0;
    }

    if (g_event_count >= AETHER_HOST_MAX_EVENTS) return -1;

    g_events[g_event_count].event_name = event_name;
    g_events[g_event_count].handler    = handler;
    g_event_count++;
    return 0;
}

int aether_event_unregister(const char* event_name) {
    int idx = find_event_index(event_name);
    if (idx < 0) return -1;

    /* Compact the array — preserves order, which we don't promise but
     * also don't deny. Cheap at small N. */
    for (int i = idx; i < g_event_count - 1; i++) {
        g_events[i] = g_events[i + 1];
    }
    g_event_count--;
    g_events[g_event_count].event_name = NULL;
    g_events[g_event_count].handler    = NULL;
    return 0;
}

void aether_event_clear(void) {
    for (int i = 0; i < g_event_count; i++) {
        g_events[i].event_name = NULL;
        g_events[i].handler    = NULL;
    }
    g_event_count = 0;
}

int notify(const char* event_name, int64_t id) {
    int idx = find_event_index(event_name);
    if (idx < 0) return 0;
    /* When loaded as a .so by a host (Java/Python/Ruby), stdout is
     * fully buffered. Flush before handing control to the host event
     * handler so Aether's preceding prints surface in the right order. */
    fflush(NULL);
    g_events[idx].handler(id);
    return 1;
}

/* ---------------------------------------------------------------------
 * Manifest registry
 *
 * String fields are borrowed pointers into Aether's interned-string
 * storage. The manifest .ae script lives for the lifetime of the
 * compile; the pipeline reads g_manifest before the script is freed.
 * --------------------------------------------------------------------- */

static AetherManifest g_manifest = {0};

/* Each builder ignores _ctx — the manifest registry is global state.
 * The _ctx parameter is here purely to satisfy the codegen's auto-
 * injection rule so the manifest DSL reads idiomatically inside a
 * trailing block: `abi() { describe("trading") { input(...) } }`. */

void describe(void* _ctx, const char* name) {
    (void)_ctx;
    g_manifest.namespace_name = name;
}

void input(void* _ctx, const char* name, const char* type_signature) {
    (void)_ctx;
    if (g_manifest.input_count >= AETHER_MANIFEST_MAX_INPUTS) return;
    g_manifest.inputs[g_manifest.input_count].name           = name;
    g_manifest.inputs[g_manifest.input_count].type_signature = type_signature;
    g_manifest.input_count++;
}

void event(void* _ctx, const char* name, const char* carries_type) {
    (void)_ctx;
    if (g_manifest.event_count >= AETHER_MANIFEST_MAX_EVENTS) return;
    g_manifest.events[g_manifest.event_count].name         = name;
    g_manifest.events[g_manifest.event_count].carries_type = carries_type;
    g_manifest.event_count++;
}

void bindings(void* _ctx) {
    (void)_ctx;
    /* Visual grouping; no state to mutate. */
}

void java(void* _ctx, const char* package_name, const char* class_name) {
    (void)_ctx;
    g_manifest.java.package_name = package_name;
    g_manifest.java.class_name   = class_name;
}

void python(void* _ctx, const char* module_name) {
    (void)_ctx;
    g_manifest.python.module_name = module_name;
}

void ruby(void* _ctx, const char* module_name) {
    (void)_ctx;
    g_manifest.ruby.module_name = module_name;
}

void go(void* _ctx, const char* package_name) {
    (void)_ctx;
    g_manifest.go.package_name = package_name;
}

AetherManifest* manifest_get(void) {
    /* Return NULL when nothing has been declared so callers can
     * distinguish "no manifest run" from "empty manifest". */
    if (!g_manifest.namespace_name) return NULL;
    return &g_manifest;
}

void manifest_clear(void) {
    /* memset is safe here: the strings we hold are borrowed pointers
     * we never owned. The Aether-side string storage takes care of
     * its own lifetime. */
    AetherManifest empty = {0};
    g_manifest = empty;
}

/* ---------------------------------------------------------------------
 * Caller-info channel (issue #344). One TLS slot per thread; the host
 * deep-copies (identity + key/value pairs) into a bounded buffer at
 * aether_set_caller time so the host's source strings can be freed
 * after the call returns. The Aether-side accessors return borrowed
 * pointers into the same buffer.
 *
 * Layout: a single TLS arena of AETHER_CALLER_INFO_MAX_BYTES bytes
 * holds every NUL-terminated string back-to-back. Two parallel arrays
 * of offsets index into the arena for keys and values. The identity
 * string is stored at offset 0 (or kept absent when set NULL).
 *
 * Lookup is O(n) — the per-call cap (AETHER_CALLER_INFO_MAX_ATTRS,
 * default 32) is small enough that a linear scan beats anything with
 * hash overhead.
 * --------------------------------------------------------------------- */

typedef struct {
    /* arena holds NUL-terminated strings; arena_used is the byte
     * cursor. identity_off == -1 means "no identity set". */
    char  arena[AETHER_CALLER_INFO_MAX_BYTES];
    int   arena_used;
    int   identity_off;
    int   attr_count;
    int   key_off[AETHER_CALLER_INFO_MAX_ATTRS];
    int   val_off[AETHER_CALLER_INFO_MAX_ATTRS];
    int64_t deadline_ms;
    int   present;  /* 0 = slot wiped (defaults), 1 = set */
} AetherCallerInfo;

/* AETHER_TLS_SHARED rather than AETHER_TLS: aether_host.o is pulled
 * into both the main `ae` executable AND every `--emit=lib` .so
 * (because the .so calls notify() / manifest builders). The default
 * Initial-Exec TLS model emits R_X86_64_TPOFF32 relocations that
 * the linker rejects when building a shared object; the
 * Global-Dynamic model in AETHER_TLS_SHARED works in both contexts
 * with a sub-nanosecond extra GOT indirection per access.
 *
 * tls_caller is the setting: what aether_set_caller wrote last, what the
 * next execution entered sees, and what code outside any execution
 * reads. An execution reads the setting it was entered with: tls_caller
 * itself, until a host service it called sets another while it runs. Then
 * the running executions that still read tls_caller get a copy of it
 * first (t_view, one block shared by them, counted), and when an
 * execution with a copy returns, the copy is the setting again (#2955).
 * The copy is made only on that path: an export call costs nothing here. */
static AETHER_TLS_SHARED AetherCallerInfo tls_caller = { .identity_off = -1 };

typedef struct {
    int refs;
    AetherCallerInfo info;
} CallerView;

static AETHER_TLS_SHARED CallerView* t_view[AETHER_EXEC_MAX_DEPTH + 1];

static const AetherCallerInfo* caller_seen(void) {
    int d = aether_exec_depth();
    if (d > 0 && d <= AETHER_EXEC_MAX_DEPTH && t_view[d]) return &t_view[d]->info;
    return &tls_caller;
}

/* Before the setting changes while executions run: each that reads it
 * keeps what it saw. 0 when there was no room for the copy. */
static int caller_keep_views(void) {
    int d = aether_exec_depth();
    if (d > AETHER_EXEC_MAX_DEPTH) d = AETHER_EXEC_MAX_DEPTH;
    int need = 0;
    for (int k = 1; k <= d; k++) if (!t_view[k]) need++;
    if (need == 0) return 1;
    CallerView* v = (CallerView*)malloc(sizeof(CallerView));
    if (!v) return 0;
    v->refs = need;
    v->info = tls_caller;
    for (int k = 1; k <= d; k++) {
        if (t_view[k]) continue;
        t_view[k] = v;
        aether_exec_mark_view(k);
    }
    return 1;
}

void aether_caller_leave(int depth) {
    if (depth < 1 || depth > AETHER_EXEC_MAX_DEPTH) return;
    CallerView* v = t_view[depth];
    if (!v) return;
    t_view[depth] = NULL;
    tls_caller = v->info;
    if (--v->refs == 0) free(v);
}

/* Append a NUL-terminated copy of `s` to the arena. Returns the
 * starting offset on success, or -1 if there isn't room. */
static int caller_arena_dup(AetherCallerInfo* ci, const char* s) {
    if (!s) return -1;
    size_t n = strlen(s) + 1;  /* include NUL */
    if (ci->arena_used + (int)n > AETHER_CALLER_INFO_MAX_BYTES) return -1;
    int off = ci->arena_used;
    memcpy(ci->arena + off, s, n);
    ci->arena_used += (int)n;
    return off;
}

int aether_set_caller(const char* identity,
                      const char** attr_keys,
                      const char** attr_vals,
                      size_t n,
                      int64_t deadline_ms) {
    if (n > AETHER_CALLER_INFO_MAX_ATTRS) return -1;
    if (n > 0 && (!attr_keys || !attr_vals)) return -1;

    /* Stage into a fresh struct so a partial copy on overflow leaves
     * the previous TLS state intact. */
    AetherCallerInfo staged = { .identity_off = -1, .deadline_ms = deadline_ms };

    if (identity) {
        int off = caller_arena_dup(&staged, identity);
        if (off < 0) return -1;
        staged.identity_off = off;
    }

    for (size_t i = 0; i < n; i++) {
        if (!attr_keys[i] || !attr_vals[i]) return -1;
        int koff = caller_arena_dup(&staged, attr_keys[i]);
        if (koff < 0) return -1;
        int voff = caller_arena_dup(&staged, attr_vals[i]);
        if (voff < 0) return -1;
        staged.key_off[i] = koff;
        staged.val_off[i] = voff;
    }
    staged.attr_count = (int)n;
    staged.present    = 1;

    /* The running executions keep what they were entered with. */
    if (!caller_keep_views()) return -1;
    /* Commit. Single struct copy, no torn write across fields. */
    tls_caller = staged;
    return 0;
}

void aether_clear_caller(void) {
    /* Without room to keep the running executions' views, nothing changes. */
    if (!caller_keep_views()) return;
    AetherCallerInfo empty = { .identity_off = -1 };
    tls_caller = empty;
}

const char* aether_caller_identity(void) {
    const AetherCallerInfo* ci = caller_seen();
    if (!ci->present || ci->identity_off < 0) return "";
    return ci->arena + ci->identity_off;
}

const char* aether_caller_attribute(const char* key) {
    const AetherCallerInfo* ci = caller_seen();
    if (!key || !ci->present) return "";
    for (int i = 0; i < ci->attr_count; i++) {
        const char* k = ci->arena + ci->key_off[i];
        if (strcmp(k, key) == 0) {
            return ci->arena + ci->val_off[i];
        }
    }
    return "";
}

int64_t aether_caller_deadline_ms(void) {
    const AetherCallerInfo* ci = caller_seen();
    if (!ci->present) return 0;
    return ci->deadline_ms;
}
