/* libaether.h — public C API for embedders of `--emit=lib` Aether
 * code.
 *
 * Stable C interface that host programs (Java/Python/Go embedders,
 * plugin systems, language gateways) link against to drive
 * Aether-generated `.so` / `.a` artifacts.
 *
 * Today this surface exposes the per-call resource caps from issue
 * #343 (memory ceiling + wall-clock deadline). Future additions
 * land as additive symbols — never break the existing names.
 *
 * The Aether build emits codegen-level calls into this surface
 * automatically when `--emit=lib` is set. Embedders that drive
 * those caps from outside (typical plugin host) include this
 * header and link `libaether.a` (or the platform shared variant).
 */

#ifndef LIBAETHER_H
#define LIBAETHER_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Symbol-visibility export. Builds with `-fvisibility=hidden`
 * still expose these as default-visibility public symbols. */
#if defined(__GNUC__) || defined(__clang__)
#  define AETHER_API __attribute__((visibility("default")))
#elif defined(_MSC_VER)
#  define AETHER_API __declspec(dllexport)
#else
#  define AETHER_API
#endif

/* Process-wide memory cap. After this call, every subsequent
 * cap-aware allocator (string, list, map, arena, pool) refuses
 * allocations that would push current usage past `bytes` and
 * returns NULL / its error-string convention. Pass `0` to
 * disable (unlimited).
 *
 * Already-accounted allocations are unaffected — only new
 * allocations are gated. Existing ones drain via their normal
 * free paths and decrement the counter.
 *
 * Thread-safe: relaxed atomic store. */
AETHER_API void aether_set_memory_cap(uint64_t bytes);

/* Per-thread wall-clock deadline. After this call, every
 * codegen-emitted tripwire (at every loop head in `--emit=lib`
 * builds) checks `now >= deadline_at`. On positive trip the
 * sticky flag flips, and `aether_deadline_tripped()` returns 1
 * for every subsequent call until you arm a fresh deadline.
 *
 * Pass `0` to disable. Calling with a non-zero value clears the
 * sticky flag (a fresh deadline is a fresh chance). */
AETHER_API void aether_set_call_deadline(int64_t ms);

/* Codegen-tripwire target. Returns 1 when the per-thread deadline
 * has passed OR when `__aether_abort_call` was explicitly invoked
 * since the last `aether_set_call_deadline`. Returns 0 otherwise.
 *
 * Embedders typically don't call this directly — the codegen
 * emits checks at every loop head. The host's job is to set the
 * deadline before invoking the entry function and inspect any
 * error string the entry returns. */
AETHER_API int aether_deadline_tripped(void);

/* How the last call into an export on this thread ended (#2956). Every
 * aether_<name> export runs inside an execution frame: a panic the export
 * does not catch ends the call, not the process, and the export returns
 * the zero value of its result (NULL for a string, which the release
 * accepts). A zero value with an outcome other than AETHER_OK is not a
 * result; release only what an AETHER_OK call returned. The library is
 * usable again at once; nothing done before the failure is rolled back.
 *
 * Nested calls (an export calls a host service, which calls an export)
 * each have their own outcome, and the outer call's caller info,
 * deadline and sandbox grants are back when the inner one returns, on
 * every exit. The frame costs a context save per call (about 5.8 ns on
 * Windows MinGW for an export that calls a function; none for one that
 * can neither panic, allocate, loop nor call anything): docs/emit-lib.md,
 * "Failures and nested calls at the boundary". */
#ifndef AETHER_OK
#define AETHER_OK             0   /* returned normally */
#define AETHER_PANICKED       1   /* a panic the export did not catch */
#define AETHER_DEADLINE       2   /* its deadline passed (see above) */
#define AETHER_CANCELLED      3   /* cancelled from another thread */
#define AETHER_MEMORY_CAP     4   /* past the memory cap */
#define AETHER_OUT_OF_MEMORY  5   /* an allocation failed */
#endif
AETHER_API int aether_last_outcome(void);

/* The last outcome's reason: "" for AETHER_OK, the panic's message (cut at
 * 1023 bytes) or a fixed description otherwise. Borrowed: valid until the
 * next call into the library on this thread. */
AETHER_API const char* aether_last_outcome_text(void);

#ifdef __cplusplus
}
#endif

#endif  /* LIBAETHER_H */
