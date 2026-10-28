- **`ae add` needs no git, and pins each package by the hash of its tree.**
  It takes the source archive the forge serves for the tag (or the default
  branch) over HTTPS: GitHub, GitLab, Bitbucket, Codeberg and self-hosted
  Gitea, Forgejo or GitLab, or a mirror named by `AE_RELEASE_BASE_URL`, over
  HTTP or `file://`. The fetcher is an Aether program (`tools/ae-fetch`,
  std.http, std.tar, std.zlib), shipped as source and built by the
  installed toolchain on first use. `aether.toml` gains
  `[dependency-hashes]`: a later `ae add` must fetch the same tree (a moved
  tag is refused), `ae build`, `ae run` and `ae lib-path` stop on an
  installed package that is not the pinned tree, and `--update` moves a pin
  to another version or tree. Without `@version`, `ae add` installs the
  version `aether.toml` names, so a fresh checkout's dependencies install at
  their pinned versions (#1362).
  Migration: `--source` now means the source archive rather than a git
  clone. Asking for another version of a dependency `aether.toml` already
  lists needs `--update` (it used to print "Already in dependencies." and
  change nothing). A package cached by git before this keeps working and is
  not checked; `ae add <package> --update` refetches it and pins its hash.
  A repository's symlinks are installed as symlinks and their targets are
  part of the hash; one whose target leaves the package is refused, and on
  Windows a symlink needs Developer Mode, as git needs it (#3306).
