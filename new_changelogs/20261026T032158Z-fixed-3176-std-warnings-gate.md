- **std and contrib type-check without a warning, and `make check-warnings`
  keeps them so.** 36 warnings lived there, several an error result a test
  never checked (a read's error in std.zip's test, the matches of eight
  clapae error cases): each became the check its contract implies, the two
  calls naming their module twice (`fs.fs_is_symlink`) use the short name,
  and the dead code went. The gate, in Aether with a self-test, runs
  `ae check` over every .ae file under std and contrib, as many at once as
  the machine has cores, and fails a file that does not type-check at all,
  whose warnings the errors hide; `make ci` runs it (#3176).
