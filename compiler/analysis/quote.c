/* `quote`: a trailing block handed over as a tree (docs/quote.md).
 *
 * The type checker has checked the body as a closure's. Here it is
 *   1. checked against version 1's subset (each construct the tree has no
 *      node for is an error naming it, at its line);
 *   2. lowered to the tree it stands for, every node carrying the type the
 *      checker gave it, each outer variable it reads recorded as a capture;
 *   3. hashed, so a back end can cache what it makes from it.
 * Codegen then emits one builder per quote (quote_emit_builder) that makes
 * the same tree at run time through std.quote's runtime. */

#include "quote.h"
#include "typechecker.h"

#include <stdlib.h>
#include <string.h>

static QuoteInfo** g_quotes = NULL;
static int g_quote_count = 0;
static int g_quote_cap = 0;

int quote_count(void) { return g_quote_count; }
QuoteInfo* quote_at(int index) {
    return (index >= 0 && index < g_quote_count) ? g_quotes[index] : NULL;
}

QuoteInfo* quote_of(ASTNode* node) {
    if (!node || node->type != AST_QUOTE || !node->value) return NULL;
    QuoteInfo* q = quote_at(atoi(node->value));
    return (q && q->node == node) ? q : NULL;
}

static void free_qnode(QNode* n) {
    if (!n) return;
    for (int i = 0; i < n->nkids; i++) free_qnode(n->kids[i]);
    free(n->kids);
    free(n);
}

void quote_reset(void) {
    for (int i = 0; i < g_quote_count; i++) {
        QuoteInfo* q = g_quotes[i];
        free_qnode(q->body);
        free(q->param_names);
        free(q->param_types);
        free(q->caps);
        free(q);
    }
    free(g_quotes);
    g_quotes = NULL;
    g_quote_count = g_quote_cap = 0;
}

/* ---- types ---- */

const char* quote_type_name(Type* t) {
    if (!t) return "";
    if (t->distinct_name) return t->distinct_name;
    switch (t->kind) {
        case TYPE_F32X4: return "f32x4";
        case TYPE_F64X2: return "f64x2";
        case TYPE_I32X4: return "i32x4";
        case TYPE_I64X2: return "i64x2";
        case TYPE_I16X8: return "i16x8";
        case TYPE_F32X8: return "f32x8";
        case TYPE_I32X8: return "i32x8";
        case TYPE_STRUCT: return t->struct_name ? t->struct_name : "struct";
        case TYPE_VOID: return "";
        case TYPE_UNKNOWN: return "";
        default: return type_to_string(t);
    }
}

int quote_is_tree_type(Type* t) {
    return t && t->kind == TYPE_PTR && t->distinct_name &&
           strcmp(t->distinct_name, "Tree") == 0;
}

/* ---- lowering ---- */

typedef struct {
    ASTNode* quote;
    SymbolTable* outer;
    QuoteErrorFn report;
    int errors;
    /* The quote's own names (parameters, then locals in scope), a stack
     * that each block pops back to on exit. */
    const char** locals;
    int nlocals;
    int caplocals;
    QCapture* caps;
    int ncaps;
    int capcaps;
} Lower;

static QNode* qnode(int kind, const char* type, const char* name, const char* op,
                    const char* lit, int line) {
    QNode* n = (QNode*)calloc(1, sizeof(QNode));
    if (!n) { fprintf(stderr, "aetherc: out of memory lowering a quote\n"); exit(1); }
    n->kind = kind;
    n->type = aether_intern(type ? type : "");
    n->name = aether_intern(name ? name : "");
    n->op = aether_intern(op ? op : "");
    n->lit = aether_intern(lit ? lit : "");
    n->line = line;
    return n;
}

static QNode* qadd(QNode* parent, QNode* kid) {
    if (!parent) { free_qnode(kid); return NULL; }
    if (!kid) return parent;
    if (parent->nkids == parent->capkids) {
        parent->capkids = parent->capkids ? parent->capkids * 2 : 4;
        parent->kids = (QNode**)aether_xrealloc(parent->kids, (size_t)parent->capkids * sizeof(QNode*));
    }
    parent->kids[parent->nkids++] = kid;
    return parent;
}

