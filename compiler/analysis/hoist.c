/* Shared hoisting rules -- see hoist.h (#2186). The logic here is what
 * codegen's hoist_if_branch_vars, hoist_common_vars and
 * hoist_loop_vars used to compute inline; they now call it, and so does the
 * typechecker. */

#include "hoist.h"
#include "../aether_strmap.h"

#include <stdlib.h>
#include <string.h>

int hoist_direct_decl_names(ASTNode* block, const char** out, int count, int cap) {
    if (!block || !out) return count;
    for (int i = 0; i < block->child_count; i++) {
        ASTNode* child = block->children[i];
        if (!child) continue;
        if (child->type == AST_VARIABLE_DECLARATION && child->value && count < cap) {
            int already = 0;
            for (int j = 0; j < count; j++) {
                if (strcmp(out[j], child->value) == 0) { already = 1; break; }
            }
            if (!already) out[count++] = child->value;
        }
    }
    return count;
}

ASTNode* hoist_find_decl(ASTNode* block, const char* name) {
    if (!block || !name) return NULL;
    for (int i = 0; i < block->child_count; i++) {
        ASTNode* child = block->children[i];
        if (!child) continue;
        if (child->type == AST_VARIABLE_DECLARATION && child->value
            && strcmp(child->value, name) == 0) {
            return child;
        }
    }
    return NULL;
}

int hoist_has_identifier_ref(ASTNode* node, const char* name) {
    if (!node || !name) return 0;
    if (node->type == AST_IDENTIFIER && node->value &&
        strcmp(node->value, name) == 0) return 1;
    /* Any identifier counts as a use; declaration order within a subtree is
     * not tracked. Over-eager, and safe: an extra hoisted declaration is a
     * zero-initialised local. */
    for (int i = 0; i < node->child_count; i++) {
        if (hoist_has_identifier_ref(node->children[i], name)) return 1;
    }
    return 0;
}

Type* hoist_decl_type(ASTNode* decl) {
    if (!decl) return NULL;
    Type* t = decl->node_type;
    if ((!t || t->kind == TYPE_VOID || t->kind == TYPE_UNKNOWN)
        && decl->child_count > 0 && decl->children[0] && decl->children[0]->node_type) {
        t = decl->children[0]->node_type;
    }
    return t;
}

/* Is `t` a number kind (numeric_join_type's)? */
static int is_number_type(Type* t) {
    Type* probe = t ? numeric_join_type(t, t) : NULL;
    if (!probe) return 0;
    free_type(probe);
    return 1;
}

/* #3064: what binding `n` of a name gives a join: its type when that is a
 * number, NULL otherwise. A declaration that writes its type is that type
 * (`*written`), and its value no literal arm; an inferred one is its
 * value's type until it has its own. `*arm` is the value a literal is read
 * from. */
static Type* join_part(const ASTNode* n, const ASTNode** arm, int* written) {
    Type* t = n->node_type;
    const ASTNode* v = n->type_inferred && n->child_count > 0 ? n->children[0] : NULL;
    if ((!t || t->kind == TYPE_UNKNOWN) && v) t = v->node_type;
    *arm = v;
    *written = !n->type_inferred;
    return is_number_type(t) ? t : NULL;
}

/* The join of a name's bindings, part by part. */
typedef struct {
    Type* acc;           /* the inferred parts' join */
    const ASTNode* arm;  /* the arm it is read by (join_arm_after) */
    int apart;           /* two inferred parts no type holds */
    Type* written;       /* #3070: the first written part */
} JoinFold;

/* One part `t` (arm `v`) into the fold. Inferred parts join as an
 * if-expression's branches do (branch_join_type), each part's value the
 * arm a literal is read from (join_arm_after): `x = -1` in one branch and
 * `x = u` (a uint32) in another is a long, `x = 0` beside it a uint32. Two
 * that no type holds (a signed one beside a uint64) are apart. #3070: a
 * written type is the variable's type, whatever the inferred parts are:
 * one the written type does not hold is the checker's to refuse
 * (ast_number_holds). No part (NULL) leaves the fold as it is. */
