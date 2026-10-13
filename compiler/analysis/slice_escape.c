/* A slice of a function's own storage must not outlive the function. See
 * slice_escape.h. */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "slice_escape.h"
#include "../aether_error.h"
#include "../aether_strmap.h"

#define ESC_LOCAL ((void*)1)
#define ESC_PARAM ((void*)2)

typedef struct {
    StrMap globals;   /* module-level `var` names */
    int errors;
} Esc;

/* One function, closure or `main`: what its frame holds. */
typedef struct {
    ASTNode* owner;
    char shown[160];  /* its name as the source writes it, for messages */
    StrMap typed;     /* names a written-type declaration binds */
    StrMap locals;    /* name -> its binding node (a local or a parameter) */
    StrMap params;    /* the parameters among them */
    StrMap arrays;    /* the frame's own fixed-size arrays: name -> declaration */
    StrMap views;     /* locals that hold a slice of the frame's storage */
} Frame;

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

static ASTNode* frame_body(ASTNode* owner) {
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
    strmap_init(&f->views);
    if (owner->type == AST_MAIN_FUNCTION) {
        snprintf(f->shown, sizeof(f->shown), "'main'");
    } else if (owner->type == AST_CLOSURE) {
        snprintf(f->shown, sizeof(f->shown), "this closure");
    } else {
        char buf[160];
        snprintf(f->shown, sizeof(f->shown), "'%s'", ast_source_name(owner, buf, sizeof(buf)));
    }
    /* Parameters: a function's children ahead of its body, a closure's
     * AST_CLOSURE_PARAMs. Their storage is the caller's. */
    for (int i = 0; i < owner->child_count; i++) {
        ASTNode* p = owner->children[i];
        if (!p || p->type == AST_BLOCK || !p->value) continue;
        if (p->type == AST_PATTERN_VARIABLE || p->type == AST_VARIABLE_DECLARATION ||
            p->type == AST_CLOSURE_PARAM) {
            strmap_put(&f->locals, p->value, p);
            strmap_put(&f->params, p->value, p);
        }
    }
    ASTNode* body = owner->type == AST_MAIN_FUNCTION
        ? (owner->child_count > 0 ? owner->children[0] : NULL) : frame_body(owner);
    collect_typed(f, body);
    collect_locals(esc, f, body);
}

static void frame_free(Frame* f) {
    strmap_free(&f->typed);
    strmap_free(&f->locals);
    strmap_free(&f->params);
    strmap_free(&f->arrays);
    strmap_free(&f->views);
}

/* Is `e` storage of the frame: a non-empty array literal (it lives in the
 * frame as the array it is), or one of the frame's own fixed-size arrays? */
static int frame_storage(Frame* f, ASTNode* e) {
    if (!e) return 0;
    if (e->type == AST_ARRAY_LITERAL) return e->child_count > 0;
    if (e->type == AST_IDENTIFIER && e->value) return strmap_has(&f->arrays, e->value);
    return 0;
}

static int frame_view(Frame* f, ASTNode* e);

/* Does the closure `c` capture one of the frame's views (a name it does not
 * bind itself)? A captured slice is copied into the closure as it is, and so
 * still views the frame. A captured array is copied whole, and does not. */
static int captures_view(Frame* f, ASTNode* n, StrMap* own) {
    if (!n) return 0;
    if (n->type == AST_IDENTIFIER && n->value && strmap_has(&f->views, n->value) &&
        !strmap_has(own, n->value))
        return 1;
    for (int i = 0; i < n->child_count; i++)
        if (captures_view(f, n->children[i], own)) return 1;
    return 0;
}

static void collect_closure_names(ASTNode* n, StrMap* own) {
    if (!n) return;
    if ((n->type == AST_VARIABLE_DECLARATION || n->type == AST_CLOSURE_PARAM ||
         n->type == AST_PATTERN_VARIABLE) && n->value)
        strmap_put(own, n->value, n);
    for (int i = 0; i < n->child_count; i++) collect_closure_names(n->children[i], own);
}

/* Is the value `e` a slice of the frame's storage, or something holding one
 * (a struct literal, a closure)? */
static int frame_view(Frame* f, ASTNode* e) {
    if (!e) return 0;
    switch (e->type) {
        case AST_SLICE_FROM_ARRAY:
            return e->child_count > 0 && frame_storage(f, e->children[0]);
        case AST_SLICE_EXPR:
            return e->child_count > 0 &&
                   (frame_storage(f, e->children[0]) || frame_view(f, e->children[0]));
        case AST_IDENTIFIER:
            return e->value && strmap_has(&f->views, e->value);
        case AST_EXPRESSION_STATEMENT:
            return e->child_count > 0 && frame_view(f, e->children[0]);
        case AST_IF_EXPRESSION:
            return (e->child_count > 1 && frame_view(f, e->children[1])) ||
                   (e->child_count > 2 && frame_view(f, e->children[2]));
        case AST_MATCH_STATEMENT:
            for (int i = 1; i < e->child_count; i++) {
                ASTNode* arm = e->children[i];
                if (arm && arm->type == AST_MATCH_ARM && arm->child_count > 1 &&
                    frame_view(f, match_arm_value(arm->children[1])))
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
                if (frame_view(f, c)) return 1;
            }
            return 0;
        case AST_CLOSURE: {
            if (!ast_is_own_function(e) || strmap_count(&f->views) == 0) return 0;
            StrMap own;
            strmap_init(&own);
            collect_closure_names(e, &own);
            int r = captures_view(f, e, &own);
            strmap_free(&own);
            return r;
        }
        default:
            return 0;
    }
}

