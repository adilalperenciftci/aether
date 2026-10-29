- **Freeing an execution account that is in use no longer leaves the
  runtime writing into freed memory.** `aether_exec_account_free` (and
  `host.account_free`) freed the account while the thread's account in use,
  the account's own thread claim and every execution that began under it
  still named it: `host.account_in_use()` went on returning it, the next
  cap-aware allocation charged the freed block, and the execution's return
  charged its time to it and put it back in use. Now freeing an account in
  use on the calling thread ends its use; one in use on another thread is
  charged nothing more there, and that thread lets go of it at its next
  allocation, call or `aether_exec_use`; an execution that began under it
  holds it until it returns and then puts no account back. The block goes
  when the last of them lets go (#3407).
