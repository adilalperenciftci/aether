/* A slice of a function's own storage must not outlive the function. See
 * slice_escape.h. */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "slice_escape.h"
#include "../aether_error.h"
#include "../aether_strmap.h"

#define LIVE ((void*)1)

typedef struct {
    StrMap globals;   /* module-level `var` names */
    int errors;
} Esc;

/* What holds a view of the frame's storage at one point of the function:
 * a set of paths, `v` for a local as a whole or `h.data` for a field of a
 * local value, each mapped to LIVE while it holds one (a cleared path maps
 * to NULL: a StrMap keeps its keys). */
typedef StrMap Views;

/* The `break`s and `continue`s of the loop being walked: what holds a view
 * where each leaves the body. */
typedef struct LoopExits {
    Views exits;
    Views next;
    struct LoopExits* outer;
} LoopExits;

/* One function, closure or `main`: what its frame holds. */
typedef struct {
    ASTNode* owner;
    char shown[160];  /* its name as the source writes it, for messages */
    StrMap typed;     /* names a written-type declaration binds */
    StrMap locals;    /* name -> its binding node (a local or a parameter) */
    StrMap params;    /* the parameters among them */
    StrMap arrays;    /* the frame's own fixed-size arrays: name -> declaration */
    StrMap rebinders; /* local closures a call of re-binds: name -> StrMap* of paths */
    LoopExits* loop;  /* the innermost loop being walked */
} Frame;

/* ---- the path sets ---- */

static int key_on(const char* key, const char* root) {
    size_t n = strlen(root);
    return strncmp(key, root, n) == 0 && (key[n] == '\0' || key[n] == '.');
}

/* Does anything at or under `path` hold a view, or does a value it is part
 * of hold one as a whole? */
static int views_touch(const Views* v, const char* path) {
    for (int i = 0; i < strmap_count(v); i++) {
        if (!strmap_value_at(v, i)) continue;
        const char* k = strmap_key_at(v, i);
        if (key_on(k, path) || key_on(path, k)) return 1;
    }
    return 0;
}

static void views_set(Views* v, const char* path) {
    strmap_put(v, path, LIVE);
}

/* `path` and everything under it holds no view any more. */
static void views_clear(Views* v, const char* path) {
    for (int i = 0; i < strmap_count(v); i++) {
        const char* k = strmap_key_at(v, i);
        if (strmap_value_at(v, i) && key_on(k, path)) strmap_put(v, k, NULL);
    }
}

static void views_copy(Views* dst, const Views* src) {
    strmap_init(dst);
    for (int i = 0; i < strmap_count(src); i++)
        if (strmap_value_at(src, i)) strmap_put(dst, strmap_key_at(src, i), LIVE);
}

/* dst holds what either holds. Returns 1 when dst grew. */
static int views_join(Views* dst, const Views* src) {
    int grew = 0;
    for (int i = 0; i < strmap_count(src); i++) {
        if (!strmap_value_at(src, i)) continue;
        const char* k = strmap_key_at(src, i);
        if (!strmap_get(dst, k)) {
            strmap_put(dst, k, LIVE);
            grew = 1;
        }
    }
    return grew;
}

static void views_move(Views* dst, Views* src) {
    strmap_free(dst);
    *dst = *src;
}

/* `to` holds what `from` holds, path for path. */
static void views_alias(Views* v, const char* from, const char* to) {
    size_t n = strlen(from);
    int count = strmap_count(v);
    for (int i = 0; i < count; i++) {
        if (!strmap_value_at(v, i)) continue;
        const char* k = strmap_key_at(v, i);
        if (!key_on(k, from)) continue;
        char path[256];
        snprintf(path, sizeof(path), "%s%s", to, k + n);
        strmap_put(v, path, LIVE);
    }
}

/* ---- the frame ---- */

static ASTNode* unwrap_export(ASTNode* n) {
    if (n && n->type == AST_EXPORT_STATEMENT && n->child_count > 0) return n->children[0];
    return n;
}

static int node_line(ASTNode* n) {
    if (!n) return 0;
    if (n->line > 0) return n->line;
    for (int i = 0; i < n->child_count; i++) {
        int l = node_line(n->children[i]);
        if (l > 0) return l;
    }
    return 0;
}

static int node_column(ASTNode* n) {
    if (!n) return 0;
    if (n->line > 0) return n->column;
    for (int i = 0; i < n->child_count; i++) {
        if (node_line(n->children[i]) > 0) return node_column(n->children[i]);
    }
    return 0;
}

/* `x = v` writes the module-level `var x` when the frame declares no `x` of
 * its own with a written type (a bare binding of a global's name is a store
 * to the global, #701). */
static int writes_global(Esc* esc, Frame* f, ASTNode* decl) {
    return decl->value && decl->type_inferred && strmap_has(&esc->globals, decl->value) &&
           !strmap_has(&f->typed, decl->value) && !strmap_has(&f->params, decl->value);
}

