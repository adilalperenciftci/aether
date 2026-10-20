/* Where the text of an Aether source file starts (#2999).
 *
 * A source file is UTF-8. One that starts with the UTF-8 byte order mark
 * (EF BB BF, U+FEFF), as Windows editors write it, starts its text after the
 * mark: the mark is no part of the program, as C#, Go, Rust and Python treat
 * it. Anywhere else U+FEFF is a character like any other, valid only in a
 * string or a comment.
 *
 * Every reader of source goes through this: the lexer (the compiler, `ae
 * check`, imported modules, the LSP), the formatter (`ae fmt`, which keeps the
 * mark where it found it), and `ae`'s own line scans of a source file (its
 * imports, `ae help`). Header-only, so the `ae` binary shares it with no
 * build change. */
#ifndef AETHER_SOURCE_TEXT_H
#define AETHER_SOURCE_TEXT_H

#include <stddef.h>

/* The length of the byte order mark `src` starts with: 3, or 0 for none. */
static inline size_t aether_source_bom_length(const char* src) {
    if (src && (unsigned char)src[0] == 0xEF && (unsigned char)src[1] == 0xBB &&
        (unsigned char)src[2] == 0xBF)
        return 3;
    return 0;
}

#endif /* AETHER_SOURCE_TEXT_H */
