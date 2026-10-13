#ifndef AETHER_QUOTE_ANALYSIS_H
#define AETHER_QUOTE_ANALYSIS_H

/* `f(args) quote |a: T| { body }` (docs/quote.md).
 *
 * The type checker checks a quote's body as a closure's, then hands it here:
 * quote_lower() rejects what version 1 of the tree cannot hold, lowers the
 * typed body to the tree it stands for (QNode, kinds as std.quote numbers
 * them), and records the outer variables the body reads (its captures). The
 * body is then taken off the AST so no later pass reads the quoted
 * statements as code to run. Codegen promotes each capture to a shared cell
 * and emits one builder per quote (quote_emit_builder) that rebuilds this
 * tree at run time through std.quote's runtime. */

#include <stdio.h>
#include <stdint.h>
#include "../ast.h"
#include "../aether_error.h"

struct SymbolTable;

/* Node kinds, version 1: std/quote/module.ae's constants, the same numbers.
 * Kinds are added, never removed or renumbered. */
enum {
    QK_BLOCK = 1, QK_LET, QK_ASSIGN, QK_RETURN, QK_IF, QK_WHILE, QK_FOR,
    QK_BREAK, QK_CONTINUE, QK_EXPR, QK_LIT, QK_LOCAL, QK_CAPTURE, QK_UNARY,
    QK_BINARY, QK_CHOOSE, QK_CALL, QK_FIELD, QK_INDEX, QK_MAKE, QK_FIELD_VALUE
};

typedef struct QNode {
    int kind;
    const char* type;   /* the checker's type, as Aether spells it; "" for a statement */
    const char* name;
    const char* op;
    const char* lit;
    int line;
    struct QNode** kids;
    int nkids;
    int capkids;
} QNode;

typedef struct QCapture {
    const char* name;
    const char* type;   /* as written: "vec2" */
    const char* base;   /* what the typed getters read it as: "f32x4" */
    Type* var_type;     /* the variable's type, for codegen's cell release */
} QCapture;

typedef struct QuoteInfo {
    ASTNode* node;
    const char* source;   /* "file:line" */
    QNode* body;
    const char** param_names;
    const char** param_types;
    int nparams;
    QCapture* caps;
    int ncaps;
    uint64_t hash;
    /* Set by codegen: the scope the quote is written in, as closure
     * discovery names scopes (a function, "main", a closure's). */
    const char* scope;
} QuoteInfo;

/* Check and lower the quote whose body the type checker has just checked.
 * `outer` is the scope the quote is written in (its captures resolve
 * there). Reports each construct outside the v1 subset as an error through
 * `report` and returns the number reported; on 0 the quote is in the table
 * and its node's `value` names its index. */
typedef void (*QuoteErrorFn)(const char* message, const char* hint, int line,
                             int column, AetherErrorCode code);
int quote_lower(ASTNode* quote, struct SymbolTable* outer, const char* file,
                QuoteErrorFn report);

int quote_count(void);
QuoteInfo* quote_at(int index);
/* The quote an AST_QUOTE node was lowered to, or NULL. */
QuoteInfo* quote_of(ASTNode* node);
/* Forget every quote (a new compilation). */
void quote_reset(void);

/* The name a type is spelled with in the tree: a distinct type's own name
 * ("vec2"), a struct's, a lane type's ("f32x4"), else the scalar's. */
const char* quote_type_name(Type* t);

/* Is `t` std.quote's Tree, the type a function receiving a quote takes? */
int quote_is_tree_type(Type* t);

/* Emit `static void* _quote_build_<index>(void** _cells)`: it builds the
 * tree, taking a reference to each capture's cell (_cells[i], in caps
 * order) and naming `release_fns[i]` to give it back. */
void quote_emit_builder(FILE* out, int index, const char* const* release_fns);
/* The prototypes of the std.quote constructors the builders call. */
void quote_emit_prototypes(FILE* out);

#endif
