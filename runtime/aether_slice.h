#ifndef AETHER_SLICE_H
#define AETHER_SLICE_H

/* First-class slices (#1286): the C shape of an Aether `T[]`.
 *
 * A slice is a fat pointer, `{ ptr, len }`, that does NOT own the
 * elements it points at. The element type is static (the Aether
 * typechecker knows it); the generated C scales an index by sizeof(T)
 * itself, so one struct serves every element type.
 *
 * `len` is the element count. AETHER_SLICE_UNBOUNDED marks a VIEW whose
 * length the compiler could not know: a bare `ptr as T[]`, or a `T[]`
 * handed back by an extern C function. Such a view indexes without a
 * bounds check (exactly what `T[]` meant before slices carried a length)
 * and reports `.len` as -1. Sub-slicing it with an explicit end
 * (`v[0..n]`) yields a bounded slice.
 *
 * Every helper is `static inline`: the header is textually included by
 * each generated program, so a program that never touches a slice pays
 * nothing, and there is no runtime symbol to link. A failed check goes
 * through aether_panic(), the same unwind `panic("...")` uses, so a
 * `try` block can catch it and an actor step dies cleanly. */

#include <stddef.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include "actors/aether_panic.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct AetherSlice {
    void*    ptr;
    uint64_t len;
    /* #3025: AETHER_SLICE_READONLY, or 0. Beside `len` and read only where
     * an element is stored, so a read costs what it did. */
    uint32_t flags;
} AetherSlice;

#define AETHER_SLICE_UNBOUNDED UINT64_MAX

/* #3025: a view of memory the program may read and not write: the bytes of
 * a string (`string.bytes(s)`), a literal's in read-only data or a counted
 * string's that others share. A store through it panics, by name, where an
 * element store is bounds-checked; every view made from it (a sub-slice, a
 * pattern's tail, a copy) carries the mark. */
#define AETHER_SLICE_READONLY 1u

/* #3072: a view of elements another slice or an array holds: a sub-slice of
 * a bounded slice (or one at an offset of any view), a list pattern's tail,
 * an array viewed as a slice. It owns nothing (R1, R2), so `free` of it is
 * a named panic, as `free` of a read-only view is: the allocator would take
 * a pointer it never handed out, or one the owner still holds. A view of a
 * raw pointer bounded at its start, `(p as T[])[0..n]`, is how a program
 * holds a buffer it owns, and is not marked. */
#define AETHER_SLICE_BORROWED 2u

/* #3159: the buffer `make([]T, n)` handed out. Its elements are places: a
 * store into one takes the value (#2921), so `free` gives back what each
 * holds before the buffer goes. A view of a raw pointer is not marked: its
 * elements are C's, and a store there takes nothing. */
#define AETHER_SLICE_MADE 4u

/* `const void*`: a view is made over an array of strings too, `const char*
 * xs[N]`. Taken as `void*`, cl.exe read the elements' `const` as the array's
 * and refused the call (C4090, an error under the MSVC check, #2799); the
 * view itself is untyped either way. */
static inline AetherSlice aether_slice_make(const void* ptr, uint64_t len) {
    AetherSlice s;
    s.ptr = (void*)ptr;
    s.len = len;
    s.flags = 0;
    return s;
}

/* #3025: `s` as a read-only view: the same elements, a store through it a
 * panic. */
static inline AetherSlice aether_slice_readonly(AetherSlice s) {
    s.flags |= AETHER_SLICE_READONLY;
    return s;
}

/* #3072: `s` as a view of elements something else holds (an array viewed
 * as a slice, a list pattern's tail): `free` of it panics. */
static inline AetherSlice aether_slice_borrowed(AetherSlice s) {
    s.flags |= AETHER_SLICE_BORROWED;
    return s;
}

/* A view of `s`'s memory at `ptr`, `len` long, with `s`'s marks: a
 * sub-slice, a list pattern's tail. */
static inline AetherSlice aether_slice_derive(AetherSlice s, const void* ptr, uint64_t len) {
    AetherSlice d = aether_slice_make(ptr, len);
    d.flags = s.flags;
    return d;
}

/* A view over a raw pointer of unknown extent. */
static inline AetherSlice aether_slice_view(void* ptr) {
    return aether_slice_make(ptr, AETHER_SLICE_UNBOUNDED);
}

/* `make([]T, n)`: a fresh zeroed buffer of n elements, viewed as a slice.
 * The caller frees it with `free(s)` (aether_slice_free). */
