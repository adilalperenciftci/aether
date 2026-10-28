# Package fetching

`ae add <host>/<owner>/<repo>[@version]` installs a package's source under
`~/.aether/packages/<host>/<owner>/<repo>` and records it in the project's
`aether.toml`. It needs no git, no shell and no tools beyond the Aether
toolchain (#1362). This page is the design: what a package is, where its
bytes come from, and what is checked.

## A package is its tree's hash

A package is identified by the hash of what is in it, not by where it came
from. A URL is one place to get bytes that match the hash. This is Zig's
model (`build.zig.zon`), and it is what makes an install reproducible: a
second machine, or the same one after its cache was emptied, must end up with
the same tree, whichever server it got it from.

`ae add` writes two sections:

```toml
[dependencies]
"github.com/acme/widget" = "v1.2.0"

[dependency-hashes]
"github.com/acme/widget" = "sha256-9f2c...e41a"
```

The hash is `sha256-` and the hex SHA-256 of a listing of the tree: for each
regular file and symlink under the package root, in byte order of its path
(relative, `/`-separated), the path, a NUL byte, then the hex SHA-256 of a
file's bytes, or `symlink ` and a link's target as the archive spells it,
and a newline. A symlink is listed, never followed, so a link and the file
it names are two entries. Directories and file modes are not part of it, so
a package hashes the same on every OS, and the listing can be recomputed
with standard tools:

```sh
find . \( -type f -o -type l \) | sed 's|^\./||' | LC_ALL=C sort |
  while IFS= read -r f; do
    if [ -L "$f" ]; then printf '%s\0symlink %s\n' "$f" "$(readlink "$f")"
    else printf '%s\0%s\n' "$f" "$(sha256sum "$f" | cut -d' ' -f1)"; fi
  done | sha256sum
```

## Where the bytes come from

Every forge serves an archive of a tag, and of its default branch, over
HTTPS. `ae add` asks for that archive, never for a clone:

| Host | Archive of a tag | Tag list |
| --- | --- | --- |
| `github.com` | `codeload.github.com/<owner>/<repo>/tar.gz/refs/tags/<tag>` | `api.github.com/repos/<owner>/<repo>/tags` |
| `gitlab.com`, `gitlab.*` | `<host>/<path>/-/archive/<tag>/<repo>-<tag>.tar.gz` | `<host>/api/v4/projects/<path>/repository/tags` |
| `bitbucket.org` | `bitbucket.org/<owner>/<repo>/get/<tag>.tar.gz` | `api.bitbucket.org/2.0/repositories/<owner>/<repo>/refs/tags` |
| `codeberg.org`, Gitea, Forgejo | `<host>/<path>/archive/<tag>.tar.gz` | `<host>/api/v1/repos/<path>/tags` |
| any other host | Gitea's layout, then GitLab's | Gitea's |

The default branch is the ref `HEAD` in each layout. A version is tried as
`v<version>` and then as written, so `@1.2.0` and `@v1.2.0` both find a tag
named either way. When no archive answers, `ae add` prints why for each URL
and lists the tags the forge has.

`AE_RELEASE_BASE_URL` replaces the forge with a mirror laid out as Gitea's
archive endpoint is:

```
<mirror>/<host>/<owner>/<repo>/archive/<tag>.tar.gz
<mirror>/<host>/<owner>/<repo>/archive/HEAD.tar.gz
<mirror>/<host>/<owner>/<repo>/tags.json        # [{"name": "v1.2.0"}, ...]
```

A mirror can be an HTTP server or a directory (`file:///srv/mirror`,
`file://C:/mirror`), for a machine with no network. The hash makes a mirror
safe to use: it cannot hand over another tree than the one pinned.

A package that publishes a release artifact for the host (a binary package,
or `<repo>-<tag>-<os>-<arch>.tar.gz`) is installed from it instead when a
version is given, verified by its `.sha256` (getting-started.md, "Add a
package"). `--source` skips that and takes the source archive.

## The fetcher

The fetching is done by `ae-fetch`, an Aether program (`tools/ae-fetch`):
std.http fetches (OpenSSL, or the pure-Aether TLS where there is none),
std.zlib inflates, std.tar unpacks and std.cryptography hashes. std.tar reads
the pax and GNU archives forges produce, and refuses an entry whose path
leaves the destination. A repository's symlinks are installed as symlinks
(#3306), and std.tar refuses one whose target leaves the package and any
entry under a symlinked directory. Windows creates a symlink only with
Developer Mode on (Settings, System, For developers) or as an administrator.
Elsewhere, a package that holds a symlink fails to install with that
reason, and leaves nothing.

Every install ships the fetcher's source (`share/aether/tools/ae-fetch`), not
a binary per platform. The first `ae add` builds it with the installed
toolchain into `~/.aether/tools/ae-fetch-<key>`, keyed as `ae run`'s build
cache is (the source, what it imports, the compiler, the runtime), so it is
rebuilt when the toolchain changes and never older than the std it uses. The
build takes a few seconds, once. `AE_FETCH` names a fetcher to use instead.

The archive is unpacked beside the package directory and moved into place
whole, so a failed or interrupted fetch leaves nothing resolvable. Beside
each package it fetched, `ae add` keeps a record,
`~/.aether/packages/<host>/<owner>/<repo>.fetched`, with the URL, the hash and
the version.

## What is checked

* **On add.** When `aether.toml` already pins a hash, the fetched tree must
  have it. A tag that was moved, or a default branch that moved on, is
  refused, and nothing is installed or written:

  ```
  Error: github.com/acme/widget@v1.2.0 is not the tree aether.toml pins:
           pinned   sha256-9f2c...e41a
           fetched  sha256-03b7...77c0
  ```

* **On build.** `ae build`, `ae run` and `ae lib-path` compare each
  dependency's record with the hash its declaring manifest pins, and stop on
  a difference rather than build against another tree. A package with no
  record (installed from a release artifact, or by git before #1362) is not
  checked.

* **One version per package.** The cache holds one tree of a package for
  every project on the machine. A project that asks for another version than
  the installed one is told so, and is not served the installed tree.

## Moving a pin

The hash only changes when asked:

```sh
ae add github.com/acme/widget@v1.3.0 --update   # another version
ae add github.com/acme/widget --update          # what the pinned version (or the default branch) holds now
```

Without a version, `ae add <package>` installs the version `aether.toml`
names, so a fresh checkout's dependencies are installed with
`ae add <package>` for each, at the versions and trees the project pinned.