static int is_sized_array_type(Type* t) {
    return t && t->kind == TYPE_ARRAY && t->array_size > 0;
}

static void collect_typed(Frame* f, ASTNode* n) {
    if (!n || ast_is_own_function(n)) return;
    if (n->type == AST_VARIABLE_DECLARATION && n->value && !n->type_inferred)
        strmap_put(&f->typed, n->value, n);
    for (int i = 0; i < n->child_count; i++) collect_typed(f, n->children[i]);
}

/* The names the frame binds, outside the closures in it (a trailing block is
 * part of it). */
static void collect_locals(Esc* esc, Frame* f, ASTNode* n) {
    if (!n || ast_is_own_function(n)) return;
    if (n->type == AST_VARIABLE_DECLARATION && n->value && !writes_global(esc, f, n)) {
        if (!strmap_has(&f->locals, n->value)) strmap_put(&f->locals, n->value, n);
        if (is_sized_array_type(n->node_type) && !strmap_has(&f->arrays, n->value))
            strmap_put(&f->arrays, n->value, n);
    } else if ((n->type == AST_PATTERN_VARIABLE || n->type == AST_CATCH_CLAUSE) && n->value) {
        if (!strmap_has(&f->locals, n->value)) strmap_put(&f->locals, n->value, n);
    } else if (n->type == AST_TUPLE_DESTRUCTURE) {
        for (int i = 0; i + 1 < n->child_count; i++) {
            ASTNode* c = n->children[i];
            if (c && c->value && !strmap_has(&f->locals, c->value))
                strmap_put(&f->locals, c->value, c);
        }
    }
    for (int i = 0; i < n->child_count; i++) collect_locals(esc, f, n->children[i]);
}

/* ---- closures a call of re-binds the frame's names ---- */

/* Does `n` leave the code it is in early: a `return`, `break`, `continue`
 * or `panic` anywhere in it (not in a closure of its own)? */
static int may_exit(ASTNode* n) {
    if (!n || ast_is_own_function(n)) return 0;
    if (n->type == AST_RETURN_STATEMENT || n->type == AST_BREAK_STATEMENT ||
        n->type == AST_CONTINUE_STATEMENT || n->type == AST_PANIC_STATEMENT)
        return 1;
    for (int i = 0; i < n->child_count; i++)
        if (may_exit(n->children[i])) return 1;
    return 0;
}

/* A value that holds no view of any frame: a call's result (taken to be
 * none, as everywhere in this check; `make` is one), `null`, or `[]`. */
static int holds_no_view(ASTNode* e) {
    if (!e) return 0;
    if (e->type == AST_FUNCTION_CALL || e->type == AST_NULL_LITERAL) return 1;
    return e->type == AST_ARRAY_LITERAL && e->child_count == 0;
}

static ASTNode* value_path(ASTNode* e, char* out, size_t cap, int* whole);
static int store_parts(ASTNode* n, ASTNode** left, ASTNode** value);

/* The paths of the frame `f` a closure body's statements re-bind, on every
 * way through them, to a value that holds no view: `v = make([]T, n)`, or
 * `h.data = make([]T, n)` for a local `h`. A name the closure declares
 * itself (a parameter, a written-type declaration, in `own`) is its own.
 * Only straight-line statements count, and an `if` whose branches both
 * re-bind the path; the walk stops at the first statement that may leave
 * early, since what follows it may not run. */
static void must_rebind(Frame* f, ASTNode* block, StrMap* own, StrMap* out) {
    if (!block) return;
    int count = block->type == AST_BLOCK ? block->child_count : 1;
    for (int i = 0; i < count; i++) {
        ASTNode* st = block->type == AST_BLOCK ? block->children[i] : block;
        if (!st) continue;
        if (st->type == AST_EXPRESSION_STATEMENT && st->child_count > 0) st = st->children[0];
        if (may_exit(st)) return;
        if (st->type == AST_VARIABLE_DECLARATION && st->value && st->child_count > 0) {
            if (!st->type_inferred) {
                strmap_put(own, st->value, st);
                continue;
            }
            if (!strmap_has(own, st->value) && strmap_has(&f->locals, st->value) &&
                holds_no_view(st->children[0]))
                strmap_put(out, st->value, LIVE);
            continue;
        }
        ASTNode *left, *value;
        if (store_parts(st, &left, &value)) {
            char path[256];
            int element = 0;
            ASTNode* root = value_path(left, path, sizeof(path), &element);
            if (root && !element && !strmap_has(own, root->value) &&
                strmap_has(&f->locals, root->value) && holds_no_view(value))
                strmap_put(out, path, LIVE);
            continue;
        }
        if (st->type == AST_BLOCK) {
            must_rebind(f, st, own, out);
            continue;
        }
        if (st->type == AST_IF_STATEMENT && st->child_count >= 3) {
            StrMap a, b;
            strmap_init(&a);
            strmap_init(&b);
            must_rebind(f, st->children[1], own, &a);
            must_rebind(f, st->children[2], own, &b);
            for (int j = 0; j < strmap_count(&a); j++) {
                const char* k = strmap_key_at(&a, j);
                if (strmap_get(&b, k)) strmap_put(out, k, LIVE);
            }
            strmap_free(&a);
            strmap_free(&b);
        }
    }
}

