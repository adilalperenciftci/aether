- **A chain of linked actors ends in the same stack depth however long it
  is (#3394).** Where a death is finalized as soon as it is seen (the
  cooperative scheduler, and the threaded one once it is stopped), the end
  a link passed on ran inside the previous actor's finalize, so a chain of
  linked actors ended one inside the other, a few frames per actor: killing
  the head of 8000 linked actors overflowed a 256 KiB stack (wasm, an
  ESP32 task or a host's thread have no more). An end a link passes on
  while the thread is still making another now waits in the thread's queue
  and is made after it; 100000 linked actors end on a 64 KiB stack.