/* The first line a node or its children carry (some statements, `match`
 * among them, are made without one). */
static ASTNode* with_line(ASTNode* n) {
    if (!n || n->line > 0) return n;
    for (int i = 0; i < n->child_count; i++) {
        ASTNode* k = with_line(n->children[i]);
        if (k && k->line > 0) return k;
    }
    return NULL;
}

static void lerror(Lower* L, ASTNode* at, AetherErrorCode code, const char* msg, const char* hint) {
    L->errors++;
    if (at && at->line <= 0) at = with_line(at);
    if (L->report) L->report(msg, hint, at ? at->line : L->quote->line,
                             at ? at->column : L->quote->column, code);
}

/* A construct the tree has no node for. */
static QNode* reject(Lower* L, ASTNode* at, const char* what, const char* why) {
    char msg[320], hint[320];
    snprintf(msg, sizeof msg, "%s can't be quoted", what);
    snprintf(hint, sizeof hint,
             "a quote becomes a tree for a library to read; %s", why);
    lerror(L, at, AETHER_ERR_QUOTE_SUBSET, msg, hint);
    return NULL;
}

static int is_local(Lower* L, const char* name) {
    for (int i = L->nlocals - 1; i >= 0; i--)
        if (strcmp(L->locals[i], name) == 0) return 1;
    return 0;
}

static void push_local(Lower* L, const char* name) {
    if (L->nlocals == L->caplocals) {
        L->caplocals = L->caplocals ? L->caplocals * 2 : 16;
        L->locals = (const char**)aether_xrealloc(L->locals, (size_t)L->caplocals * sizeof(char*));
    }
    L->locals[L->nlocals++] = name;
}

/* Where the quote's scope resolves `name`, when it is not one of the
 * quote's own: 1 for a local of an enclosing function (a capture), 2 for a
 * program-level name, 0 for nothing. */
static Symbol* outer_symbol(Lower* L, const char* name, int* is_local_scope) {
    for (SymbolTable* t = L->outer; t; t = t->parent) {
        Symbol* s = lookup_symbol_local(t, name);
        if (s) {
            *is_local_scope = t->parent != NULL;
            return s;
        }
    }
    *is_local_scope = 0;
    return NULL;
}

static QNode* lower_expr(Lower* L, ASTNode* e);
static QNode* lower_stmt(Lower* L, ASTNode* s);

static const char* node_type_name(ASTNode* e) {
    return quote_type_name(e ? e->node_type : NULL);
}

static QNode* lower_identifier(Lower* L, ASTNode* e) {
    const char* name = e->value;
    if (is_local(L, name)) return qnode(QK_LOCAL, node_type_name(e), name, NULL, NULL, e->line);
    int local_scope = 0;
    Symbol* s = outer_symbol(L, name, &local_scope);
    /* A program-level constant whose value is a literal reads as that
     * literal: the tree has no node for a global, and a constant does not
     * change, so nothing is lost. */
    ASTNode* cdecl = (s && !local_scope) ? tc_program_const(name) : NULL;
    if (cdecl && cdecl->child_count > 0 && cdecl->children[0] &&
        cdecl->children[0]->type == AST_LITERAL) {
        ASTNode* lit = cdecl->children[0];
        Type* t = s->type ? s->type : lit->node_type;
        return qnode(QK_LIT, quote_type_name(t), NULL, NULL, lit->value, e->line);
    }
    char what[200];
    snprintf(what, sizeof what, "'%s' (not a local, a parameter or a literal constant)", name);
    return reject(L, e, what,
                  "it can read its own locals and parameters, and constants with a literal value");
}

static int is_actor_call(const char* name) {
    return name && (strcmp(name, "spawn") == 0 || strcmp(name, "send") == 0 ||
                    strcmp(name, "reply") == 0 || strcmp(name, "receive") == 0);
}