/* The local closure a call calls by name: `reset()`, which the checker
 * has made `call(reset)`. NULL for any other call. */
static const char* called_closure_name(ASTNode* call) {
    if (!call || call->type != AST_FUNCTION_CALL || !call->value) return NULL;
    if (strcmp(call->value, "call") == 0)
        return (call->child_count > 0 && call->children[0] &&
                call->children[0]->type == AST_IDENTIFIER) ? call->children[0]->value : NULL;
    return call->value;
}

/* How often `name` is bound in `n`, closures included, and whether it is
 * read as a value anywhere (an identifier: passed, stored, captured), as
 * opposed to called by name. */
static void closure_name_uses(ASTNode* n, const char* name, int* binds, int* reads) {
    if (!n) return;
    if (n->type == AST_VARIABLE_DECLARATION && n->value && strcmp(n->value, name) == 0) (*binds)++;
    if (n->type == AST_IDENTIFIER && n->value && strcmp(n->value, name) == 0) (*reads)++;
    int from = 0;
    /* `call(name, ...)`: the callee is called, not read. */
    if (n->type == AST_FUNCTION_CALL && n->value && strcmp(n->value, "call") == 0 &&
        n->child_count > 0 && n->children[0] && n->children[0]->type == AST_IDENTIFIER &&
        n->children[0]->value && strcmp(n->children[0]->value, name) == 0)
        from = 1;
    for (int i = from; i < n->child_count; i++) closure_name_uses(n->children[i], name, binds, reads);
}

/* The frame's local closures a call of which re-binds some of its paths:
 * a name bound once, to a closure literal, and used only by calling it by
 * name, so every call runs that body. A closure passed on, stored or bound
 * again is left out: what it does when is not known here. */
static void collect_rebinders_in(Frame* f, ASTNode* body, ASTNode* n) {
    if (!n || ast_is_own_function(n)) return;
    if (n->type == AST_VARIABLE_DECLARATION && n->value && n->child_count > 0 &&
        n->children[0] && n->children[0]->type == AST_CLOSURE &&
        ast_is_own_function(n->children[0]) && !strmap_has(&f->rebinders, n->value)) {
        int binds = 0, reads = 0;
        closure_name_uses(body, n->value, &binds, &reads);
        if (binds == 1 && reads == 0) {
            ASTNode* lit = n->children[0];
            StrMap own;
            strmap_init(&own);
            for (int i = 0; i < lit->child_count; i++) {
                ASTNode* c = lit->children[i];
                if (c && c->type == AST_CLOSURE_PARAM && c->value) strmap_put(&own, c->value, c);
            }
            StrMap* paths = calloc(1, sizeof(StrMap));
            if (paths) {
                strmap_init(paths);
                for (int i = lit->child_count - 1; i >= 0; i--) {
                    if (lit->children[i] && lit->children[i]->type == AST_BLOCK) {
                        must_rebind(f, lit->children[i], &own, paths);
                        break;
                    }
                }
                if (strmap_count(paths) > 0) strmap_put(&f->rebinders, n->value, paths);
                else {
                    strmap_free(paths);
                    free(paths);
                }
            }
            strmap_free(&own);
        }
    }
    for (int i = 0; i < n->child_count; i++) collect_rebinders_in(f, body, n->children[i]);
}

static void collect_rebinders(Frame* f, ASTNode* body) {
    collect_rebinders_in(f, body, body);
}

static ASTNode* frame_body(ASTNode* owner) {
    if (owner->type == AST_MAIN_FUNCTION)
        return owner->child_count > 0 ? owner->children[0] : NULL;
    for (int i = owner->child_count - 1; i >= 0; i--)
        if (owner->children[i] && owner->children[i]->type == AST_BLOCK) return owner->children[i];
    return NULL;
}

