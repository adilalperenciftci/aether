/* Use after free, double free and dead views (#1300).
 *
 * A call frees what its argument points at when the parameter is C's `free`,
 * `heap.free`'s, or declared `@frees`; it may move the storage the argument
 * holds when the parameter is declared `@moves` (a buffer that grows). Each
 * function body is walked in order, keeping for every local:
 *
 *   - whether it is freed on every path that reaches this point;
 *   - for a view (a slice `buf[a..b]`, a cast `p as T[]` or `p as *T`, the
 *     result of a call whose `@into` parameter it was given), the local whose
 *     storage it views, and whether that storage is gone (freed or moved) on
 *     every path.
 *
 * A read of a local freed on every path, a second free of one, and a read of
 * a view whose storage is gone on every path are errors (E0903). Where one
 * path frees and another does not, nothing is said: only a fault that
 * happens whichever way the program goes is reported. A loop is also walked
 * from the state its body leaves for the next turn, so a free that the next
 * turn repeats (the variable not bound afresh in between) is reported. A
 * local whose address is taken, or that a closure or a `defer` names, is not
 * followed from there.
 *
 * An Aether function that declares a parameter `@frees` frees it on every
 * path to its end (or finds it null), without binding it to something else
 * first; one that declares `@moves` passes it on some path to a parameter
 * that may move or free it (E0904).
 */

#ifndef AETHER_FREE_CHECK_H
#define AETHER_FREE_CHECK_H

#include "../ast.h"

/* Checks every function body of the type-checked `program`. Returns the
 * number of errors reported. */
int check_frees(ASTNode* program);

#endif /* AETHER_FREE_CHECK_H */