static QNode* lower_expr(Lower* L, ASTNode* e) {
    if (!e) return NULL;
    switch (e->type) {
        case AST_LITERAL:
            return qnode(QK_LIT, node_type_name(e), NULL, NULL, e->value, e->line);
        case AST_NULL_LITERAL:
            return qnode(QK_LIT, "ptr", NULL, NULL, "null", e->line);
        case AST_IDENTIFIER:
            if (!e->value) break;
            return lower_identifier(L, e);
        case AST_UNARY_EXPRESSION: {
            const char* op = e->value ? e->value : "";
            if (e->child_count < 1) break;
            if (strcmp(op, "-") != 0 && strcmp(op, "!") != 0 && strcmp(op, "~") != 0) {
                char what[64];
                snprintf(what, sizeof what, "the operator '%s' here", op);
                return reject(L, e, what, "it has unary '-', '!' and '~'; write a step as `x += 1`");
            }
            QNode* n = qnode(QK_UNARY, node_type_name(e), NULL, op, NULL, e->line);
            QNode* x = lower_expr(L, e->children[0]);
            if (!x) { free_qnode(n); return NULL; }
            return qadd(n, x);
        }
        case AST_BINARY_EXPRESSION: {
            if (e->child_count < 2) break;
            const char* op = e->value ? e->value : "";
            if (strcmp(op, "=") == 0) {
                return reject(L, e, "an assignment used as a value",
                              "an assignment is a statement in the tree");
            }
            QNode* n = qnode(QK_BINARY, node_type_name(e), NULL, op, NULL, e->line);
            QNode* l = lower_expr(L, e->children[0]);
            QNode* r = lower_expr(L, e->children[1]);
            if (!l || !r) { free_qnode(l); free_qnode(r); free_qnode(n); return NULL; }
            return qadd(qadd(n, l), r);
        }
        case AST_IF_EXPRESSION: {
            if (e->child_count < 3) break;
            QNode* n = qnode(QK_CHOOSE, node_type_name(e), NULL, NULL, NULL, e->line);
            int ok = 1;
            for (int i = 0; i < 3; i++) {
                QNode* k = lower_expr(L, e->children[i]);
                if (!k) ok = 0;
                n = qadd(n, k);
            }
            if (!ok) { free_qnode(n); return NULL; }
            return n;
        }
        case AST_FUNCTION_CALL: {
            const char* written = e->source_name ? e->source_name : e->value;
            if (!written) break;
            if (strcmp(written, "panic") == 0)
                return reject(L, e, "'panic'", "it has no node for unwinding");
            if (is_actor_call(written)) {
                char what[64];
                snprintf(what, sizeof what, "'%s'", written);
                return reject(L, e, what, "an actor operation has no meaning in a tree");
            }
            if (e->node_type && e->node_type->kind == TYPE_ACTOR_REF)
                return reject(L, e, "'spawn'", "an actor operation has no meaning in a tree");
            if (strcmp(written, "call") == 0)
                return reject(L, e, "a closure call", "it has no node for a closure");
            QNode* n = qnode(QK_CALL, node_type_name(e), written, NULL, NULL, e->line);
            int ok = 1;
            for (int i = 0; i < e->child_count; i++) {
                ASTNode* a = e->children[i];
                if (a && a->type == AST_NAMED_ARG && a->child_count > 0) a = a->children[0];
                QNode* k = lower_expr(L, a);
                if (!k) ok = 0;
                n = qadd(n, k);
            }
            if (!ok) { free_qnode(n); return NULL; }
            return n;
        }
        case AST_MEMBER_ACCESS: {
            if (e->child_count < 1 || !e->value) break;
            QNode* n = qnode(QK_FIELD, node_type_name(e), e->value, NULL, NULL, e->line);
            QNode* o = lower_expr(L, e->children[0]);
            if (!o) { free_qnode(n); return NULL; }
            return qadd(n, o);
        }
        case AST_ARRAY_ACCESS: {
            if (e->child_count < 2) break;
            QNode* n = qnode(QK_INDEX, node_type_name(e), NULL, NULL, NULL, e->line);
            QNode* o = lower_expr(L, e->children[0]);
            QNode* i = lower_expr(L, e->children[1]);
            if (!o || !i) { free_qnode(o); free_qnode(i); free_qnode(n); return NULL; }
            return qadd(qadd(n, o), i);
        }
        case AST_STRUCT_LITERAL: {
            /* MAKE: `type` the struct; the field each child sets is in
             * `lit`, comma-separated in child order (a child keeps its own
             * `name`: a LOCAL's or a CALL's). */
            Type* st = e->node_type;
            const char* tname = (st && st->kind == TYPE_STRUCT && st->struct_name)
                                    ? st->struct_name : (e->value ? e->value : "");
            char fields[1024];
            fields[0] = 0;
            QNode* n = qnode(QK_MAKE, tname, NULL, NULL, NULL, e->line);
            int ok = 1;
            for (int i = 0; i < e->child_count; i++) {
                ASTNode* f = e->children[i];
                if (!f || f->child_count < 1 || !f->value) { ok = 0; continue; }
                if (fields[0]) strncat(fields, ",", sizeof fields - strlen(fields) - 1);
                strncat(fields, f->value, sizeof fields - strlen(fields) - 1);
                QNode* k = lower_expr(L, f->children[0]);
                if (!k) ok = 0;
                n = qadd(n, k);
            }
            if (!ok) { free_qnode(n); return NULL; }
            n->lit = aether_intern(fields);
            return n;
        }
        case AST_STRING_INTERP:
            return reject(L, e, "string interpolation",
                          "version 1 has string literals only");
        case AST_ARRAY_LITERAL:
            return reject(L, e, "an array literal", "version 1 has no node for one");
        case AST_HEAP_NEW:
            return reject(L, e, "'new'", "version 1 has no node for an allocation");
        case AST_CLOSURE: {
            int trailing = e->value && strcmp(e->value, "trailing") == 0;
            return reject(L, e, trailing ? "a trailing block" : "a closure or callback",
                          "a tree of trees has no back end to go to");
        }
        case AST_QUOTE:
            return reject(L, e, "a quote inside a quote", "a tree of trees has no back end to go to");
        case AST_MATCH_STATEMENT:
            return reject(L, e, "'match'", "version 1 has no node for patterns");
        case AST_SEND_FIRE_FORGET:
        case AST_SEND_ASK:
        case AST_SEND_STATEMENT:
            return reject(L, e, "an actor send", "an actor operation has no meaning in a tree");
        case AST_SPAWN_ACTOR_STATEMENT:
            return reject(L, e, "'spawn'", "an actor operation has no meaning in a tree");
        default:
            break;
    }
    char what[96];
    snprintf(what, sizeof what, "this expression (%s)", ast_node_type_to_string(e->type));
    return reject(L, e, what, "version 1's tree has no node for it");
}

