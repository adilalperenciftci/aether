- **An ask returns only once its reply slot is freed.** The replier let go
  of the slot just after it woke the asker, from its own thread, so the slot
  was sometimes freed a moment after the ask returned, and a program that
  counted its heap around asks saw it in the wrong window (a 104-byte
  difference failed a test on Windows). An answered or failed ask now waits
  those few instructions and frees the slot itself (#3245).
