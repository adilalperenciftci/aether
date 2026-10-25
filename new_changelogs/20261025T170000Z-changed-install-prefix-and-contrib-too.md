- **`make install` defaults to `~/.aether`, and `./install.sh --contrib-too`
  installs the contrib archives too.** `make install` and `make
  install-contrib` defaulted to `PREFIX=/usr/local`, unlike `install.sh` and
  `docs/install-layout.md`, so the documented `sudo make install` left a
  root-owned toolchain that `ae` and the compiler fall back to from every other
  checkout, and that only `sudo` could remove. Both targets now default to
  `~/.aether`. As root they refuse to run without an explicit `PREFIX`, since
  under `sudo` the default would be root's home; a system install is `sudo
  make install PREFIX=/usr/local`. `install.sh` takes `--contrib-too`, which
  builds the contrib archives for the modules whose dev libraries are present
  and installs them before the version is recorded, so `ae use` carries them.
  Flags and the prefix combine in any order, and an unknown flag is refused
  instead of becoming the install directory. `docs/bootstrap-from-source.md`
  now leads with `./install.sh --contrib-too`.