static void fold_add(JoinFold* f, Type* t, const ASTNode* v, int written) {
    if (!t) return;
    if (written) {
        if (!f->written) f->written = clone_type(t);
        return;
    }
    if (f->apart) return;
    if (!f->acc) {
        f->acc = clone_type(t);
        f->arm = v;
        return;
    }
    Type* j = branch_join_type(f->acc, f->arm, t, v);
    if (!j) {
        f->apart = 1;
        return;
    }
    free_type(f->acc);
    f->acc = j;
    f->arm = join_arm_after(f->arm, v);
}

/* What the fold joins to, a fresh Type: the written type, else the
 * inferred parts' join; NULL for none, or two apart. */
static Type* fold_result(const JoinFold* f) {
    if (f->written) return clone_type(f->written);
    return f->apart || !f->acc ? NULL : clone_type(f->acc);
}

static void fold_copy(JoinFold* to, const JoinFold* from) {
    to->acc = from->acc ? clone_type(from->acc) : NULL;
    to->arm = from->arm;
    to->apart = from->apart;
    to->written = from->written ? clone_type(from->written) : NULL;
}

static void fold_free(JoinFold* f) {
    if (f->acc) free_type(f->acc);
    if (f->written) free_type(f->written);
    memset(f, 0, sizeof(*f));
}

static void fold_bind(JoinFold* f, const ASTNode* n) {
    const ASTNode* v = NULL;
    int written = 0;
    Type* t = join_part(n, &v, &written);
    fold_add(f, t, v, written);
}

/* The bindings of `name` under `n` (closures excluded, each its own
 * function), joined in the order they are written. */
static void join_walk(ASTNode* n, const char* name, JoinFold* f) {
    if (!n) return;
    if (n->type == AST_CLOSURE || n->type == AST_QUOTE) return;   /* its own function */
    if (n->type == AST_VARIABLE_DECLARATION && n->value && strcmp(n->value, name) == 0)
        fold_bind(f, n);
    for (int i = 0; i < n->child_count; i++) join_walk(n->children[i], name, f);
}

static JoinFold fold_of(ASTNode* root, const char* name) {
    JoinFold f;
    memset(&f, 0, sizeof(f));
    for (int i = 0; root && name && i < root->child_count; i++)
        join_walk(root->children[i], name, &f);
    return f;
}

Type* hoist_numeric_join(ASTNode* root, const char* name) {
    JoinFold f = fold_of(root, name);
    Type* r = fold_result(&f);
    fold_free(&f);
    return r;
}

Type* hoist_numeric_written(ASTNode* root, const char* name) {
    JoinFold f = fold_of(root, name);
    Type* written = f.written;
    f.written = NULL;
    fold_free(&f);
    return written;
}

/* #3064: the bindings of one name under a HoistJoins' root, in the order
 * join_walk meets them, and what the walk typing them has made of them.
 * The walk types binds[0..typed) in that order; their parts are final for
 * it, folded in `head`. A binding not typed yet changes only when the walk
 * types it, so the parts of binds[typed..count) that `join` read (`rest`,
 * those that are numbers) stand until then, and `join` with them. */
typedef struct {
    const ASTNode* bind;
    const ASTNode* arm;
    Type* part;
    int written;
} JoinRest;

typedef struct {
    const ASTNode** binds;
    int count;
    int cap;
    int typed;
    int unordered;        /* typed out of order, or twice: each ask joins them all */
    int started;          /* `head` and `rest` are kept from the first ask on */
    JoinFold head;
    JoinRest* rest;
    int rest_count;
    int rest_next;        /* rest[0..rest_next) are typed now, and in `head` */
    int fresh;            /* `join` is the join of `head` and the rest */
    Type* join;
} HoistNameJoin;

struct HoistJoins {
    StrMap names;   /* name -> HoistNameJoin* */
};