static void frame_init(Esc* esc, Frame* f, ASTNode* owner) {
    memset(f, 0, sizeof(*f));
    f->owner = owner;
    strmap_init(&f->typed);
    strmap_init(&f->locals);
    strmap_init(&f->params);
    strmap_init(&f->arrays);
    strmap_init(&f->rebinders);
    if (owner->type == AST_MAIN_FUNCTION) {
        snprintf(f->shown, sizeof(f->shown), "'main'");
    } else if (owner->type == AST_CLOSURE) {
        snprintf(f->shown, sizeof(f->shown), "this closure");
    } else {
        char buf[160];
        snprintf(f->shown, sizeof(f->shown), "'%s'", ast_source_name(owner, buf, sizeof(buf)));
    }
    /* Parameters: a function's children ahead of its body, a closure's
     * AST_CLOSURE_PARAMs. A slice parameter views the caller's storage; a
     * fixed-size array parameter is the function's own copy of the
     * caller's array, storage of its frame as a local array is. */
    for (int i = 0; i < owner->child_count; i++) {
        ASTNode* p = owner->children[i];
        if (!p || p->type == AST_BLOCK || !p->value) continue;
        if (p->type == AST_PATTERN_VARIABLE || p->type == AST_VARIABLE_DECLARATION ||
            p->type == AST_CLOSURE_PARAM) {
            strmap_put(&f->locals, p->value, p);
            strmap_put(&f->params, p->value, p);
            if (is_sized_array_type(p->node_type)) strmap_put(&f->arrays, p->value, p);
        }
    }
    ASTNode* body = frame_body(owner);
    collect_typed(f, body);
    collect_locals(esc, f, body);
    collect_rebinders(f, body);
}

static void frame_free(Frame* f) {
    strmap_free(&f->typed);
    strmap_free(&f->locals);
    strmap_free(&f->params);
    strmap_free(&f->arrays);
    for (int i = 0; i < strmap_count(&f->rebinders); i++) {
        StrMap* paths = strmap_value_at(&f->rebinders, i);
        if (paths) {
            strmap_free(paths);
            free(paths);
        }
    }
    strmap_free(&f->rebinders);
}

/* ---- what a value views ---- */

/* Is `e` storage of the frame: a non-empty array literal (it lives in the
 * frame as the array it is), or one of the frame's own fixed-size arrays? */
static int frame_storage(Frame* f, ASTNode* e) {
    if (!e) return 0;
    if (e->type == AST_ARRAY_LITERAL) return e->child_count > 0;
    if (e->type == AST_IDENTIFIER && e->value) return strmap_has(&f->arrays, e->value);
    return 0;
}

/* The path an lvalue or a read names: `h` for a local, `h.data.ptr` for a
 * field of one; an element (`a[i]`) is its array as a whole, since another
 * element may hold what this one does not. Writes it into `out` and returns
 * its root, or NULL when the root is not a name. `*whole` is set when an
 * element was taken. */
static ASTNode* value_path(ASTNode* e, char* out, size_t cap, int* whole) {
    const char* fields[16];
    int nf = 0;
    *whole = 0;
    while (e && (e->type == AST_MEMBER_ACCESS || e->type == AST_ARRAY_ACCESS) &&
           e->child_count > 0) {
        if (e->type == AST_ARRAY_ACCESS) {
            nf = 0;
            *whole = 1;
        } else if (nf < 16 && e->value) {
            fields[nf++] = e->value;
        }
        e = e->children[0];
    }
    if (!e || e->type != AST_IDENTIFIER || !e->value) return NULL;
    size_t pos = (size_t)snprintf(out, cap, "%s", e->value);
    for (int i = nf - 1; i >= 0 && pos < cap; i--)
        pos += (size_t)snprintf(out + pos, cap - pos, ".%s", fields[i]);
    return e;
}

static int frame_view(Frame* f, const Views* v, ASTNode* e);

/* Can a value of type `t` hold a view: a slice, or a value with fields or
 * elements (a struct, a tuple, an array, an optional, a sum), or a closure?
 * An unknown type might. */
static int may_hold_view(Type* t) {
    if (!t) return 1;
    switch (t->kind) {
        case TYPE_ARRAY: case TYPE_STRUCT: case TYPE_TUPLE: case TYPE_OPTIONAL:
        case TYPE_SUM: case TYPE_FUNCTION: case TYPE_UNKNOWN: case TYPE_WILDCARD:
            return 1;
        default:
            return 0;
    }
}

/* Does the closure `c` capture a name that holds a view here (one it does
 * not bind itself)? A captured slice is copied into the closure as it is,
 * and so still views the frame. A captured array is copied whole, and does
 * not. */
static int captures_view(const Views* v, ASTNode* n, StrMap* own) {
    if (!n) return 0;
    if (n->type == AST_IDENTIFIER && n->value && views_touch(v, n->value) &&
        !strmap_has(own, n->value))
        return 1;
    for (int i = 0; i < n->child_count; i++)
        if (captures_view(v, n->children[i], own)) return 1;
    return 0;
}

static void collect_closure_names(ASTNode* n, StrMap* own) {
    if (!n) return;
    if ((n->type == AST_VARIABLE_DECLARATION || n->type == AST_CLOSURE_PARAM ||
         n->type == AST_PATTERN_VARIABLE) && n->value)
        strmap_put(own, n->value, n);
    for (int i = 0; i < n->child_count; i++) collect_closure_names(n->children[i], own);
}

/* Is the value `e`, read where `v` says what holds a view, a slice of the
 * frame's storage, or something holding one (a struct literal, a closure)? */