/* The left side and the value of a store: `x = v` (a declaration that
 * binds), `a.f = v` (a `=` in an expression), or an AST_ASSIGNMENT. */
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

/* The variable an lvalue `a.f[i].g` writes into: `a`, or NULL when it is
 * not a name (a call's result, a dereference). */
static ASTNode* lvalue_root(ASTNode* l) {
    while (l && (l->type == AST_MEMBER_ACCESS || l->type == AST_ARRAY_ACCESS) &&
           l->child_count > 0)
        l = l->children[0];
    return (l && l->type == AST_IDENTIFIER && l->value) ? l : NULL;
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

/* Which locals hold a view: bound to one, or a local value one is stored
 * into. */
static int mark_views(Esc* esc, Frame* f, ASTNode* n) {
    if (!n || ast_is_own_function(n)) return 0;
    int changed = 0;
    if (n->type == AST_VARIABLE_DECLARATION && n->value && n->child_count > 0 &&
        !writes_global(esc, f, n) && !strmap_has(&f->views, n->value) &&
        frame_view(f, n->children[0])) {
        strmap_put(&f->views, n->value, n);
        changed = 1;
    }
    ASTNode *left, *value;
    if (store_parts(n, &left, &value) && frame_view(f, value)) {
        ASTNode* target = NULL;
        if (left && left->type == AST_IDENTIFIER && left->value &&
            strmap_has(&f->locals, left->value))
            target = left;
        else {
            ASTNode* root = lvalue_root(left);
            if (root && root != left && root_is_frame_value(f, root)) target = root;
        }
        if (target && !strmap_has(&f->views, target->value)) {
            strmap_put(&f->views, target->value, target);
            changed = 1;
        }
    }
    for (int i = 0; i < n->child_count; i++) changed |= mark_views(esc, f, n->children[i]);
    return changed;
}

/* What the value that leaves is, for the message. */
static void describe(Frame* f, ASTNode* e, char* out, size_t cap) {
    if (!e) { snprintf(out, cap, "a slice of it"); return; }
    switch (e->type) {
        case AST_SLICE_FROM_ARRAY:
        case AST_SLICE_EXPR: {
            ASTNode* c = e->child_count > 0 ? e->children[0] : NULL;
            if (c && c->type == AST_ARRAY_LITERAL)
                snprintf(out, cap, "an array literal");
            else if (c && c->type == AST_IDENTIFIER && c->value && strmap_has(&f->arrays, c->value))
                snprintf(out, cap, "the array `%s`", c->value);
            else
                describe(f, c, out, cap);
            return;
        }
        case AST_IDENTIFIER:
            snprintf(out, cap, "`%s`, which holds a slice of it", e->value);
            return;
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

static void find_escapes(Esc* esc, Frame* f, ASTNode* n) {
    if (!n || ast_is_own_function(n)) return;
    if (n->type == AST_RETURN_STATEMENT) {
        for (int i = 0; i < n->child_count; i++)
            if (frame_view(f, n->children[i]))
                report_escape(esc, f, n->children[i], LEAVES_BY_RETURN, NULL);
    }
    if (n->type == AST_VARIABLE_DECLARATION && n->child_count > 0 && writes_global(esc, f, n) &&
        frame_view(f, n->children[0]))
        report_escape(esc, f, n->children[0], LEAVES_TO_GLOBAL, n->value);
    ASTNode *left, *value;
    if (store_parts(n, &left, &value) && frame_view(f, value)) {
        if (left && left->type == AST_IDENTIFIER && left->value) {
            if (!strmap_has(&f->locals, left->value) && strmap_has(&esc->globals, left->value))
                report_escape(esc, f, value, LEAVES_TO_GLOBAL, left->value);
        } else {
            ASTNode* root = lvalue_root(left);
            if (!root_is_frame_value(f, root))
                report_escape(esc, f, value, LEAVES_TO_FIELD, root ? root->value : NULL);
        }
    }
    for (int i = 0; i < n->child_count; i++) find_escapes(esc, f, n->children[i]);
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
    ASTNode* body = owner->type == AST_MAIN_FUNCTION
        ? (owner->child_count > 0 ? owner->children[0] : NULL) : frame_body(owner);
    for (int pass = 0; pass < 64 && mark_views(esc, &f, body); pass++) {}
    find_escapes(esc, &f, body);
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