static QNode* lower_block(Lower* L, ASTNode* b) {
    QNode* n = qnode(QK_BLOCK, "", NULL, NULL, NULL, b ? b->line : L->quote->line);
    if (!b) return n;
    int mark = L->nlocals;
    int ok = 1;
    for (int i = 0; i < b->child_count; i++) {
        if (!b->children[i]) continue;
        QNode* k = lower_stmt(L, b->children[i]);
        if (!k) { ok = 0; continue; }
        n = qadd(n, k);
    }
    L->nlocals = mark;
    if (!ok) { free_qnode(n); return NULL; }
    return n;
}

static QNode* lower_stmt(Lower* L, ASTNode* s) {
    switch (s->type) {
        case AST_BLOCK:
            return lower_block(L, s);
        case AST_EXPRESSION_STATEMENT: {
            if (s->child_count < 1 || !s->children[0]) break;
            ASTNode* x = s->children[0];
            if (x->type == AST_CLOSURE || x->type == AST_QUOTE || x->type == AST_STRING_INTERP ||
                x->type == AST_MATCH_STATEMENT || x->type == AST_SEND_FIRE_FORGET ||
                x->type == AST_SEND_ASK || x->type == AST_SEND_STATEMENT) {
                return lower_expr(L, x);  /* reports it */
            }
            QNode* v = lower_expr(L, x);
            if (!v) return NULL;
            return qadd(qnode(QK_EXPR, "", NULL, NULL, NULL, s->line), v);
        }
        case AST_RETURN_STATEMENT: {
            QNode* n = qnode(QK_RETURN, "", NULL, NULL, NULL, s->line);
            if (s->child_count > 1)
                return free_qnode(n), reject(L, s, "returning several values",
                                             "a RETURN has one value");
            if (s->child_count == 1 && s->children[0]) {
                QNode* v = lower_expr(L, s->children[0]);
                if (!v) { free_qnode(n); return NULL; }
                n->type = v->type;
                qadd(n, v);
            }
            return n;
        }
        case AST_SEND_STATEMENT:
        case AST_SEND_FIRE_FORGET:
        case AST_SEND_ASK:
            return reject(L, s, "an actor send", "an actor operation has no meaning in a tree");
        case AST_SPAWN_ACTOR_STATEMENT:
            return reject(L, s, "'spawn'", "an actor operation has no meaning in a tree");
        default:
            if (s->type == AST_FUNCTION_CALL || s->type == AST_CLOSURE || s->type == AST_QUOTE ||
                s->type == AST_STRING_INTERP || s->type == AST_IF_EXPRESSION) {
                QNode* v = lower_expr(L, s);
                if (!v) return NULL;
                return qadd(qnode(QK_EXPR, "", NULL, NULL, NULL, s->line), v);
            }
            break;
    }
    char what[96];
    snprintf(what, sizeof what, "this statement (%s)", ast_node_type_to_string(s->type));
    return reject(L, s, what, "version 1's tree has no node for it");
}

