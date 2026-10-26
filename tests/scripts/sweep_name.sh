# The name a `make test-ae` test goes by, sourced by the sweep's runners
# (run_ae_test.sh, run_ae_sh_dir.sh), by the scripts that find what the
# sweep built under that name (opt_diff_one.sh, strict_c11_sweep_one.sh),
# and by sweep_unreported.sh, which has to name every test the sweep listed
# the same way the runner that reports it does (#3111). A .ae or .sh path
# relative to the repository root:
#
#   tests/integration/foo/test_foo.sh -> integration_foo_test_foo
#   std/fs/test_fs.ae                 -> std_fs_test_fs
#
# One sed expression, so a list of paths is named in a single run of sed.
SWEEP_NAME_SED='s|tests/||;s|/|_|g;s|\.ae$||;s|\.sh$||'