static void joins_collect(ASTNode* n, HoistJoins* j) {
    if (!n) return;
    if (n->type == AST_CLOSURE || n->type == AST_QUOTE) return;   /* its own function */
    if (n->type == AST_VARIABLE_DECLARATION && n->value) {
        HoistNameJoin* nj = (HoistNameJoin*)strmap_get(&j->names, n->value);
        if (!nj) {
            nj = (HoistNameJoin*)calloc(1, sizeof(HoistNameJoin));
            if (!nj) return;
            strmap_put(&j->names, n->value, nj);
        }
        if (nj->count == nj->cap) {
            nj->cap = nj->cap ? nj->cap * 2 : 4;
            nj->binds = (const ASTNode**)aether_xrealloc((void*)nj->binds,
                                                         (size_t)nj->cap * sizeof(ASTNode*));
        }
        nj->binds[nj->count++] = n;
    }
    for (int i = 0; i < n->child_count; i++) joins_collect(n->children[i], j);
}

HoistJoins* hoist_joins_new(ASTNode* root) {
    HoistJoins* j = (HoistJoins*)calloc(1, sizeof(HoistJoins));
    if (!j) return NULL;
    strmap_init(&j->names);
    for (int i = 0; root && i < root->child_count; i++) joins_collect(root->children[i], j);
    return j;
}

static void name_join_forget(HoistNameJoin* nj) {
    fold_free(&nj->head);
    for (int i = 0; i < nj->rest_count; i++) free_type(nj->rest[i].part);
    free(nj->rest);
    nj->rest = NULL;
    nj->rest_count = nj->rest_next = 0;
    if (nj->join) free_type(nj->join);
    nj->join = NULL;
    nj->fresh = 0;
}

void hoist_joins_typed(HoistJoins* j, const ASTNode* decl) {
    HoistNameJoin* nj = j && decl && decl->value
                        ? (HoistNameJoin*)strmap_get(&j->names, decl->value) : NULL;
    if (!nj || nj->unordered) return;
    if (nj->typed >= nj->count || nj->binds[nj->typed] != decl) {
        /* Typed again, or before a binding written ahead of it (one in
         * another's value): every ask joins them all from here on. */
        nj->unordered = 1;
        name_join_forget(nj);
        return;
    }
    nj->typed++;
    if (!nj->started) return;
    const ASTNode* v = NULL;
    int written = 0;
    Type* t = join_part(decl, &v, &written);
    fold_add(&nj->head, t, v, written);
    /* Its part as `join` read it: none, or the one `rest` holds. */
    JoinRest* r = nj->rest_next < nj->rest_count && nj->rest[nj->rest_next].bind == decl
                  ? &nj->rest[nj->rest_next] : NULL;
    if (r) nj->rest_next++;
    if (nj->fresh && (r ? !t || !types_equal(t, r->part) : t != NULL)) nj->fresh = 0;
}

Type* hoist_joins_get(HoistJoins* j, const char* name) {
    HoistNameJoin* nj = j && name ? (HoistNameJoin*)strmap_get(&j->names, name) : NULL;
    if (!nj) return NULL;
    JoinFold f;
    memset(&f, 0, sizeof(f));
    if (nj->unordered) {
        for (int i = 0; i < nj->count; i++) fold_bind(&f, nj->binds[i]);
        Type* r = fold_result(&f);
        fold_free(&f);
        return r;
    }
    if (!nj->started) {
        nj->started = 1;
        if (nj->count > nj->typed)
            nj->rest = (JoinRest*)aether_xrealloc(NULL, (size_t)(nj->count - nj->typed) *
                                                            sizeof(JoinRest));
        for (int i = 0; i < nj->count; i++) {
            const ASTNode* v = NULL;
            int written = 0;
            Type* t = join_part(nj->binds[i], &v, &written);
            if (i < nj->typed) {
                fold_add(&nj->head, t, v, written);
            } else if (t) {
                JoinRest* r = &nj->rest[nj->rest_count++];
                r->bind = nj->binds[i];
                r->arm = v;
                r->part = clone_type(t);
                r->written = written;
            }
        }
    }
    if (!nj->fresh) {
        fold_copy(&f, &nj->head);
        for (int i = nj->rest_next; i < nj->rest_count; i++)
            fold_add(&f, nj->rest[i].part, nj->rest[i].arm, nj->rest[i].written);
        if (nj->join) free_type(nj->join);
        nj->join = fold_result(&f);
        fold_free(&f);
        nj->fresh = 1;
    }
    return nj->join ? clone_type(nj->join) : NULL;
}

