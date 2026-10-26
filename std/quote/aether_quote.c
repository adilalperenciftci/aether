/* Copyright (c) 2026 Aether Developers. */
/* std.quote runtime: the tree a `quote` trailing block builds (docs/quote.md).
 * The compiler emits the calls to the constructors; std/quote/module.ae reads
 * the tree back through the accessors. */
#include "aether_quote.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct AeQuoteNode {
    int kind;
    const char* type;
    const char* name;
    const char* op;
    const char* lit;
    int line;
    struct AeQuoteNode** kids;
    int nkids;
    int capkids;
} AeQuoteNode;

typedef struct {
    const char* name;
    const char* type;
} AeQuoteParam;

typedef struct {
    const char* name;
    const char* type;
    const char* base;
    void* cell;
    void (*release)(const void*);
} AeQuoteCapture;

typedef struct AeQuoteTree_ {
    int version;
    const char* source;
    int64_t hash;
    AeQuoteNode* body;
    AeQuoteParam* params;
    int nparams;
    AeQuoteCapture** caps;
    int ncaps;
    /* Version 2: a helper (a @quotable function) has a name and a return
     * type; a quote has the helpers its body reaches, callees first. */
    const char* name;
    const char* ret;
    struct AeQuoteTree_** helpers;
    int nhelpers;
} AeQuoteTree;

/* Out of memory while building a tree: nothing sensible can follow, and this
 * file is linked into the compiler too, which has no aether_panic. */
static void quote_oom(void) {
    fprintf(stderr, "std.quote: out of memory building a quote's tree\n");  /* silent-ok: last line before abort */
    abort();
}

static void* quote_alloc(size_t n) {
    void* p = calloc(1, n);
    if (!p) quote_oom();
    return p;
}

static void* quote_grow(void* p, size_t n) {
    void* q = realloc(p, n);
    if (!q) quote_oom();
    return q;
}

static const char* nz(const char* s) { return s ? s : ""; }

void* aether_quote_tree(const char* source, int64_t hash) {
    AeQuoteTree* t = (AeQuoteTree*)quote_alloc(sizeof(AeQuoteTree));
    t->version = AETHER_QUOTE_VERSION;
    t->source = nz(source);
    t->hash = hash;
    return t;
}

void* aether_quote_node(int kind, const char* type, const char* name,
                        const char* op, const char* lit, int line) {
    AeQuoteNode* n = (AeQuoteNode*)quote_alloc(sizeof(AeQuoteNode));
    n->kind = kind;
    n->type = nz(type);
    n->name = nz(name);
    n->op = nz(op);
    n->lit = nz(lit);
    n->line = line;
    return n;
}

void* aether_quote_add(void* parent, void* child) {
    AeQuoteNode* p = (AeQuoteNode*)parent;
    if (!p) return NULL;
    if (p->nkids == p->capkids) {
        p->capkids = p->capkids ? p->capkids * 2 : 4;
        p->kids = (AeQuoteNode**)quote_grow(p->kids, (size_t)p->capkids * sizeof(AeQuoteNode*));
    }
    p->kids[p->nkids++] = (AeQuoteNode*)child;
    return p;
}

void aether_quote_set_body(void* tree, void* body) {
    if (tree) ((AeQuoteTree*)tree)->body = (AeQuoteNode*)body;
}

void aether_quote_param(void* tree, const char* name, const char* type) {
    AeQuoteTree* t = (AeQuoteTree*)tree;
    if (!t) return;
    t->params = (AeQuoteParam*)quote_grow(t->params, (size_t)(t->nparams + 1) * sizeof(AeQuoteParam));
    t->params[t->nparams].name = nz(name);
    t->params[t->nparams].type = nz(type);
    t->nparams++;
}

void aether_quote_capture(void* tree, const char* name, const char* type,
                          const char* base, void* cell, void (*release)(const void*)) {
    AeQuoteTree* t = (AeQuoteTree*)tree;
    if (!t) return;
    AeQuoteCapture* c = (AeQuoteCapture*)quote_alloc(sizeof(AeQuoteCapture));
    c->name = nz(name);
    c->type = nz(type);
    c->base = nz(base);
    c->cell = cell;
    c->release = release;
    t->caps = (AeQuoteCapture**)quote_grow(t->caps, (size_t)(t->ncaps + 1) * sizeof(AeQuoteCapture*));
    t->caps[t->ncaps++] = c;
}

