/* The C functions the probe's modules bind: tally binds tally_count
 * through @extern, tally_c binds tally_total as a bare extern. */
int tally_count(int x) { return x * 2; }
int tally_total(int x) { return x + 100; }