void hoist_joins_free(HoistJoins* j) {
    if (!j) return;
    for (int i = 0; i < strmap_count(&j->names); i++) {
        HoistNameJoin* nj = (HoistNameJoin*)strmap_value_at(&j->names, i);
        if (!nj) continue;
        name_join_forget(nj);
        free((void*)nj->binds);
        free(nj);
    }
    strmap_free(&j->names);
    free(j);
}

/* Over the inferred bindings of `name` in `n` (closures excluded): sets
 * `*strings` when one is a string, `*others` when one is neither a string
 * nor `null`. */
static void null_string_walk(ASTNode* n, const char* name, int* strings, int* others) {
    if (!n) return;
    if (n->type == AST_CLOSURE || n->type == AST_QUOTE) return;
    if (n->type == AST_VARIABLE_DECLARATION && n->value && n->type_inferred &&
        strcmp(n->value, name) == 0) {
        ASTNode* init = n->child_count > 0 ? n->children[0] : NULL;
        Type* t = hoist_decl_type(n);
        if (init && init->type == AST_NULL_LITERAL) {
            /* `null` fits any pointer kind, a string included */
        } else if (t && t->kind == TYPE_STRING) {
            *strings = 1;
        } else {
            *others = 1;
        }
    }
    for (int i = 0; i < n->child_count; i++) null_string_walk(n->children[i], name, strings, others);
}

/* #2980 review: over the inferred bindings of `name` in `n` (closures
 * excluded), function values joined with `acc` by fn_type_mode_join. */
static Type* fn_join_walk(ASTNode* n, const char* name, Type* acc) {
    if (!n) return acc;
    if (n->type == AST_CLOSURE || n->type == AST_QUOTE) return acc;
    if (n->type == AST_VARIABLE_DECLARATION && n->value && n->type_inferred &&
        strcmp(n->value, name) == 0) {
        Type* j = fn_type_mode_join(acc, hoist_decl_type(n));
        if (j) { free_type(acc); acc = j; }
    }
    for (int i = 0; i < n->child_count; i++) acc = fn_join_walk(n->children[i], name, acc);
    return acc;
}

Type* hoist_join_type(ASTNode* scope_body, const char* name, Type* seed) {
    if (!scope_body || !seed) return NULL;
    /* #2980 review: a local bound to functions in two branches is called
     * through the stronger mode at each parameter, where either may stand;
     * typed from the first binding alone, a `@keep` in the other was lost. */
    if (seed->kind == TYPE_FUNCTION) {
        Type* acc = fn_join_walk(scope_body, name, clone_type(seed));
        if (acc && types_equal(acc, seed)) { free_type(acc); return NULL; }
        return acc;
    }
    /* #3032: a `null` binding names no type of its own. A local hoisted
     * from `t = null` in one branch and `t = "b"` in another is a string,
     * as the same two bindings in one block make it. Joined as the `ptr` of
     * its first binding, it was a `ptr` that codegen managed as a string,
     * which a `string` local could not take (E0202). */
    if (seed->kind == TYPE_PTR && !seed->element_type) {
        int strings = 0, others = 0;
        null_string_walk(scope_body, name, &strings, &others);
        if (strings && !others) return create_type(TYPE_STRING);
    }
    if (!is_number_type(seed)) return NULL;   /* not a numeric kind: nothing to join */
    /* #3064: the bindings' own join, as an if-expression's; with two that
     * no type holds, the seed stands and the checker refuses the other
     * (sibling_binding_other_type). #3070: a written type is the join, and
     * the checker refuses a binding it does not hold. */
    Type* acc = hoist_numeric_join(scope_body, name);
    if (acc && types_equal(acc, seed)) { free_type(acc); return NULL; }
    return acc;
}

