- **The nested ACTIVE-time test no longer fails on a slow macOS runner.**
  `accounts_active_time_once_when_nested` (#3409) gave two sleeps 90 ms of
  room under the account's budget, and on macOS CI they overran by more.
  It now checks the time charged against the wall time the nested call
  took, on the clock the runtime charges by, so a double charge still fails
  it on any host and a long sleep cannot; the cut past the budget is
  asserted with a margin an overrun only widens (#3422).
