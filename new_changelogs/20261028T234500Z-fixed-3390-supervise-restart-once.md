- **A supervisor restarts each child once per restart, in start order
  (#3390).** Under `one_for_all` and `rest_for_one`, a death while a
  restart still waited for a killed sibling's `Down` queued every child of
  its restart again, the waiting ones included. The duplicate came round
  after the child was already restarted and gave the supervisor up ("child
  c cannot be restarted"), the children restarted out of start order (c
  before a), and the 32-slot ring could overflow and overwrite entries. The
  queue is now one pending mark per child: a child is marked at most once,
  whichever deaths ask for it, the first marked in start order is restarted
  next, and nothing can overflow.