/* The arms of a branching statement: an if's then and else blocks, a
 * switch's case statements, whose children (after a case's selector) are
 * its body, or a match's arm bodies. A case's selector is never a
 * declaration, so the case node itself is the body hoist_direct_decl_names
 * and hoist_find_decl read (#2732). A match arm that binds a name has a
 * block body (the parser makes `1 -> v = 10` the block `{ v = 10 }`); any
 * other arm body is a value or a statement that binds nothing, and counts
 * as an arm all the same (#2768). Returns the count written to `arms` (at
 * most `cap`), 0 for any other statement. */
static int branch_arms(ASTNode* stmt, ASTNode** arms, int cap) {
    int n = 0;
    if (!stmt) return 0;
    if (stmt->type == AST_IF_STATEMENT) {
        for (int j = 1; j < stmt->child_count && j < 3 && n < cap; j++)
            arms[n++] = stmt->children[j];
    } else if (stmt->type == AST_SWITCH_STATEMENT) {
        for (int j = 1; j < stmt->child_count && n < cap; j++) {
            ASTNode* c = stmt->children[j];
            if (c && c->type == AST_CASE_STATEMENT) arms[n++] = c;
        }
    } else if (stmt->type == AST_MATCH_STATEMENT) {
        for (int j = 1; j < stmt->child_count && n < cap; j++) {
            ASTNode* a = stmt->children[j];
            if (a && a->type == AST_MATCH_ARM && a->child_count > 1 && a->children[1])
                arms[n++] = a->children[1];
        }
    }
    return n;
}

/* Is `stmt` a statement whose arms branch_arms lists? */
static int is_branching(ASTNode* stmt) {
    return stmt && (stmt->type == AST_IF_STATEMENT || stmt->type == AST_SWITCH_STATEMENT ||
                    stmt->type == AST_MATCH_STATEMENT);
}

/* Does the arm pattern `p` bind `name`: `some(name)`, an element of a
 * list pattern (`[name, y]`, `[name | t]`), or a field of a struct pattern
 * (`Pt { x: name }`)? A bare name in a pattern is a
 * value compared with, or a sum's variant, and binds nothing. */
static int pattern_binds_name(const ASTNode* p, const char* name) {
    if (!p || !name) return 0;
    if (p->type == AST_PATTERN_VARIABLE)
        return p->annotation && strcmp(p->annotation, "some_pattern") == 0 && p->value &&
               strcmp(p->value, name) == 0;
    /* #2992: a struct pattern binds the names its fields take, and those of
     * a struct pattern over a field. */
    if (p->type == AST_PATTERN_STRUCT) {
        for (int i = 0; i < p->child_count; i++) {
            const ASTNode* fp = p->children[i];
            const ASTNode* sub = (fp && fp->type == AST_ASSIGNMENT && fp->child_count > 0)
                                 ? fp->children[0] : NULL;
            if (!sub) continue;
            if (sub->type == AST_PATTERN_VARIABLE && sub->value && strcmp(sub->value, name) == 0)
                return 1;
            if (sub->type == AST_PATTERN_STRUCT && pattern_binds_name(sub, name)) return 1;
        }
        return 0;
    }
    if (p->type != AST_PATTERN_LIST && p->type != AST_PATTERN_CONS) return 0;
    for (int i = 0; i < p->child_count; i++) {
        const ASTNode* e = p->children[i];
        if (e && e->type == AST_PATTERN_VARIABLE && e->value && strcmp(e->value, name) == 0)
            return 1;
    }
    return 0;
}

