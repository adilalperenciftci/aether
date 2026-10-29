- **Execution accounts: a budget that belongs to a script, not to a call
  or a thread.** A host that runs many scripts on one thread, each
  yielding and resumed later, gives each an account
  (`aether_exec_account_new`, `aether_exec_use`; `host.account_new` and
  friends in std.host): every cap-aware allocation made while it is in use
  is charged to it and its parent chain and refused past its allowance
  (`AETHER_MEMORY_CAP`), a block credits the account that allocated it
  wherever it is freed, and its deadline counts wall time from its making
  (`AETHER_DEADLINE_ELAPSED`) or only the time spent in its calls
  (`AETHER_DEADLINE_ACTIVE`). A parent only narrows; an account is in use
  on one thread at a time (`aether_exec_use` returns -1 for one in use on
  another); an execution puts back the account it began with; an actor
  stepped inside code that has one in use is not charged to it. Libraries
  with a runtime of their own share the accounts of the first loaded copy
  (one lock, one table), and a copy of another layout refuses them, saying
  so once. While no account exists an allocation still tests one word
  (#2954).