static inline AetherSlice aether_slice_alloc(int64_t count, size_t elem_size) {
    if (count < 0) {
        aether_panic("make([]T, n): negative element count");
    }
    void* p = calloc(count > 0 ? (size_t)count : 1, elem_size);
    if (!p) aether_out_of_memory("make([]T, n): out of memory");
    AetherSlice s = aether_slice_make(p, (uint64_t)count);
    s.flags = AETHER_SLICE_MADE;
    return s;
}

/* `.len` — -1 for an unbounded view. */
static inline int64_t aether_slice_len(AetherSlice s) {
    return s.len == AETHER_SLICE_UNBOUNDED ? -1 : (int64_t)s.len;
}

/* #2932: a failed check panics with its message built whole, a long source
 * path in it included, as a counted string the catch that receives it owns.
 * Declared as the generated program declares them; std/string defines both. */
void* aether_interp_string(const char* fmt, va_list ap);
void string_release(const char* s);

static inline void aether_slice_release_msg(const void* p) {
    string_release((const char*)p);
}

static inline void aether_slice_panicf(const char* fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    void* msg = aether_interp_string(fmt, ap);
    va_end(ap);
    if (!msg) aether_panic("slice bounds check failed (out of memory for its message)");
    aether_panic_owned((const char*)msg, aether_slice_release_msg);
}

static inline void aether_slice_fail_index(int64_t idx, uint64_t len,
                                           const char* file, int line) {
    aether_slice_panicf("%s:%d: slice index %lld out of range for length %llu",
                        file, line, (long long)idx, (unsigned long long)len);
}

/* #3113: an index into a fixed-size array `T[N]` outside `0 ..< N`, the
 * slice's panic with the array's length. */
static inline void aether_array_fail_index(int64_t idx, uint64_t len,
                                           const char* file, int line) {
    aether_slice_panicf("%s:%d: array index %lld out of range for length %llu",
                        file, line, (long long)idx, (unsigned long long)len);
}

/* #3113: `a[i]` on a `T[N]`: `i`, checked against N, for the generated C
 * to index with (`a[aether_array_index(i, N, ...)]`), so the element stays
 * an lvalue and `i` is evaluated once. A negative index is out of range.
 * With a constant N and a loop bounded by it the C compiler drops the
 * test. */
static inline int64_t aether_array_index(int64_t i, uint64_t len,
                                         const char* file, int line) {
    if ((uint64_t)i >= len) aether_array_fail_index(i, len, file, line);
    return i;
}

static inline void aether_slice_fail_range(int64_t lo, int64_t hi, uint64_t len,
                                           const char* file, int line) {
    aether_slice_panicf("%s:%d: slice range %lld..%lld out of range for length %llu",
                        file, line, (long long)lo, (long long)hi,
                        (unsigned long long)len);
}

/* `s[i]` — the address of element i, checked against len (an unbounded
 * view is not checked). Returns a byte pointer; the generated C casts it
 * to `T*` and dereferences, which keeps the result an lvalue for
 * `s[i] = v` and evaluates `s` exactly once. */
static inline void* aether_slice_at(AetherSlice s, int64_t i, size_t elem_size,
                                    const char* file, int line) {
    if (s.len != AETHER_SLICE_UNBOUNDED && (uint64_t)i >= s.len) {
        aether_slice_fail_index(i, s.len, file, line);
    }
    return (char*)s.ptr + (uint64_t)i * elem_size;
}

static inline void aether_slice_fail_readonly(const char* file, int line) {
    aether_slice_panicf("%s:%d: a write through a read-only view of a string", file, line);
}

/* #3025: `s[i] = v`, `s[i] += v`, `s[i]++`: the element's address for a
 * store, which a read-only view (`string.bytes(s)`) refuses with a named
 * panic, checked beside the bounds. A read goes through aether_slice_at
 * and tests nothing more than it did. */
static inline void* aether_slice_at_w(AetherSlice s, int64_t i, size_t elem_size,
                                      const char* file, int line) {
    if (s.flags & AETHER_SLICE_READONLY) aether_slice_fail_readonly(file, line);
    return aether_slice_at(s, i, elem_size, file, line);
}

/* #3029: `s[i]` in a function's view body, where the function's entry has
 * tested once that `s` is an unbounded view: the element's address with no
 * test, which is what aether_slice_at does for a view after its test of
 * the sentinel. Without that test in the loop the compiler can vectorize. */