/* #2768: does an arm pattern of `stmt`, a match, bind `name`? Such a name
 * is the arm's own, and is not hoisted out of the match by any rule: a
 * binding of it in that arm rebinds the pattern's value, and one in another
 * arm stays in its arm too, so a read after the match is no read of either
 * (the checker's "Undefined variable"). */
static int match_pattern_binds(const ASTNode* stmt, const char* name) {
    if (!stmt || stmt->type != AST_MATCH_STATEMENT || !name) return 0;
    for (int i = 1; i < stmt->child_count; i++) {
        const ASTNode* a = stmt->children[i];
        if (a && a->type == AST_MATCH_ARM && a->child_count > 0 &&
            pattern_binds_name(a->children[0], name))
            return 1;
    }
    return 0;
}

#define HOIST_MAX_ARMS 256

int hoist_if_branch_candidates(ASTNode* body, const char** out, int cap) {
    if (!body || !out) return 0;
    /* Names a top-level statement declares get their own function-scope
     * declaration (and heap tracker) where they are; hoisting them from an
     * arm as well would declare them twice. */
    const char* top_level_decls[HOIST_MAX_NAMES];
    int top_count = 0;
    for (int i = 0; i < body->child_count && top_count < HOIST_MAX_NAMES; i++) {
        ASTNode* child = body->children[i];
        if (!child) continue;
        if (child->type == AST_VARIABLE_DECLARATION && child->value) {
            top_level_decls[top_count++] = child->value;
        }
    }

    const char* names[HOIST_MAX_NAMES];
    int count = 0;
    for (int i = 0; i < body->child_count; i++) {
        ASTNode* arms[HOIST_MAX_ARMS];
        int na = branch_arms(body->children[i], arms, HOIST_MAX_ARMS);
        for (int j = 0; j < na; j++) {
            count = hoist_direct_decl_names(arms[j], names, count, HOIST_MAX_NAMES);
        }
    }
    /* A name a match's pattern binds comes out of no arm of that match;
     * hoist_if_branch_first_decl, below, finds a binding of it elsewhere or
     * none. */

    int kept = 0;
    for (int n = 0; n < count && kept < cap; n++) {
        const char* name = names[n];
        int dup = 0;
        for (int k = 0; k < top_count; k++) {
            if (strcmp(name, top_level_decls[k]) == 0) { dup = 1; break; }
        }
        if (dup) continue;
        /* Only a name read outside the arms -- by a top-level statement that
         * does not branch, or by an if's condition or a switch's or a
         * match's subject -- is hoisted. */
        int referenced_outside = 0;
        for (int i = 0; i < body->child_count && !referenced_outside; i++) {
            ASTNode* child = body->children[i];
            if (!child) continue;
            if (is_branching(child)) {
                if (child->child_count > 0 &&
                    hoist_has_identifier_ref(child->children[0], name)) {
                    referenced_outside = 1;
                }
                continue;
            }
            if (hoist_has_identifier_ref(child, name)) referenced_outside = 1;
        }
        if (!referenced_outside) continue;
        if (!hoist_if_branch_first_decl(body, name)) continue;
        out[kept++] = name;
    }
    return kept;
}

ASTNode* hoist_if_branch_first_decl(ASTNode* body, const char* name) {
    if (!body) return NULL;
    for (int i = 0; i < body->child_count; i++) {
        if (match_pattern_binds(body->children[i], name)) continue;
        ASTNode* arms[HOIST_MAX_ARMS];
        int na = branch_arms(body->children[i], arms, HOIST_MAX_ARMS);
        for (int j = 0; j < na; j++) {
            ASTNode* d = hoist_find_decl(arms[j], name);
            if (d) return d;
        }
    }
    return NULL;
}

