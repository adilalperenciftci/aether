- **Execution accounts no longer cost threads that use none, and freeing
  one is linear.** While any account existed, every cap-aware allocation
  and free on every thread (actor cores, HTTP workers) took the accounts'
  lock, a test-and-set loop with no pause, and probed their table; and
  freeing an account rescanned the table from the start after each of its
  blocks, under that lock (40,000 blocks took 1.1 s, with every allocation
  in the process waiting). Now a thread with no account in use asks a
  filter of the addresses the accounts recorded and takes no lock unless
  its block may be one of them; freeing an account is one pass over the
  table (40,000 blocks: 0.5 ms); and a waiter on the lock pauses, then
  yields, instead of spinning hot. emit-lib.md gives the cost while an
  account exists (#3410).