/* ---- hash ---- */

static void fnv(uint64_t* h, const char* s) {
    for (; s && *s; s++) { *h ^= (unsigned char)*s; *h *= 1099511628211ULL; }
    *h ^= 0xff; *h *= 1099511628211ULL;   /* field separator */
}

static void fnv_int(uint64_t* h, int v) {
    char buf[24];
    snprintf(buf, sizeof buf, "%d", v);
    fnv(h, buf);
}

static void hash_node(uint64_t* h, QNode* n) {
    fnv_int(h, n->kind);
    fnv(h, n->type);
    fnv(h, n->name);
    fnv(h, n->op);
    fnv(h, n->lit);
    fnv_int(h, n->nkids);
    for (int i = 0; i < n->nkids; i++) hash_node(h, n->kids[i]);
}

/* ---- entry ---- */

int quote_lower(ASTNode* quote, SymbolTable* outer, const char* file, QuoteErrorFn report) {
    Lower L;
    memset(&L, 0, sizeof L);
    L.quote = quote;
    L.outer = outer;
    L.report = report;

    ASTNode* body = NULL;
    int nparams = 0;
    for (int i = 0; i < quote->child_count; i++) {
        ASTNode* c = quote->children[i];
        if (!c) continue;
        if (c->type == AST_CLOSURE_PARAM) {
            nparams++;
            if (c->value) push_local(&L, aether_intern(c->value));
        } else if (c->type == AST_BLOCK) {
            body = c;
        }
    }
    QNode* tree = lower_block(&L, body);
    if (L.errors) {
        free_qnode(tree);
        free(L.locals);
        free(L.caps);
        return L.errors;
    }

    QuoteInfo* q = (QuoteInfo*)calloc(1, sizeof(QuoteInfo));
    if (!q) { fprintf(stderr, "aetherc: out of memory lowering a quote\n"); exit(1); }
    q->node = quote;
    q->body = tree;
    q->nparams = nparams;
    q->param_names = (const char**)calloc((size_t)(nparams ? nparams : 1), sizeof(char*));
    q->param_types = (const char**)calloc((size_t)(nparams ? nparams : 1), sizeof(char*));
    int pi = 0;
    for (int i = 0; i < quote->child_count; i++) {
        ASTNode* c = quote->children[i];
        if (!c || c->type != AST_CLOSURE_PARAM) continue;
        q->param_names[pi] = aether_intern(c->value ? c->value : "");
        q->param_types[pi] = aether_intern(quote_type_name(c->node_type));
        pi++;
    }
    q->caps = L.caps;
    q->ncaps = L.ncaps;
    const char* f = file ? file : "";
    const char* slash = strrchr(f, '/');
    q->source = aether_internf("%s:%d", slash ? slash + 1 : f, quote->line);

    uint64_t h = 14695981039346656037ULL;
    fnv_int(&h, 1);   /* the format version */
    for (int i = 0; i < q->nparams; i++) { fnv(&h, q->param_names[i]); fnv(&h, q->param_types[i]); }
    for (int i = 0; i < q->ncaps; i++) { fnv(&h, q->caps[i].name); fnv(&h, q->caps[i].type); }
    hash_node(&h, tree);
    q->hash = h;
    free(L.locals);

    if (g_quote_count == g_quote_cap) {
        g_quote_cap = g_quote_cap ? g_quote_cap * 2 : 8;
        g_quotes = (QuoteInfo**)aether_xrealloc(g_quotes, (size_t)g_quote_cap * sizeof(QuoteInfo*));
    }
    g_quotes[g_quote_count] = q;
    char idx[24];
    snprintf(idx, sizeof idx, "%d", g_quote_count);
    g_quote_count++;
    free(quote->value);
    quote->value = strdup(idx);
    return 0;
}