int hoist_common_decl_names(ASTNode* stmt, const char** out, int cap) {
    if (!stmt || !out) return 0;
    ASTNode* arms[HOIST_MAX_ARMS];
    int na = branch_arms(stmt, arms, HOIST_MAX_ARMS);
    /* Every path must pass through an arm: an if needs its else, a switch
     * its default, a match a `_` arm or arms that cover its type (#2768). */
    if (stmt->type == AST_IF_STATEMENT && na < 2) return 0;
    if (stmt->type == AST_SWITCH_STATEMENT) {
        int has_default = 0;
        for (int j = 0; j < na; j++) {
            if (arms[j]->value && strcmp(arms[j]->value, "default") == 0) has_default = 1;
        }
        if (!has_default || na < 2) return 0;
    }
    if (stmt->type == AST_MATCH_STATEMENT && !ast_match_covers(stmt)) return 0;
    if (na == 0) return 0;
    const char* first[HOIST_MAX_NAMES];
    int nfirst = hoist_direct_decl_names(arms[0], first, 0, HOIST_MAX_NAMES);
    int kept = 0;
    for (int i = 0; i < nfirst && kept < cap; i++) {
        int everywhere = !match_pattern_binds(stmt, first[i]);
        for (int j = 1; j < na && everywhere; j++) {
            if (!hoist_find_decl(arms[j], first[i])) everywhere = 0;
        }
        if (everywhere) out[kept++] = first[i];
    }
    return kept;
}

ASTNode* hoist_common_first_decl(ASTNode* stmt, const char* name) {
    ASTNode* arms[HOIST_MAX_ARMS];
    int na = branch_arms(stmt, arms, HOIST_MAX_ARMS);
    ASTNode* any = NULL;
    for (int j = 0; j < na; j++) {
        ASTNode* d = hoist_find_decl(arms[j], name);
        if (!d) continue;
        if (!any) any = d;
        Type* t = hoist_decl_type(d);
        if (t && t->kind != TYPE_VOID && t->kind != TYPE_UNKNOWN) return d;
    }
    return any;
}

/* The matches whose arms a hoist_loop_decls walk is inside, innermost last:
 * a name one of their patterns binds is declared in no loop hoist. */
#define HOIST_MAX_MATCH_DEPTH 64
typedef struct {
    HoistDeclVisitor visit;
    void* user;
    const ASTNode* matches[HOIST_MAX_MATCH_DEPTH];
    int depth;
} LoopWalk;

static void loop_decls_walk(ASTNode* body, LoopWalk* w) {
    if (!body) return;
    for (int i = 0; i < body->child_count; i++) {
        ASTNode* child = body->children[i];
        if (!child) continue;
        if (child->type == AST_VARIABLE_DECLARATION && child->value) {
            int own = 0;
            for (int m = 0; m < w->depth && !own; m++)
                own = match_pattern_binds(w->matches[m], child->value);
            if (!own) w->visit(child, w->user);
        }
        /* A switch's children are its cases, whose own children are their
         * bodies: they are visited as an if's arms are (#2732). A match's
         * are its arms, whose bodies are visited the same way (#2768). */
        if (child->type == AST_IF_STATEMENT || child->type == AST_WHILE_LOOP ||
            child->type == AST_FOR_LOOP || child->type == AST_SWITCH_STATEMENT) {
            for (int j = 0; j < child->child_count; j++) loop_decls_walk(child->children[j], w);
        } else if (child->type == AST_MATCH_STATEMENT && w->depth < HOIST_MAX_MATCH_DEPTH) {
            ASTNode* arms[HOIST_MAX_ARMS];
            int na = branch_arms(child, arms, HOIST_MAX_ARMS);
            w->matches[w->depth++] = child;
            for (int j = 0; j < na; j++) loop_decls_walk(arms[j], w);
            w->depth--;
        }
    }
}

void hoist_loop_decls(ASTNode* body, HoistDeclVisitor visit, void* user) {
    if (!body || !visit) return;
    LoopWalk w;
    w.visit = visit;
    w.user = user;
    w.depth = 0;
    loop_decls_walk(body, &w);
}
