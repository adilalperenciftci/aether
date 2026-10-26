/* Shared C, as std's is (check.ae --root). ew_twice is defined in
 * contrib/ew_two too: one finding. A static function and a second
 * definition in this directory (another platform's branch) are not. */
int ew_twice(int x) { return x; }
static int ew_private(int x) { return x; }
int ew_branch(int x) { return x; }