static inline void* aether_slice_view_at(AetherSlice s, int64_t i, size_t elem_size) {
    return (char*)s.ptr + (uint64_t)i * elem_size;
}

/* #3029: a store there, which still refuses a read-only view. */
static inline void* aether_slice_view_at_w(AetherSlice s, int64_t i, size_t elem_size,
                                           const char* file, int line) {
    if (s.flags & AETHER_SLICE_READONLY) aether_slice_fail_readonly(file, line);
    return (char*)s.ptr + (uint64_t)i * elem_size;
}

/* `s[lo..hi]` — the half-open sub-slice [lo, hi), sharing the backing
 * store. `hi` past the end, `lo > hi`, or a negative bound is a panic;
 * on an unbounded view only `lo <= hi` and `lo >= 0` can be checked. */
static inline AetherSlice aether_slice_sub(AetherSlice s, int64_t lo, int64_t hi,
                                           size_t elem_size,
                                           const char* file, int line) {
    if (lo < 0 || hi < lo ||
        (s.len != AETHER_SLICE_UNBOUNDED && (uint64_t)hi > s.len)) {
        aether_slice_fail_range(lo, hi, s.len, file, line);
    }
    AetherSlice d = aether_slice_derive(s, (char*)s.ptr + (uint64_t)lo * elem_size,
                                        (uint64_t)(hi - lo));
    /* #3072: a view of a bounded slice's elements, or of any view's from
     * an offset, owns nothing. */
    if (s.len != AETHER_SLICE_UNBOUNDED || lo != 0) d.flags |= AETHER_SLICE_BORROWED;
    return d;
}

/* `s[lo..]` — from lo to the end. On an unbounded view the result stays
 * unbounded. */
static inline AetherSlice aether_slice_from(AetherSlice s, int64_t lo,
                                            size_t elem_size,
                                            const char* file, int line) {
    if (s.len == AETHER_SLICE_UNBOUNDED) {
        if (lo < 0) aether_slice_fail_range(lo, lo, s.len, file, line);
        AetherSlice d = aether_slice_derive(s, (char*)s.ptr + (uint64_t)lo * elem_size,
                                            AETHER_SLICE_UNBOUNDED);
        if (lo != 0) d.flags |= AETHER_SLICE_BORROWED;   /* #3072 */
        return d;
    }
    return aether_slice_sub(s, lo, (int64_t)s.len, elem_size, file, line);
}

/* #3072: `free(s)`: the buffer `make([]T, n)` handed out, or a pointer the
 * program owns viewed from its start. A view owns nothing (R1, R2): `free`
 * of a read-only one (string.bytes) or of one of another slice's or an
 * array's elements is a named panic, where the allocator was given a
 * pointer it never handed out (heap corruption) or one its owner still
 * holds (a double free later). */
static inline void aether_slice_free(AetherSlice s, const char* file, int line) {
    if (s.flags & AETHER_SLICE_READONLY)
        aether_slice_panicf("%s:%d: free of a read-only view of a string, which owns nothing",
                            file, line);
    if (s.flags & AETHER_SLICE_BORROWED)
        aether_slice_panicf("%s:%d: free of a view of elements another slice or an array "
                            "holds, which owns nothing", file, line);
    free(s.ptr);
}

/* #3159: `free(s)` of a slice whose element type owns something (a string,
 * a closure, a struct or composite that holds one): a `make` buffer's
 * elements each give back what they hold (`drop`, the place's own release,
 * which empties it), then the buffer goes, as a struct's destroy releases
 * its fields. Before, every string stored into the buffer leaked. A view is
 * refused before anything is released: its elements are another's. */
static inline void aether_slice_free_elems(AetherSlice s, size_t elem_size,
                                           void (*drop)(const void*),
                                           const char* file, int line) {
    if (s.flags & (AETHER_SLICE_READONLY | AETHER_SLICE_BORROWED)) {
        aether_slice_free(s, file, line);
        return;
    }
    if ((s.flags & AETHER_SLICE_MADE) && s.len != AETHER_SLICE_UNBOUNDED) {
        for (uint64_t i = 0; i < s.len; i++) drop((const char*)s.ptr + i * elem_size);
    }
    free(s.ptr);
}

#ifdef __cplusplus
}
#endif

#endif /* AETHER_SLICE_H */
