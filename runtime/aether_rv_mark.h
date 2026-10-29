#ifndef AETHER_RV_MARK_H
#define AETHER_RV_MARK_H

/* A runtime copy's mark in its own image (#3445).
 *
 * The sandbox levels and the execution accounts are one per process: they
 * live in one runtime copy, which every copy finds the same way, the first
 * loaded image, in load order, that carries a record of them
 * (aether_rendezvous_find, aether_resource_caps.c). The copies once looked
 * for an export instead, which a Windows executable never has, nor one
 * linked without -rdynamic on Linux: a program's own copy that looked before
 * it loaded a library kept levels and accounts the library's copy never
 * found, and code of the library that the program called inside a deny-all
 * block was allowed everything.
 *
 * The record is laid out as an ELF note on every format: the 12-byte header,
 * the name "AetherRV" (9 bytes, so what follows starts at 24 whether notes
 * are aligned to 4 or to 8), and what names the copy's rendezvous function:
 *
 * - ELF: a note in a read-only section, emitted by assembly, whose 4-byte
 *   desc is the function's offset from the desc, fixed when the image is
 *   linked (the function is hidden, so nothing relocates it at load and
 *   nothing interposes it). A loaded object shows its notes (PT_NOTE).
 * - PE: a .aerv section holding the function's address, read from the
 *   section table the loader maps with the module.
 * - Mach-O: a __DATA_CONST,__aether_rv section holding the address.
 *
 * The record never changes: a copy of any release reads any other's. */

#include <stdint.h>
#include "utils/aether_compiler.h"

#define AETHER_RV_KIND_SANDBOX  1   /* the sandbox levels */
#define AETHER_RV_KIND_ACCOUNTS 2   /* the execution accounts */

#define AETHER_RV_NAME "AetherRV"

/* Any function pointer type converts to this one and back. */
typedef void (*aether_rv_fn)(void);

/* Where the images are read in load order: Windows (MinGW), macOS, and the
 * ELF systems with dl_iterate_phdr. Not Cygwin (its lookup is the global
 * scope's), wasm or a bare-metal build, which load no second copy. */
#if AETHER_GCC_COMPAT && !defined(__EMSCRIPTEN__) && !defined(__wasi__) && \
    (defined(_WIN32) || defined(__APPLE__) || defined(__linux__) || defined(__FreeBSD__) || \
     defined(__NetBSD__) || defined(__OpenBSD__))
#  define AETHER_RV_MARKS 1
#  if defined(_WIN32) || defined(__APPLE__)
#    define AETHER_RV_ELF 0
#  else
#    define AETHER_RV_ELF 1
#  endif
#else
#  define AETHER_RV_MARKS 0
#  define AETHER_RV_ELF 0
#endif

typedef struct AetherRvMark {
    uint32_t namesz;     /* sizeof AETHER_RV_NAME */
    uint32_t descsz;     /* sizeof the field below */
    uint32_t kind;       /* AETHER_RV_KIND_* */
    char name[12];       /* AETHER_RV_NAME, padded to 4 */
#if AETHER_RV_ELF
    int32_t fn_offset;   /* the function's address less this field's */
#else
    aether_rv_fn fn;     /* the function's address */
#endif
} AetherRvMark;

#define AETHER_RV_STR2(x) #x
#define AETHER_RV_STR(x) AETHER_RV_STR2(x)

/* AETHER_RV_MARK(anchor, kind, fn): this image's record of `kind` naming
 * `fn`, a function of this image (hidden on ELF, AETHER_COPY_LOCAL, so its
 * offset is fixed at link time), as the hidden `anchor`. The finder is given
 * the anchor: it knows its own image by it, and the reference keeps the
 * record where a link drops what nothing reaches (--gc-sections). */
#if AETHER_RV_MARKS && AETHER_RV_ELF
#  define AETHER_RV_MARK(anchor, kind, fn)                                    \
    __asm__(".pushsection .note.aether.rv,\"a\",%note\n"                      \
            "\t.balign 4\n"                                                   \
            "\t.globl " #anchor "\n"                                          \
            "\t.hidden " #anchor "\n"                                         \
            #anchor ":\n"                                                     \
            "\t.long 9, 4, " AETHER_RV_STR(kind) "\n"                         \
            "\t.asciz \"" AETHER_RV_NAME "\"\n"                               \
            "\t.balign 4\n"                                                   \
            "\t.long " #fn " - .\n"                                           \
            "\t.balign 4\n"                                                   \
            "\t.popsection\n");                                               \
    extern __attribute__((visibility("hidden"))) const AetherRvMark anchor
#elif AETHER_RV_MARKS
#  if defined(_WIN32)
#    define AETHER_RV_SECTION ".aerv"              /* 8 bytes at most */
#  else
#    define AETHER_RV_SEGMENT "__DATA_CONST"
#    define AETHER_RV_SECTNAME "__aether_rv"
#    define AETHER_RV_SECTION AETHER_RV_SEGMENT "," AETHER_RV_SECTNAME
#  endif
#  if defined(__clang__)
#    define AETHER_RV_NO_ASAN __attribute__((no_sanitize("address")))   /* no redzone between records */
#  else
#    define AETHER_RV_NO_ASAN
#  endif
#  define AETHER_RV_MARK(anchor, kind, fn)                                                \
    AETHER_RV_NO_ASAN static const AetherRvMark anchor                                  \
        __attribute__((section(AETHER_RV_SECTION), used, aligned(sizeof(void*)))) = {   \
            (uint32_t)sizeof AETHER_RV_NAME, (uint32_t)sizeof(aether_rv_fn), (kind),    \
            AETHER_RV_NAME, (aether_rv_fn)(fn) }
#endif

/* The rendezvous function of the copy that owns `kind`: the first loaded
 * image, in load order, with a record of it; NULL when none has one. `self`
 * is this copy's record (NULL where there are none). Where the images are
 * not read (Cygwin), the global scope's `symbol`. Each copy's own: the
 * copies may be of different releases. */
AETHER_COPY_LOCAL void* aether_rendezvous_find(const char* symbol, uint32_t kind,
                                               const AetherRvMark* self);

#endif /* AETHER_RV_MARK_H */
