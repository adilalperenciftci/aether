/* Missing-return check (#2684).
 *
 * A function whose result is not void must return a value on every path. A
 * path that reaches the end of the body instead falls off the end of a
 * non-void C function, which is undefined behaviour: the caller reads
 * whatever the return register held (a string printed "(null)" on MinGW).
 *
 * The check is over the type-checked program, so a `match` knows the type it
 * matches on. It reports each function, clause and closure whose end control
 * can reach, at the closing brace, naming the statement that lets control
 * through.
 */

#ifndef AETHER_MISSING_RETURN_H
#define AETHER_MISSING_RETURN_H

#include "../ast.h"

/* Reports every definition in `program` whose result is not void and whose
 * end control can reach. Returns the number of errors reported. */
int check_missing_returns(ASTNode* program);

/* Whether control can go on to the statement after `n`, by the rules at the
 * top of missing_return.c (#3017). The one answer every check that asks
 * "does this leave?" uses: a function's missing return, an `or { }`
 * handler that must yield a value or leave, a `match` arm, the isolation
 * check's branches and W1002's unreachable code. `program` resolves a
 * `const` in a condition; with NULL only literal conditions are decided. */
int stmt_can_complete(ASTNode* program, ASTNode* n);

/* A call that never returns: `exit(...)` (and `os.exit(...)`, the same
 * extern). The one list of them. */
int ast_call_never_returns(const ASTNode* n);

#endif /* AETHER_MISSING_RETURN_H */