static int frame_view(Frame* f, const Views* v, ASTNode* e) {
    if (!e) return 0;
    switch (e->type) {
        case AST_SLICE_FROM_ARRAY:
            return e->child_count > 0 && frame_storage(f, e->children[0]);
        case AST_SLICE_EXPR:
            return e->child_count > 0 &&
                   (frame_storage(f, e->children[0]) || frame_view(f, v, e->children[0]));
        case AST_IDENTIFIER:
            return e->value && views_touch(v, e->value);
        case AST_MEMBER_ACCESS:
        case AST_ARRAY_ACCESS: {
            /* A field or an element is a view only when it can hold one:
             * an int read out of a slice views nothing. */
            if (!may_hold_view(e->node_type)) return 0;
            char path[256];
            int whole;
            return value_path(e, path, sizeof(path), &whole) && views_touch(v, path);
        }
        case AST_EXPRESSION_STATEMENT:
            return e->child_count > 0 && frame_view(f, v, e->children[0]);
        case AST_IF_EXPRESSION:
            return (e->child_count > 1 && frame_view(f, v, e->children[1])) ||
                   (e->child_count > 2 && frame_view(f, v, e->children[2]));
        case AST_MATCH_STATEMENT:
            for (int i = 1; i < e->child_count; i++) {
                ASTNode* arm = e->children[i];
                if (arm && arm->type == AST_MATCH_ARM && arm->child_count > 1 &&
                    frame_view(f, v, match_arm_value(arm->children[1])))
                    return 1;
            }
            return 0;
        case AST_STRUCT_LITERAL:
        case AST_TUPLE_LITERAL:
            for (int i = 0; i < e->child_count; i++) {
                ASTNode* c = e->children[i];
                if (!c) continue;
                /* A struct literal's field init carries its value. */
                if (c->type == AST_ASSIGNMENT && c->child_count == 1) c = c->children[0];
                if (frame_view(f, v, c)) return 1;
            }
            return 0;
        case AST_CLOSURE: {
            if (!ast_is_own_function(e) || strmap_count(v) == 0) return 0;
            StrMap own;
            strmap_init(&own);
            collect_closure_names(e, &own);
            int r = captures_view(v, e, &own);
            strmap_free(&own);
            return r;
        }
        default:
            return 0;
    }
}

/* ---- the messages ---- */

/* What the value that leaves is, for the message. */
static void describe(Frame* f, ASTNode* e, char* out, size_t cap) {
    if (!e) { snprintf(out, cap, "a slice of it"); return; }
    switch (e->type) {
        case AST_SLICE_FROM_ARRAY:
        case AST_SLICE_EXPR: {
            ASTNode* c = e->child_count > 0 ? e->children[0] : NULL;
            if (c && c->type == AST_ARRAY_LITERAL)
                snprintf(out, cap, "an array literal");
            else if (c && c->type == AST_IDENTIFIER && c->value && strmap_has(&f->params, c->value))
                snprintf(out, cap, "the array parameter `%s`, its own copy", c->value);
            else if (c && c->type == AST_IDENTIFIER && c->value && strmap_has(&f->arrays, c->value))
                snprintf(out, cap, "the array `%s`", c->value);
            else
                describe(f, c, out, cap);
            return;
        }
        case AST_IDENTIFIER:
            snprintf(out, cap, "`%s`, which holds a slice of it", e->value);
            return;
        case AST_MEMBER_ACCESS:
        case AST_ARRAY_ACCESS: {
            char path[160];
            int whole;
            if (value_path(e, path, sizeof(path), &whole))
                snprintf(out, cap, "`%s`, which holds a slice of it", path);
            else
                snprintf(out, cap, "a slice of it");
            return;
        }
        case AST_STRUCT_LITERAL:
        case AST_TUPLE_LITERAL:
            snprintf(out, cap, "a value holding a slice of it");
            return;
        case AST_CLOSURE:
            snprintf(out, cap, "a closure that captured a slice of it");
            return;
        default:
            snprintf(out, cap, "a slice of it");
            return;
    }
}

static void report(Esc* esc, Frame* f, ASTNode* at, const char* message) {
    AetherError e = {
        at ? at->source_file : NULL, NULL, node_line(at), node_column(at), message,
        "copy the elements into storage that lives as long as the slice (a `make([]T, n)` "
        "buffer, or a module-level array), or use the slice only while the function runs",
        NULL, AETHER_ERR_DANGLING_VIEW
    };
    if (!e.filename && f->owner) e.filename = f->owner->source_file;
    aether_error_report(&e);
    esc->errors++;
}

typedef enum { LEAVES_BY_RETURN, LEAVES_TO_GLOBAL, LEAVES_TO_FIELD } Leaves;

/* `value`, a view of the frame's storage, leaves the frame. `target` names
 * the global or the variable whose field takes it. */
