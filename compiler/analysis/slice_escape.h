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
 * The check runs over the type-checked program, where the coercions into
 * slice slots are explicit. For each function, closure and `main` it finds
 * the locals that hold such a view (bound to one, or a local struct or array
 * one is stored in), then reports each place one leaves the frame, at the
 * value that leaves (E0800). A slice of a parameter's array, of a `make`
 * buffer or of a module-level array is no such view; a call's result is
 * taken to be none, so a function handing back the slice it was given is
 * not seen through.
 */

#ifndef AETHER_SLICE_ESCAPE_H
#define AETHER_SLICE_ESCAPE_H

#include "../ast.h"

/* Reports every slice of a function's own storage that leaves the function.
 * Returns the number of errors reported. */
int check_slice_escapes(ASTNode* program);

#endif /* AETHER_SLICE_ESCAPE_H */
