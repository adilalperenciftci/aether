/* A slice of a function's own storage must not outlive the function.
 *
 * A `T[]` slice does not own its elements: it is valid for as long as the
 * storage it views (language-reference.md, Slices). An array literal in a
 * slice slot, and a function's own fixed-size array, live in the function's
 * frame, which ends when the function returns. A slice of either that leaves
 * the function views memory the next call reuses: one returned, stored in a
 * module-level `var`, stored in a field of something the function did not
 * make for itself (a struct behind a pointer, a parameter's pointee, a
 * global), or carried out by a closure that captured it.
 *
 * A fixed-size array parameter is the function's own copy of the caller's
 * array, so it is storage of the frame as a local array is.
 *
 * The check runs over the type-checked program, where the coercions into
 * slice slots are explicit. For each function, closure and `main` it walks
 * the body in the order it runs, keeping what holds such a view at each
 * point: a local bound to one, or a field of a local value one is stored in.
 * Binding a local or a field again replaces what it held, so a name given
 * storage that outlives the frame before it leaves holds no view any more;
 * a statement that calls a local closure (bound once, only ever called by
 * name) re-binds what the closure's body re-binds on every path to a
 * call's result.
 * Where control joins (after the branches of an `if`, a `match` or a
 * `switch`, around a loop, after a `try`) what holds a view on any path
 * holds one. Each place a view leaves the frame is reported at the value
 * that leaves (E0800). A slice of a slice parameter, of a `make` buffer or
 * of a module-level array is no such view; a call's result is taken to be
 * none, so a function handing back the slice it was given is not seen
 * through.
 */

#ifndef AETHER_SLICE_ESCAPE_H
#define AETHER_SLICE_ESCAPE_H

#include "../ast.h"

/* Reports every slice of a function's own storage that leaves the function.
 * Returns the number of errors reported. */
int check_slice_escapes(ASTNode* program);

#endif /* AETHER_SLICE_ESCAPE_H */
