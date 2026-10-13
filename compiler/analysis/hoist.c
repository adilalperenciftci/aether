/* Shared hoisting rules -- see hoist.h (#2186). The logic here is what
 * codegen's hoist_if_branch_vars, hoist_common_vars and
 * hoist_loop_vars used to compute inline; they now call it, and so does the
 * typechecker. */

#include "hoist.h"

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

static Type* join_walk(ASTNode* n, const char* name, Type* acc) {
    if (!n) return acc;
    if (n->type == AST_CLOSURE || n->type == AST_QUOTE) return acc;   /* its own function */
    if (n->type == AST_VARIABLE_DECLARATION && n->value && n->type_inferred &&
        strcmp(n->value, name) == 0) {
        Type* t = n->node_type;
        if ((!t || t->kind == TYPE_UNKNOWN) && n->child_count > 0 && n->children[0])
            t = n->children[0]->node_type;
        Type* j = numeric_join_type(acc, t);
        if (j) { free_type(acc); acc = j; }
    }
    for (int i = 0; i < n->child_count; i++) acc = join_walk(n->children[i], name, acc);
    return acc;
}

Type* hoist_join_type(ASTNode* scope_body, const char* name, Type* seed) {
    if (!scope_body || !seed) return NULL;
    Type* probe = numeric_join_type(seed, seed);
    if (!probe) return NULL;          /* not a numeric kind: nothing to join */
    free_type(probe);
    Type* acc = join_walk(scope_body, name, clone_type(seed));
    if (acc && acc->kind == seed->kind) { free_type(acc); return NULL; }
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

/* Does the arm pattern `p` bind `name`: `some(name)`, or an element of a
 * list pattern (`[name, y]`, `[name | t]`)? A bare name in a pattern is a
 * value compared with, or a sum's variant, and binds nothing. */
static int pattern_binds_name(const ASTNode* p, const char* name) {
    if (!p || !name) return 0;
    if (p->type == AST_PATTERN_VARIABLE)
        return p->annotation && strcmp(p->annotation, "some_pattern") == 0 && p->value &&
               strcmp(p->value, name) == 0;
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
