- **The undelivered-message leak test no longer fails now and then on
  Windows.** `tests/regression/test_undelivered_message_releases_fields.ae`
  failed now and then with "dropped messages grew the heap ... in every run"
  (18 runs in 100 on main, before #3346; up to one in a hundred after). A
  heap diff of a failing run showed what grew: one actor's block (1,799
  bytes) per window, kept by the scheduler for the next spawn of its size
  (#2517). A released actor's block is kept once it is reclaimed and no
  message is on its way to it, and a spawn before that takes a fresh one,
  so the number of blocks kept followed the cores' timing, not the program.
  Each round of the test now ends settled (its released actors' messages
  dropped, their blocks reclaimed), so the next round reuses the blocks the
  first one made; its check is as exact as it was. The scheduler's comment,
  which said the blocks kept never exceed what was once live at the same
  time, now counts the released actors still being reclaimed or awaited by
  a message too (#3385).