static void report_escape(Esc* esc, Frame* f, ASTNode* value, Leaves how, const char* target) {
    char what[200], msg[640];
    describe(f, value, what, sizeof(what));
    switch (how) {
        case LEAVES_BY_RETURN:
            snprintf(msg, sizeof(msg),
                     "%s returns a slice of its own storage (%s): the storage ends when %s "
                     "returns, so the slice would view memory that is gone",
                     f->shown, what, f->shown);
            break;
        case LEAVES_TO_GLOBAL:
            snprintf(msg, sizeof(msg),
                     "the module-level `%s` is given a slice of the storage of %s (%s), which "
                     "ends when %s returns, while `%s` lasts as long as the program",
                     target, f->shown, what, f->shown, target);
            break;
        case LEAVES_TO_FIELD:
        default:
            if (target)
                snprintf(msg, sizeof(msg),
                         "a field of `%s`, which outlives %s, is given a slice of its own "
                         "storage (%s): the storage ends when %s returns, so the slice would "
                         "view memory that is gone",
                         target, f->shown, what, f->shown);
            else
                snprintf(msg, sizeof(msg),
                         "a field that outlives %s is given a slice of its own storage (%s): "
                         "the storage ends when %s returns, so the slice would view memory "
                         "that is gone",
                         f->shown, what, f->shown);
            break;
    }
    report(esc, f, value, msg);
}

/* ---- the walk ---- */

/* The left side and the value of a store: `a.f = v` (a `=` in an
 * expression) or an AST_ASSIGNMENT. */
static int store_parts(ASTNode* n, ASTNode** left, ASTNode** value) {
    if (n->type == AST_BINARY_EXPRESSION && n->value && strcmp(n->value, "=") == 0 &&
        n->child_count >= 2) {
        *left = n->children[0];
        *value = n->children[1];
        return 1;
    }
    if (n->type == AST_ASSIGNMENT && n->child_count >= 2) {
        *left = n->children[0];
        *value = n->children[1];
        return 1;
    }
    return 0;
}

/* Does the lvalue's root hold its fields in the frame: a local or parameter
 * struct, array or tuple (a value the function has a copy of), not a
 * pointer to one? */
static int root_is_frame_value(Frame* f, ASTNode* root) {
    if (!root) return 0;
    ASTNode* bind = strmap_get(&f->locals, root->value);
    if (!bind) return 0;
    Type* t = bind->node_type;
    if (!t || t->kind == TYPE_UNKNOWN) t = root->node_type;
    if ((!t || t->kind == TYPE_UNKNOWN) && bind->type == AST_VARIABLE_DECLARATION &&
        bind->child_count > 0 && bind->children[0])
        t = bind->children[0]->node_type;
    return t && (t->kind == TYPE_STRUCT || t->kind == TYPE_TUPLE ||
                 is_sized_array_type(t));
}

/* `path` (a local, or a field of a local value) is given `value`: from here
 * it holds what the value holds, and nothing it held before. A store into
 * one element of an array leaves what the other elements hold. */
static void bind_path(Frame* f, Views* v, const char* path, int element, ASTNode* value) {
    int holds = frame_view(f, v, value);
    char from[256];
    int whole = 0;
    ASTNode* src = NULL;
    if (holds && value && (value->type == AST_IDENTIFIER || value->type == AST_MEMBER_ACCESS))
        src = value_path(value, from, sizeof(from), &whole);
    /* What the value holds is read before the old contents go: `v = v[1..]`. */
    Views was;
    if (src) views_copy(&was, v);
    if (!element) views_clear(v, path);
    if (!holds) {
        if (src) strmap_free(&was);
        return;
    }
    if (src && !whole) {
        /* A copy holds what its source holds, path for path. */
        views_alias(&was, from, path);
        for (int i = 0; i < strmap_count(&was); i++) {
            const char* k = strmap_key_at(&was, i);
            if (strmap_value_at(&was, i) && key_on(k, path)) views_set(v, k);
        }
        strmap_free(&was);
        return;
    }
    if (src) strmap_free(&was);
    if (value && value->type == AST_STRUCT_LITERAL && !element) {
        /* A struct literal: the fields that hold a view. */
        int any = 0;
        for (int i = 0; i < value->child_count; i++) {
            ASTNode* c = value->children[i];
            if (!c || c->type != AST_ASSIGNMENT || c->child_count != 1 || !c->value) continue;
            if (frame_view(f, v, c->children[0])) {
                char fp[256];
                snprintf(fp, sizeof(fp), "%s.%s", path, c->value);
                views_set(v, fp);
                any = 1;
            }
        }
        if (any) return;
    }
    views_set(v, path);
}

static void flow(Esc* esc, Frame* f, ASTNode* n, Views* v, int rep);

/* Each of `n`'s children, in order. */
static void flow_children(Esc* esc, Frame* f, ASTNode* n, Views* v, int rep, int from) {
    for (int i = from; i < n->child_count; i++) flow(esc, f, n->children[i], v, rep);
}

/* `n`'s children from `from`, each from the state `v` has here, joined:
 * the branches of an `if`, the arms of a `match`, the cases of a `switch`.
 * `falls` says control may pass the construct by none of them. */
