- **An ask's reply slot rides in its own message only.** The ask handed its
  slot to the send through a thread-local. The send can step its target
  inline, and every message with fields that handler sent read the slot
  too: its receiver replied into it or failed it, the slot was let go
  twice, and the asker read freed memory (a crash on every run of a handler
  that asks an idle actor of its own core which sends before it replies,
  #3395). Inside a library call, an ask whose message copy found no memory
  unwound from inside the send and left the slot set for every later send
  on the thread, and its core marked as asking, so no actor moved onto it
  again (#3387). The ask now builds its own message; with no memory for it
  the ask fails at once with "out of memory", nothing sent and nothing left
  set, and the call ends with `AETHER_OUT_OF_MEMORY`.
