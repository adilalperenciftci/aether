- **E0902 follows a closure that reads a borrowed `ptr` stored after it
  was written.** `pb = (&b) as *Box`, `g = || { kept = pb.item }`, then
  `b.item = p` and `call(g)` was accepted, though `g` stores `p` when it
  runs; the same in a straight line was refused. A closure is checked where
  it is written, and it reads its captures as they stood there, except
  through an address of a local or a local it shares with the function
  (one a closure assigns): those it reads as they are when it runs. Such a
  closure is now checked again where it is called or passed (directly, by
  another name, to a function, in a loop), and holds what it reads there
  wherever it goes, returned or stored. A closure that copies what it
  captures, or runs before the store, stays accepted (#3058).