static void flow_branches(Esc* esc, Frame* f, ASTNode* n, Views* v, int rep, int from,
                          int falls) {
    Views joined;
    if (falls) views_copy(&joined, v);
    else strmap_init(&joined);
    for (int i = from; i < n->child_count; i++) {
        Views arm;
        views_copy(&arm, v);
        flow(esc, f, n->children[i], &arm, rep);
        views_join(&joined, &arm);
        strmap_free(&arm);
    }
    views_move(v, &joined);
}

/* A loop: its body runs any number of times, so what holds a view at its
 * top is what held one before it or at the end of any pass, or where a
 * `continue` left; after it, also what held one where a `break` left. */
static void flow_loop(Esc* esc, Frame* f, ASTNode* n, Views* v, int rep) {
    LoopExits lx;
    strmap_init(&lx.exits);
    strmap_init(&lx.next);
    lx.outer = f->loop;
    f->loop = &lx;
    for (int pass = 0; pass < 32; pass++) {
        Views body;
        views_copy(&body, v);
        flow_children(esc, f, n, &body, 0, 0);
        int grew = views_join(v, &body);
        grew |= views_join(v, &lx.next);
        strmap_free(&body);
        if (!grew) break;
    }
    Views body;
    views_copy(&body, v);
    flow_children(esc, f, n, &body, rep, 0);
    views_join(v, &body);
    strmap_free(&body);
    views_join(v, &lx.exits);
    f->loop = lx.outer;
    strmap_free(&lx.exits);
    strmap_free(&lx.next);
}

/* A statement that is a call of one of the frame's re-binding closures,
 * `reset()`, re-binds what its body re-binds on every path, there: those
 * paths hold no view after it. A call anywhere else in an expression may
 * not run (`c && reset()`), and is not counted. */
static void rebind_by_call(Frame* f, ASTNode* st, Views* v) {
    if (!st) return;
    if (st->type == AST_EXPRESSION_STATEMENT && st->child_count > 0) st = st->children[0];
    const char* name = called_closure_name(st);
    if (!name) return;
    StrMap* paths = strmap_get(&f->rebinders, name);
    if (!paths) return;
    for (int i = 0; i < strmap_count(paths); i++)
        if (strmap_value_at(paths, i)) views_clear(v, strmap_key_at(paths, i));
}

/* A block: a name it declares with a written type is a variable of the
 * block, so what the name held outside it holds again after it (joined:
 * the block may also have bound the outer one). */
static void flow_block(Esc* esc, Frame* f, ASTNode* n, Views* v, int rep, int nested) {
    StrMap mine;
    strmap_init(&mine);
    if (nested) {
        for (int i = 0; i < n->child_count; i++) {
            ASTNode* c = n->children[i];
            if (c && c->type == AST_VARIABLE_DECLARATION && c->value && !c->type_inferred)
                strmap_put(&mine, c->value, c);
        }
    }
    Views before;
    if (strmap_count(&mine) > 0) views_copy(&before, v);
    for (int i = 0; i < n->child_count; i++) {
        flow(esc, f, n->children[i], v, rep);
        rebind_by_call(f, n->children[i], v);
    }
    if (strmap_count(&mine) > 0) {
        for (int i = 0; i < strmap_count(&mine); i++) {
            const char* name = strmap_key_at(&mine, i);
            views_clear(v, name);
            for (int j = 0; j < strmap_count(&before); j++) {
                const char* k = strmap_key_at(&before, j);
                if (strmap_value_at(&before, j) && key_on(k, name)) views_set(v, k);
            }
        }
        strmap_free(&before);
    }
    strmap_free(&mine);
}