/* ---- codegen ---- */

static void emit_c_string(FILE* out, const char* s) {
    fputc('"', out);
    for (const unsigned char* p = (const unsigned char*)(s ? s : ""); *p; p++) {
        if (*p == '"' || *p == '\\') { fputc('\\', out); fputc(*p, out); }
        else if (*p == '\n') fputs("\\n", out);
        else if (*p == '\t') fputs("\\t", out);
        else if (*p == '\r') fputs("\\r", out);
        else if (*p < 32 || *p == '?' || *p >= 127) fprintf(out, "\\%03o", *p);
        else fputc(*p, out);
    }
    fputc('"', out);
}

static int emit_qnode(FILE* out, QNode* n, int* counter) {
    int id = (*counter)++;
    fprintf(out, "    void* _n%d = aether_quote_node(%d, ", id, n->kind);
    emit_c_string(out, n->type);
    fputs(", ", out);
    emit_c_string(out, n->name);
    fputs(", ", out);
    emit_c_string(out, n->op);
    fputs(", ", out);
    emit_c_string(out, n->lit);
    fprintf(out, ", %d);\n", n->line);
    for (int i = 0; i < n->nkids; i++) {
        int k = emit_qnode(out, n->kids[i], counter);
        fprintf(out, "    aether_quote_add(_n%d, _n%d);\n", id, k);
    }
    return id;
}

void quote_emit_prototypes(FILE* out) {
    fputs("/* std.quote's constructors (docs/quote.md), called by the quote builders. */\n"
          "void* aether_quote_tree(const char* source, int64_t hash);\n"
          "void* aether_quote_node(int kind, const char* type, const char* name, const char* op, const char* lit, int line);\n"
          "void* aether_quote_add(void* parent, void* child);\n"
          "void aether_quote_set_body(void* tree, void* body);\n"
          "void aether_quote_param(void* tree, const char* name, const char* type);\n"
          "void aether_quote_capture(void* tree, const char* name, const char* type, const char* base, void* cell, void (*release)(void*));\n",
          out);
}

void quote_emit_builder(FILE* out, int index, const char* const* release_fns) {
    QuoteInfo* q = quote_at(index);
    if (!q) return;
    fprintf(out, "/* the tree of the quote at %s */\n", q->source);
    fprintf(out, "static void* _quote_build_%d(void** _cells) {\n", index);
    fprintf(out, "    (void)_cells;\n    void* _t = aether_quote_tree(");
    emit_c_string(out, q->source);
    fprintf(out, ", (int64_t)0x%016llxULL);\n", (unsigned long long)q->hash);
    for (int i = 0; i < q->nparams; i++) {
        fputs("    aether_quote_param(_t, ", out);
        emit_c_string(out, q->param_names[i]);
        fputs(", ", out);
        emit_c_string(out, q->param_types[i]);
        fputs(");\n", out);
    }
    for (int i = 0; i < q->ncaps; i++) {
        fputs("    aether_quote_capture(_t, ", out);
        emit_c_string(out, q->caps[i].name);
        fputs(", ", out);
        emit_c_string(out, q->caps[i].type);
        fputs(", ", out);
        emit_c_string(out, q->caps[i].base);
        fprintf(out, ", _aether_cell_retain(_cells[%d]), %s);\n", i,
                release_fns && release_fns[i] ? release_fns[i] : "_aether_cell_release");
    }
    int counter = 0;
    int body = emit_qnode(out, q->body, &counter);
    fprintf(out, "    aether_quote_set_body(_t, _n%d);\n    return _t;\n}\n", body);
}
