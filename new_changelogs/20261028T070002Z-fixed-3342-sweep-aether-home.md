- **`make test-ae` tests the tree, not an install.** With `AETHER_HOME` set
  to an install, as `install.sh` sets it, a test that ran the tree's
  `aetherc` without pinning the variable compiled against the installed std,
  and failed where the two differed (c_callback_table,
  heap_box_across_functions). The sweep's runners now drop an inherited
  `AETHER_HOME`; a test that wants an install names one itself (#3342).