static void flow(Esc* esc, Frame* f, ASTNode* n, Views* v, int rep) {
    if (!n || ast_is_own_function(n)) return;
    switch (n->type) {
        case AST_BLOCK:
            flow_block(esc, f, n, v, rep, n != frame_body(f->owner));
            return;
        case AST_IF_STATEMENT:
            if (n->child_count > 0) flow(esc, f, n->children[0], v, rep);
            /* With no `else`, control may pass by the one branch. */
            flow_branches(esc, f, n, v, rep, 1, n->child_count < 3);
            return;
        case AST_MATCH_STATEMENT:
            if (n->child_count > 0) flow(esc, f, n->children[0], v, rep);
            /* A match that may run no arm (no `_` arm, not covering its
             * type) is joined with the state before it as well. */
            flow_branches(esc, f, n, v, rep, 1, !ast_match_covers(n));
            return;
        case AST_SWITCH_STATEMENT: {
            if (n->child_count > 0) flow(esc, f, n->children[0], v, rep);
            /* A case is entered from the switch or from the case before it
             * falling through; the switch may run none. */
            Views joined, prev;
            views_copy(&joined, v);
            strmap_init(&prev);
            for (int i = 1; i < n->child_count; i++) {
                Views arm;
                views_copy(&arm, v);
                views_join(&arm, &prev);
                flow(esc, f, n->children[i], &arm, rep);
                views_join(&joined, &arm);
                views_move(&prev, &arm);
            }
            strmap_free(&prev);
            views_move(v, &joined);
            return;
        }
        case AST_WHILE_LOOP:
        case AST_FOR_LOOP:
            flow_loop(esc, f, n, v, rep);
            return;
        case AST_BREAK_STATEMENT:
            if (f->loop) views_join(&f->loop->exits, v);
            return;
        case AST_CONTINUE_STATEMENT:
            if (f->loop) views_join(&f->loop->next, v);
            return;
        case AST_TRY_STATEMENT: {
            /* The handler runs from wherever the body panicked: from what
             * held a view before it or at any point of it. */
            Views body;
            views_copy(&body, v);
            if (n->child_count > 0) flow(esc, f, n->children[0], &body, rep);
            Views handler;
            views_copy(&handler, v);
            views_join(&handler, &body);
            for (int i = 1; i < n->child_count; i++) flow(esc, f, n->children[i], &handler, rep);
            views_join(&body, &handler);
            views_move(v, &body);
            return;
        }
        case AST_DEFER_STATEMENT: {
            /* It runs at the exit, from whatever holds a view then: checked
             * from here, which is no less. */
            Views later;
            views_copy(&later, v);
            flow_children(esc, f, n, &later, rep, 0);
            strmap_free(&later);
            return;
        }
        case AST_RETURN_STATEMENT:
            flow_children(esc, f, n, v, rep, 0);
            if (rep) {
                for (int i = 0; i < n->child_count; i++)
                    if (frame_view(f, v, n->children[i]))
                        report_escape(esc, f, n->children[i], LEAVES_BY_RETURN, NULL);
            }
            return;
        case AST_VARIABLE_DECLARATION:
            flow_children(esc, f, n, v, rep, 0);
            if (!n->value || n->child_count == 0) return;
            if (writes_global(esc, f, n)) {
                if (rep && frame_view(f, v, n->children[0]))
                    report_escape(esc, f, n->children[0], LEAVES_TO_GLOBAL, n->value);
                return;
            }
            bind_path(f, v, n->value, 0, n->children[0]);
            return;
        default:
            break;
    }
    ASTNode *left, *value;
    if (store_parts(n, &left, &value)) {
        flow_children(esc, f, n, v, rep, 0);
        if (left && left->type == AST_IDENTIFIER && left->value) {
            if (strmap_has(&f->locals, left->value))
                bind_path(f, v, left->value, 0, value);
            else if (rep && strmap_has(&esc->globals, left->value) && frame_view(f, v, value))
                report_escape(esc, f, value, LEAVES_TO_GLOBAL, left->value);
            return;
        }
        char path[256];
        int element = 0;
        ASTNode* root = value_path(left, path, sizeof(path), &element);
        if (root && root_is_frame_value(f, root))
            bind_path(f, v, path, element, value);
        else if (rep && frame_view(f, v, value))
            report_escape(esc, f, value, LEAVES_TO_FIELD, root ? root->value : NULL);
        return;
    }
    flow_children(esc, f, n, v, rep, 0);
}

static void check_frame(Esc* esc, ASTNode* owner);

/* The closures in `n` are frames of their own. */
static void check_closures_in(Esc* esc, ASTNode* n) {
    for (int i = 0; n && i < n->child_count; i++) {
        ASTNode* c = n->children[i];
        if (!c) continue;
        if (ast_is_own_function(c)) check_frame(esc, c);
        else check_closures_in(esc, c);
    }
}

static void check_frame(Esc* esc, ASTNode* owner) {
    Frame f;
    frame_init(esc, &f, owner);
    ASTNode* body = frame_body(owner);
    Views v;
    strmap_init(&v);
    flow(esc, &f, body, &v, 1);
    strmap_free(&v);
    frame_free(&f);
    check_closures_in(esc, body);
}

int check_slice_escapes(ASTNode* program) {
    if (!program) return 0;
    Esc esc;
    memset(&esc, 0, sizeof(esc));
    strmap_init(&esc.globals);
    for (int i = 0; i < program->child_count; i++) {
        ASTNode* d = unwrap_export(program->children[i]);
        if (d && d->type == AST_CONST_DECLARATION && d->value && d->annotation &&
            strcmp(d->annotation, "global_var") == 0)
            strmap_put(&esc.globals, d->value, d);
    }
    for (int i = 0; i < program->child_count; i++) {
        ASTNode* d = unwrap_export(program->children[i]);
        if (!d) continue;
        if (d->type == AST_FUNCTION_DEFINITION || d->type == AST_BUILDER_FUNCTION ||
            d->type == AST_MAIN_FUNCTION)
            check_frame(&esc, d);
    }
    strmap_free(&esc.globals);
    return esc.errors;
}
