#ifndef AETHER_RV_MARK_H
#define AETHER_RV_MARK_H

/* A runtime copy's mark in its own image (#3445).
 *
 * The sandbox levels and the execution accounts are one per process: they
 * live in one runtime copy, which every copy finds the same way, the first
 * loaded image that has them (aether_rendezvous_find, aether_resource_caps.c).
 * An image's exports could not say it: a Windows executable exports nothing,
 * nor does one linked without -rdynamic on Linux, so a program's own copy
 * that looked before it loaded a library kept levels and accounts the
 * library's copy never found, and code of the library that the program
 * called inside a deny-all block was allowed everything.
 *
 * So each copy marks its image with a record the loader maps with it: a
 * section of its own on PE and Mach-O, a note on ELF (the one part of an
 * image's headers a loaded ELF object shows). Any copy reads the records in
 * load order, the program first. An image of an Aether release before the
 * marks has none, and is found by its export, as it always was.
 *
 * A record is laid out as an ELF note on every format: the 12-byte header,
 * the name "AetherRV", and the address of the copy's rendezvous function.
 * With a name of 9 bytes the function starts at 24 whether the notes are
 * aligned to 4 or to 8, and is aligned to a pointer. */

#include <stdint.h>
#include "utils/aether_compiler.h"

#define AETHER_RV_KIND_SANDBOX  1u   /* aether_sandbox_rendezvous */
#define AETHER_RV_KIND_ACCOUNTS 2u   /* aether_accounts_rendezvous */

#define AETHER_RV_NAME "AetherRV"

/* Any function pointer type converts to this one and back. */
typedef void (*aether_rv_fn)(void);

typedef struct AetherRvMark {
    uint32_t namesz;     /* sizeof AETHER_RV_NAME */
    uint32_t descsz;     /* sizeof(aether_rv_fn) */
    uint32_t kind;       /* AETHER_RV_KIND_* */
    char name[12];       /* AETHER_RV_NAME, padded to 4 */
    aether_rv_fn fn;     /* the copy's rendezvous function */
} AetherRvMark;

/* Where the images are read in load order: Windows (MinGW), macOS, and the
 * ELF systems with dl_iterate_phdr. Not Cygwin (its lookup is the global
 * scope's), wasm or a bare-metal build, which load no second copy. */
#if AETHER_GCC_COMPAT && !defined(__EMSCRIPTEN__) && !defined(__wasi__) && \
    (defined(_WIN32) || defined(__APPLE__) || defined(__linux__) || defined(__FreeBSD__) || \
     defined(__NetBSD__) || defined(__OpenBSD__))
#  define AETHER_RV_MARKS 1
#  if defined(_WIN32)
#    define AETHER_RV_SECTION ".aerv"              /* 8 bytes at most */
#  elif defined(__APPLE__)
#    define AETHER_RV_SEGMENT "__DATA"
#    define AETHER_RV_SECTNAME "__aether_rv"
#    define AETHER_RV_SECTION AETHER_RV_SEGMENT "," AETHER_RV_SECTNAME
#  else
#    define AETHER_RV_SECTION ".note.aether.rv"    /* SHT_NOTE by its name */
#  endif
/* This copy's record of `kind` for `fn`, as the static `var`. The finder is
 * given its address: it knows its own image by it, and the reference keeps
 * the record where a link drops what nothing reaches (--gc-sections). */
#  define AETHER_RV_MARK(var, kind, fn)                                                   \
    static const AetherRvMark var                                                       \
        __attribute__((section(AETHER_RV_SECTION), used, aligned(sizeof(void*)))) = {   \
            (uint32_t)sizeof AETHER_RV_NAME, (uint32_t)sizeof(aether_rv_fn), (kind),    \
            AETHER_RV_NAME, (aether_rv_fn)(fn) }
#else
#  define AETHER_RV_MARKS 0
#endif

/* The rendezvous function of the copy that owns `kind`: the first loaded
 * image, in load order, with a record of it, or, for an image with none,
 * that exports `symbol`. NULL when none has it. `self` is this copy's
 * record (NULL where there are none). Each copy's own: the copies may be of
 * different releases. */
AETHER_COPY_LOCAL void* aether_rendezvous_find(const char* symbol, uint32_t kind,
                                               const AetherRvMark* self);

#endif /* AETHER_RV_MARK_H */
