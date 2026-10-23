- **A cooperative libaether and its programs agree on ActorBase on
  Windows.** With `-DAETHER_NO_THREADING` (a cooperative libaether, `make
  ci-coop`'s setup) aether_thread.h fell to bare-metal `int` thread types
  on Windows, while a program built against it by `ae` has the Win32-shaped
  ones. The four ActorBase fields after `thread` sat 4 bytes apart in the
  two and the rest agreed only through padding, ActorReplySlot was 40 bytes
  in one and 80 in the other, and Scheduler differed from `thread` on. The
  Windows types are now one definition for both builds, and a test compares
  those structs' layouts built both ways (#3120).