void* aether_quote_helper(const char* name, const char* ret) {
    AeQuoteTree* t = (AeQuoteTree*)aether_quote_tree("", 0);
    t->name = nz(name);
    t->ret = nz(ret);
    return t;
}
void aether_quote_add_helper(void* tree, void* helper) {
    AeQuoteTree* t = (AeQuoteTree*)tree;
    if (!t || !helper) return;
    t->helpers = (struct AeQuoteTree_**)quote_grow(t->helpers, (size_t)(t->nhelpers + 1) * sizeof(*t->helpers));
    t->helpers[t->nhelpers++] = (struct AeQuoteTree_*)helper;
}
int aether_quote_helper_count(void* tree) { return tree ? ((AeQuoteTree*)tree)->nhelpers : 0; }
void* aether_quote_helper_at(void* tree, int i) {
    AeQuoteTree* t = (AeQuoteTree*)tree;
    return (t && i >= 0 && i < t->nhelpers) ? t->helpers[i] : NULL;
}
const char* aether_quote_function_name(void* tree) {
    AeQuoteTree* t = (AeQuoteTree*)tree;
    return (t && t->name) ? t->name : "";
}
const char* aether_quote_return_type(void* tree) {
    AeQuoteTree* t = (AeQuoteTree*)tree;
    return (t && t->ret) ? t->ret : "";
}
int aether_quote_version(void* tree) { return tree ? ((AeQuoteTree*)tree)->version : 0; }
void* aether_quote_body(void* tree) { return tree ? ((AeQuoteTree*)tree)->body : NULL; }
const char* aether_quote_source(void* tree) { return tree ? ((AeQuoteTree*)tree)->source : ""; }
int64_t aether_quote_hash(void* tree) { return tree ? ((AeQuoteTree*)tree)->hash : 0; }
int aether_quote_param_count(void* tree) { return tree ? ((AeQuoteTree*)tree)->nparams : 0; }

const char* aether_quote_param_name(void* tree, int i) {
    AeQuoteTree* t = (AeQuoteTree*)tree;
    return (t && i >= 0 && i < t->nparams) ? t->params[i].name : "";
}

const char* aether_quote_param_type(void* tree, int i) {
    AeQuoteTree* t = (AeQuoteTree*)tree;
    return (t && i >= 0 && i < t->nparams) ? t->params[i].type : "";
}

int aether_quote_capture_count(void* tree) { return tree ? ((AeQuoteTree*)tree)->ncaps : 0; }

void* aether_quote_capture_at(void* tree, int i) {
    AeQuoteTree* t = (AeQuoteTree*)tree;
    return (t && i >= 0 && i < t->ncaps) ? t->caps[i] : NULL;
}

void* aether_quote_capture_named(void* tree, const char* name) {
    AeQuoteTree* t = (AeQuoteTree*)tree;
    if (!t || !name) return NULL;
    for (int i = 0; i < t->ncaps; i++) {
        if (strcmp(t->caps[i]->name, name) == 0) return t->caps[i];
    }
    return NULL;
}

int aether_quote_kind(void* node) { return node ? ((AeQuoteNode*)node)->kind : 0; }
const char* aether_quote_type(void* node) { return node ? ((AeQuoteNode*)node)->type : ""; }
const char* aether_quote_name(void* node) { return node ? ((AeQuoteNode*)node)->name : ""; }
const char* aether_quote_op(void* node) { return node ? ((AeQuoteNode*)node)->op : ""; }
const char* aether_quote_lit(void* node) { return node ? ((AeQuoteNode*)node)->lit : ""; }
int aether_quote_line(void* node) { return node ? ((AeQuoteNode*)node)->line : 0; }
int aether_quote_child_count(void* node) { return node ? ((AeQuoteNode*)node)->nkids : 0; }

void* aether_quote_child(void* node, int i) {
    AeQuoteNode* n = (AeQuoteNode*)node;
    return (n && i >= 0 && i < n->nkids) ? n->kids[i] : NULL;
}

const char* aether_quote_capture_name(void* cap) { return cap ? ((AeQuoteCapture*)cap)->name : ""; }
const char* aether_quote_capture_type(void* cap) { return cap ? ((AeQuoteCapture*)cap)->type : ""; }
void* aether_quote_capture_cell(void* cap) { return cap ? ((AeQuoteCapture*)cap)->cell : NULL; }

const char* aether_quote_capture_base(void* cap) { return cap ? ((AeQuoteCapture*)cap)->base : ""; }

/* The typed getters (std/quote/module.ae) check the capture's base type
 * against what they read, and panic naming both on a mismatch, before
 * reading the cell through these. */
double aether_quote_read_float(void* cell) { return *(double*)cell; }
float aether_quote_read_f32(void* cell) { return *(float*)cell; }
int aether_quote_read_int(void* cell) { return *(int*)cell; }
int64_t aether_quote_read_long(void* cell) { return *(int64_t*)cell; }
int aether_quote_read_bool(void* cell) { return *(_Bool*)cell ? 1 : 0; }
const char* aether_quote_read_string(void* cell) { return *(const char**)cell; }
void* aether_quote_read_ptr(void* cell) { return *(void**)cell; }

static void quote_free_node(AeQuoteNode* n) {
    if (!n) return;
    for (int i = 0; i < n->nkids; i++) quote_free_node(n->kids[i]);
    free(n->kids);
    free(n);
}

void aether_quote_free(void* tree) {
    AeQuoteTree* t = (AeQuoteTree*)tree;
    if (!t) return;
    quote_free_node(t->body);
    free(t->params);
    for (int i = 0; i < t->ncaps; i++) {
        if (t->caps[i]->release) t->caps[i]->release(t->caps[i]->cell);
        free(t->caps[i]);
    }
    free(t->caps);
    for (int i = 0; i < t->nhelpers; i++) aether_quote_free(t->helpers[i]);
    free(t->helpers);
    free(t);
}
