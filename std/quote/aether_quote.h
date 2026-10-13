/* Copyright (c) 2026 Aether Developers. */
#ifndef AETHER_QUOTE_H
#define AETHER_QUOTE_H

#include <stdint.h>

/* std.quote (docs/quote.md): the tree a `quote` trailing block hands to the
 * function it is attached to.
 *
 * The compiler emits, per quote, a static builder that calls the
 * aether_quote_* constructors below; the Aether side (std/quote/module.ae)
 * reads the result through the accessors. The C layout is private to this
 * file and the accessors: Aether code sees `quote.Tree`, `quote.Node` and
 * `quote.Capture` as opaque handles, so the layout can change without the
 * tree's public shape changing. */

/* The tree format's version, quote.VERSION. Kinds are added, never removed
 * or renumbered; each addition bumps this by one. */
#define AETHER_QUOTE_VERSION 1

/* Constructors, called by compiler-emitted builders. The strings are the
 * builder's own static literals and are not copied. */
void* aether_quote_tree(const char* source, int64_t hash);
void* aether_quote_node(int kind, const char* type, const char* name,
                        const char* op, const char* lit, int line);
void* aether_quote_add(void* parent, void* child);
void  aether_quote_set_body(void* tree, void* body);
void  aether_quote_param(void* tree, const char* name, const char* type);
/* `cell` is the captured variable's shared cell, already retained for the
 * tree; `release` gives that reference back when the tree is freed. `base`
 * is the type the cell holds as the typed getters know it ("float",
 * "f32x4", "int", ...); `type` is the Aether type as written ("vec2"). */
void  aether_quote_capture(void* tree, const char* name, const char* type,
                           const char* base, void* cell, void (*release)(void*));

/* Accessors (std/quote/module.ae). */
int         aether_quote_version(void* tree);
void*       aether_quote_body(void* tree);
const char* aether_quote_source(void* tree);
int64_t     aether_quote_hash(void* tree);
int         aether_quote_param_count(void* tree);
const char* aether_quote_param_name(void* tree, int i);
const char* aether_quote_param_type(void* tree, int i);
int         aether_quote_capture_count(void* tree);
void*       aether_quote_capture_at(void* tree, int i);
void*       aether_quote_capture_named(void* tree, const char* name);

int         aether_quote_kind(void* node);
const char* aether_quote_type(void* node);
const char* aether_quote_name(void* node);
const char* aether_quote_op(void* node);
const char* aether_quote_lit(void* node);
int         aether_quote_line(void* node);
int         aether_quote_child_count(void* node);
void*       aether_quote_child(void* node, int i);

const char* aether_quote_capture_name(void* cap);
const char* aether_quote_capture_type(void* cap);
void*       aether_quote_capture_cell(void* cap);
const char* aether_quote_capture_base(void* cap);
/* Read a cell as the given type; the getters check the type first. */
double      aether_quote_read_float(void* cell);
float       aether_quote_read_f32(void* cell);
int         aether_quote_read_int(void* cell);
int64_t     aether_quote_read_long(void* cell);
int         aether_quote_read_bool(void* cell);
const char* aether_quote_read_string(void* cell);
void*       aether_quote_read_ptr(void* cell);

void        aether_quote_free(void* tree);

#endif
