- **An execution account made under a parent that is not live is refused.**
  `aether_exec_account_new` (and `host.account_new`) dropped a parent it
  did not hold, one the host had freed or one another runtime copy made
  without sharing the accounts, and made the account with no parent at
  all: unbounded by the limits meant to narrow it. It now returns NULL
  for such a parent, so a child is never wider than its parent (#3412).
