/* The C side of the extern-width self-test (tests/extern_widths/check.ae,
 * #3097). Never built: the check only reads it. widths.ae binds these. */

#include <stddef.h>
#include <stdint.h>

/* Agree with their externs. */
int64_t ew_ok_long(int64_t v) { return v; }
size_t ew_ok_size(size_t n) { return n; }
int ew_ok_bool(int flag) { return flag; }
double ew_ok_double(double x) { return x; }
const char* ew_ok_string(const char* s) { return s; }
void* ew_ok_ptr(void* p) { return p; }
int ew_ok_ignored_result(int v) { return v; }
int ew_ok_variadic(const char* fmt, ...) { (void)fmt; return 0; }
int ew_ok_multiline(void* a,
                    int64_t b,
                    const char* c) {
    (void)a; (void)b; (void)c;
    return 0;
}

/* A macro call at file scope ends in no `;`: the next definition's type
 * starts after it. */
#define EW_DEFINE(name) int name(void) { return 0; }
EW_DEFINE(ew_ok_from_macro)
int ew_ok_after_macro(int v) { return v; }

/* Comments and literals hold no definitions:
 * long ew_bad_in_comment(long v) { return v; } */
static const char* ew_text = "long ew_bad_in_string(long v) { return v; }";

/* A static function has no symbol an extern could bind. */
static long ew_static(long v) { return v; }

/* Disagree with their externs, one mismatch each. */
long ew_bad_long_result(void) { return 0; }
void ew_bad_long_param(long v) { (void)v; }
void ew_bad_int_to_int64(int64_t v) { (void)v; }
void ew_bad_int_to_size(size_t n) { (void)n; }
size_t ew_bad_long_to_size(size_t n) { return n; }
float ew_bad_float(float x) { return x; }
void* ew_bad_pointer_as_int(void) { return 0; }
int ew_bad_arity(int a, int b) { return a + b; }
void ew_bad_void_result(int v) { (void)v; }
unsigned long ew_bad_unsigned_long(void) { return 0; }
int ew_bad_aliased(int64_t v) { return (int)v; }

/* Two definitions under preprocessor branches: both are checked, and the
 * second disagrees. */
#ifdef EW_FIRST
int ew_bad_second_branch(int v) { return v; }
#else
int ew_bad_second_branch(long v) { return (int)v; }
#endif

/* @c_import: the C compiler checks it against this prototype. */
long ew_skipped_c_import(long v) { return v; }

void ew_use(void) { (void)ew_text; (void)ew_static; }
