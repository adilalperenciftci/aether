- **aetherc refuses an argument after its input and output.** It reads its
  options before them, and took anything after them in silence: `aetherc
  main.ae out.c --lib vendor` compiled without vendor, and the caller never
  knew. Such an argument is now an error that names it and gives the
  command as it should be written (`aetherc --lib vendor main.ae out.c`),
  and nothing is compiled. A mode that writes no output still takes the
  null device in that place (#3182).
