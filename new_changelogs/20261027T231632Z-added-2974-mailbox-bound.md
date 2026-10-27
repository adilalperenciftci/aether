- **An actor's mailbox can be bounded: `@mailbox(bound: N)`.** Mailboxes stay
  unbounded by default, so a send never blocks. With a bound the actor takes
  at most N messages it has not handled yet, wherever they wait (a core's
  queue, a sender's deferred sends, its overflow, its mailbox), counted
  exactly. Past it a send is refused at once, never blocked on: the new
  `try_send(ref, Msg { ... })` returns `"the mailbox is full"` (or `"the
  actor is dead"`, and `""` when it sent), an ask fails with `"the mailbox
  is full"`, and a plain `!` is dropped, counted by
  `actors.full_drops(ref)` and reported once on stderr. A `Down` always gets
  in. Both schedulers (#2974).
