- **A death notice cut by a panic no longer leaks its entries.** The
  notice of an actor's death takes its watch entries off the actor's list
  and runs each one; a link's entry ends the linked actor, which can panic.
  A panic that left the notice skipped the free of the entries it had taken.
  They are now in the unwind journal from when the notice takes them until
  it frees them, as the link drain's queue already was, so the unwind frees
  them (#3421).
