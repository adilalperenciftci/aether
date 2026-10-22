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
 *   - hoist_if_branch_hoists: a name first bound in an arm of one of a
 *     function body's top-level ifs, switches or matches is declared at
 *     function scope, when a top-level statement, an if condition or a
 *     switch's or match's subject reads it and no top-level statement
 *     declares it.
 *   - the names every arm of an if/else, of a switch with a default, or of
 *     a match with a `_` arm or arms that cover its type, declares
 *     (hoist_common_hoists) are declared before that statement, at any
 *     depth.
 *   - a while body's locals, and those of the ifs, switches, matches and
 *     loops nested in it (hoist_loop_decls), are declared before the while.
 *
 * Whether a name is already declared, or is a module-level `var`, depends on
 * the caller's own state and is checked by the caller, and so is, for
 * hoist_common_hoists, whether a match is a statement: one whose value
 * is used (bound, returned, or yielded by an arm of another) keeps its arms'
 * names in the arms. */

#include "../ast.h"
#include "../aether_strmap.h"

/* The type a hoisted declaration of `decl` is given: its own node_type, else
 * its initializer's. Borrowed; NULL when neither is known. */
Type* hoist_decl_type(ASTNode* decl);

/* The type a local bound in several places of `scope_body` (closures
 * excluded) has, for a numeric `seed`: its bindings joined as an
 * if-expression's branches are (hoist_numeric_join; a written type, when
 * one writes it, #3070), a fresh Type when that is not `seed`, NULL when it
 * is, when two bindings join to no type, or when `seed` is not numeric. A `null` binding has no type of its own: when
 * every binding is `null` or a string, the join is `string` (#3032). */
Type* hoist_join_type(ASTNode* scope_body, const char* name, Type* seed);

/* #3064: the numeric bindings of `name` under `root` (closures excluded),
 * joined as an if-expression's branches are (branch_join_type, each
 * binding's value the arm a literal is read from): a fresh Type, NULL when
 * there is none or two that no type holds (a signed value beside a
 * uint64). #3070: a binding that writes its type (`uint64 x = 7`) makes
 * that the join, whatever the others are; the checker refuses one it does
 * not hold. */
Type* hoist_numeric_join(ASTNode* root, const char* name);

/* #3070: the type the first binding of `name` under `root` (closures
 * excluded) that writes its type writes, of any kind: a fresh Type, or
 * NULL. It is the local's type (hoist_join_type). */
Type* hoist_written_type(ASTNode* root, const char* name);

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

/* The names one of the rules hoists, in the order the arms bind them, each
 * with its bindings (#3083: any number of names, each found by name). Kept
 * by this file until hoist_cache_reset; the caller does not free it. */
typedef struct {
    int count;
    int cap;
    const char** names;
    ASTNode** decls;   /* names[i]'s bindings: decls[i * per] .. decls[i * per + per - 1] */
    int per;
    StrMap at;         /* name -> index + 1 */
} HoistNames;

/* The index of `name` in `h`, or -1. */
int hoist_names_find(const HoistNames* h, const char* name);

/* The binding of names[i] whose type the hoisted variable takes: the first
 * whose hoist_decl_type is known, else the first. */
ASTNode* hoist_names_decl(const HoistNames* h, int i);

/* The names hoist_if_branch_vars declares at the top of function body
 * `body` (before the caller's already-declared / module-global checks),
 * each with its first binding: the one in the first arm of a top-level if,
 * switch or match of `body` that declares it. */
const HoistNames* hoist_if_branch_hoists(ASTNode* body);

/* The names every arm of `stmt` declares directly, when `stmt` is an if with
 * an else, a switch with a default, or a match with a `_` arm or arms that
 * cover its type (so every path binds them), each with its binding in every
 * arm; none for any other statement. */
const HoistNames* hoist_common_hoists(ASTNode* stmt);

/* Forget every answer kept for a body or a statement: at the start of each
 * checker and codegen run, and after codegen renames names. */
void hoist_cache_reset(void);

/* `n` is being freed: forget what was kept for it, so a node allocated
 * later at its address is asked afresh. */
void hoist_node_freed(const ASTNode* n);

/* Visit, in codegen's order, the declarations hoist_loop_vars declares
 * before a while whose body is `body`: the body's direct declarations and,
 * recursively, those in every child of the ifs, switches and loops nested
 * in it and in every arm body of the matches nested in it. */
typedef void (*HoistDeclVisitor)(ASTNode* decl, void* user);
void hoist_loop_decls(ASTNode* body, HoistDeclVisitor visit, void* user);

#endif
