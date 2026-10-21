#ifndef AETHER_HOIST_H
#define AETHER_HOIST_H

/* Which locals codegen declares in an enclosing scope rather than in the
 * block that binds them -- the one definition both codegen (which emits the
 * declarations) and the typechecker (which must then let a read after the
 * block resolve) use, so the two cannot disagree (#2186).
 *
 * Three rules, all over the AST, before any C is emitted. An arm is an if's
 * then or else block, a case of a switch (#2732), or the body of a match
 * arm (#2768):
 *
 *   - hoist_if_branch_candidates: a name first bound in an arm of one of a
 *     function body's top-level ifs, switches or matches is declared at
 *     function scope, when a top-level statement, an if condition or a
 *     switch's or match's subject reads it and no top-level statement
 *     declares it.
 *   - the names every arm of an if/else, of a switch with a default, or of
 *     a match with a `_` arm or arms that cover its type, declares
 *     (hoist_common_decl_names) are declared before that statement, at any
 *     depth.
 *   - a while body's locals, and those of the ifs, switches, matches and
 *     loops nested in it (hoist_loop_decls), are declared before the while.
 *
 * Whether a name is already declared, or is a module-level `var`, depends on
 * the caller's own state and is checked by the caller, and so is, for
 * hoist_common_decl_names, whether a match is a statement: one whose value
 * is used (bound, returned, or yielded by an arm of another) keeps its arms'
 * names in the arms. */

#include "../ast.h"

#define HOIST_MAX_NAMES 64

/* Append the names `block`'s direct AST_VARIABLE_DECLARATION children bind to
 * `out` (deduplicated, at most `cap`); returns the new count. */
int hoist_direct_decl_names(ASTNode* block, const char** out, int count, int cap);

/* The first direct declaration of `name` in `block`, or NULL. */
ASTNode* hoist_find_decl(ASTNode* block, const char* name);

/* Does `node`'s subtree contain an identifier `name`? */
int hoist_has_identifier_ref(ASTNode* node, const char* name);

/* The type a hoisted declaration of `decl` is given: its own node_type, else
 * its initializer's. Borrowed; NULL when neither is known. */
Type* hoist_decl_type(ASTNode* decl);

/* The type a local bound in several places of `scope_body` (closures
 * excluded) has, for a numeric `seed`: its bindings joined as an
 * if-expression's branches are (hoist_numeric_join), a fresh Type when that
 * is not `seed`, NULL when it is, when two bindings join to no type, or
 * when `seed` is not numeric. A `null` binding has no type of its own: when
 * every binding is `null` or a string, the join is `string` (#3032). */
Type* hoist_join_type(ASTNode* scope_body, const char* name, Type* seed);

/* #3064: the numeric bindings of `name` under `root` (closures excluded),
 * joined as an if-expression's branches are (branch_join_type, each
 * binding's value the arm a literal is read from): a fresh Type, NULL when
 * there is none or two that no type holds (a signed value beside a
 * uint64). */
Type* hoist_numeric_join(ASTNode* root, const char* name);

/* #3064: hoist_numeric_join for every name bound under `root`, for a walk
 * that types its bindings in the order they are written (the early
 * inference pass) and asks for a name's join as it goes: one walk of
 * `root` gathers the bindings, and each answer is kept until a binding it
 * read is typed differently, so a body bound n times costs about n steps,
 * not n walks of the body. */
typedef struct HoistJoins HoistJoins;
HoistJoins* hoist_joins_new(ASTNode* root);
/* The walk has typed `decl`, a declaration under the root. */
void hoist_joins_typed(HoistJoins* j, const ASTNode* decl);
/* What hoist_numeric_join(root, name) gives now: a fresh Type, or NULL. */
Type* hoist_joins_get(HoistJoins* j, const char* name);
void hoist_joins_free(HoistJoins* j);

/* The names hoist_if_branch_vars declares at the top of function body
 * `body` (before the caller's already-declared / module-global checks).
 * Returns the count written to `out` (at most `cap`). */
int hoist_if_branch_candidates(ASTNode* body, const char** out, int cap);

/* The declaration of `name` in the first arm of a top-level if, switch or
 * match of `body` that declares it (the one whose type the hoisted variable
 * takes). */
ASTNode* hoist_if_branch_first_decl(ASTNode* body, const char* name);

/* The names every arm of `stmt` declares directly, when `stmt` is an if with
 * an else, a switch with a default, or a match with a `_` arm or arms that
 * cover its type (so every path binds them); 0 for any other statement.
 * Returns the count written to `out` (at most `cap`). */
int hoist_common_decl_names(ASTNode* stmt, const char** out, int cap);

/* The declaration of `name` in an arm of `stmt` whose type the hoisted
 * variable takes: the first whose hoist_decl_type is known, else the first. */
ASTNode* hoist_common_first_decl(ASTNode* stmt, const char* name);

/* Visit, in codegen's order, the declarations hoist_loop_vars declares
 * before a while whose body is `body`: the body's direct declarations and,
 * recursively, those in every child of the ifs, switches and loops nested
 * in it and in every arm body of the matches nested in it. */
typedef void (*HoistDeclVisitor)(ASTNode* decl, void* user);
void hoist_loop_decls(ASTNode* body, HoistDeclVisitor visit, void* user);

#endif
