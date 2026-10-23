# Proposal: one capability vocabulary across Aether, aeb and aeo

For Nic. A plan rather than a report; the Selaenium shared library is the
worked case, and the open discussions in #2954 and #2955 are neighbours, not
prerequisites.

## In three sentences

Aether has fine-grained capability machinery (`std.sandbox`'s nine grant
categories, pattern matching, nested narrowing) but the places a library's
needs are declared, derived and shipped all speak a coarser and different
language: `--with=fs,net,os`, `--emit=effects`' four booleans, aeb's own
grant matcher, `aether_describe().capabilities`. This proposes one
vocabulary and one grammar in every one of those places, a report the
compiler derives and aeb checks a declaration against, and a pattern by
which an emitted library confines itself to what it was configured with.
It also states, up front, what none of this can do without the kernel's
help, so nobody mistakes it for a syscall sandbox.

## The case

Selaenium's `selenium_core/.build.ae` declares `caps("net,os,fs,extern")`.
Its source audit shows four distinct uses behind that one line: talking to
a remote WebDriver over HTTP, launching and killing local driver and
browser processes, downloading archives into a cache and marking them
executable, and an optional runner that listens. An adopter who only wants
the first gets all four, and `os` in that list covers `getenv` and
`run_capture` alike. The audit's last sentence is the real finding: the
build grants describe the source, and sandbox nothing once Java loads the
`.so`.

This isn't specific to Selaenium. RexxAE, servirtium-vcr and every
`--emit=lib` consumer face the same three questions with no shared answer:
what may the build do, what can the artifact do, what will the host let it
do.

The shape that answers them already runs in sae. An app's `app.json`
grants URL prefixes (`"http": ["https://api.github.com/"]`, scheme, host,
port and path, checked before any socket and on every redirect hop) and
directory roots with verbs (`"fs": { "read": [...], "write": [...] }`); a
page says what it wants in words a person reads (`seeks outgoing-http GET
https://api.github.com/notifications/*`); the page gets the intersection,
or fails to load saying why. `services/files` runs each operation inside
`std.sandbox.enforce` with those roots as its grants. That is the old Java
policy file's level of statement ("may write under this directory", "may
GET from this host and path"), written as code, enforced in-process. sae is
a runtime and Aether is a language, but the two can be spoken of together:
what sae had to build for itself is what the language should hand every
emit-lib consumer.

## Proposal

### 1. One vocabulary

`std.sandbox`'s categories become the capability vocabulary everywhere:

    fs_read  fs_write  exec  env  tcp  tcp_listen  udp  http  native  all

`http` is the one addition: a URL prefix (scheme, host, port, path) with an
optional verb list, `grant_http("GET", "https://api.github.com/repos/*")`.
It is sae's `capabilities.http` rule moved into `std.sandbox` and honoured
by `std.http.client` at the point a request is opened, before the socket
and again on each redirect hop. It is a protocol-level check, not a socket
one: an `http` grant implies no `tcp` grant, a raw `tcp_connect` to the
same host is refused, and the report lists the two separately.

- `--with=fs,net,os,extern` stays as the coarse build gate; each coarse
  name is defined as a set of fine ones (`os` = `exec`, `env`; `net` =
  `tcp`, `tcp_listen`, `udp`, `http`; `extern` = `native`).
- `--emit=effects` reports reachability per function in the fine set,
  with one edge per category: the first call site on the chain
  (`file:line`) and the `std` entry point it reaches. Reachability, not
  dataflow: it says a function *may* reach `exec`, never whether the
  executable is constant.
- `aether_describe().capabilities` carries the fine set the artifact was
  built to reach, so a consumer reads it before compiling anything.
- `docs/emit-lib.md`'s "per-function grants are out of scope" note is
  rewritten: the fine set is for reporting and self-confinement; the
  coarse gate is unchanged.

### 2. One grammar, two words

The `grant_*` setters of `std.sandbox.new` are the grammar, learnt once,
used in three files. The two words are sae's: code **seeks**, a context
**grants**, the effective set is their intersection, and a seek the
context does not grant fails at load with the reason. That is already the
rule of `std.sandbox`'s nested `enforce` and of aeb's operator ceiling;
naming it the same way everywhere is the DX point.

```aether
// std: a worker confines code it runs
worker = sandbox.new("driver") {
    grant_exec("${cache}/chromedriver*")
    grant_tcp("127.0.0.1", 0)
    grant_fs_write("${cache}/*")
}

// aeb: a maintainer says what the artifact seeks (checked, see 3)
aether.shared_lib() {
    caps("net,os,fs,extern")          // the coarse gate, as today
    seeks() {
        grant_exec("*")                // launches drivers it resolves at run time
        grant_http("*", "https://googlechromelabs.github.io/*")
        grant_http("*", "https://storage.googleapis.com/chrome-for-testing-public/*")
        grant_tcp("127.0.0.1", 0)      // the driver it launched
        grant_fs_write("*")
    }
}

// aeb: an operator's ceiling for the build itself (profile.ae)
profile("ci") {
    grant_fs_read("/usr/*")
    grant_fs_write("${target}/*")
    // no grant_tcp: the build may not reach the network
}
```

Narrowing becomes a data operation `std.sandbox` exports (`narrow(a, b)`,
`to_string`, `parse`), pattern-aware (`/cache/*` narrows `/cache/selenium/*`
to the latter, and refuses combinations it can't express, loudly). aeb's
`lib/sandbox` matcher, which today intersects exact pairs, goes away in
favour of it.

### 3. Declared against derived

aeb runs `--emit=effects` on what it builds and checks `seeks {}` against
it. A declared category nothing reaches is an error; a reached category not
declared is an error, with the edge printed. `caps()` is derived the same
way (`_detect_caps` already scans imports; it just isn't consulted).

The report is written beside the artifact, keyed by its digest, compiler
version and target. That's the input for a later aeb veto rule: a
dependency upgrade that widens a library's set fails CI with the new edge
named. Not in the first delivery.

### 4. The library confines itself

The pattern every emit-lib consumer copies, and the one sae's
`services/files` already uses: a `configure()` that builds a grant list
from what it was told, and exports that enter through `sandbox.enforce`.

```aether
configure(cache_dir: string, driver_host: string) {
    perms = sandbox.new("selenium_core") {
        grant_fs_read("${cache_dir}/*")
        grant_fs_write("${cache_dir}/*")
        grant_exec("${cache_dir}/*")
        grant_http("*", "http://${driver_host}/*")
        grant_env("SE_*")
    }
}

session_new(caps_json: string) -> string {
    return sandbox.enforce(perms) callback { return new_session(caps_json) }
}
```

Then the audit's last sentence changes from "these grants don't sandbox the
`.so` when Java loads it" to "the `.so` confines itself to the configured
cache and driver host, by the in-process checks". Which checks are active
on the platform is part of the report, not left to the reader.

For Selaenium specifically, two artifacts: a remote-only build whose entry
module never imports `drivermgr`, so the emitted C contains no
provisioning path at all, and the full build. Narrower by construction,
no feature flags.

### 5. The owned-string bridge

Selaenium's whole `extern` grant exists for `sel_embed_dup` /
`sel_embed_free`, the caller-owned-string pair every binding reinvents.
The lib ABI (`runtime/aether_lib_meta.h`) should export an owned-string
allocate and release, so that grant disappears from most consumers and
`native` in a report means something unusual is going on.

### 6. aeo consumes the report

aeo's `constrain {}` stays substrate-shaped: Capsicum fd grants and pf on
FreeBSD, `--cap-drop ALL` and podman network tiers on Linux. It doesn't
adopt the vocabulary; it reads the report. A node whose artifact never
reaches `tcp` gets `deny_egress()` unless the operator says otherwise. One
source of truth flowing outward: the compiler derives, aeb checks, the
host enforces in-process, aeo renders the kernel boundary.

## What this cannot do, and won't pretend to

- **A child process is a new authority boundary.** `grant_exec` decides
  *which* executable may start and with what environment. Once
  chromedriver or Chrome is running, nothing in this proposal sees its
  syscalls. Policing a child is the kernel's job: `std.capsicum` on
  FreeBSD, aeo's bwrap, nspawn and container drivers on Linux. Aether will
  not grow a seccomp or pledge of its own; re-engineering what a
  sub-process may do is operating-system work and we'd do it badly.
- **In-process checks cover Aether code paths.** `std`'s fs, net, os and
  udp entry points are checked. A C extern (`native`) is opaque, and so is
  anything that bypasses libc: raw `syscall()`, io_uring, a static binary.
  The LD_PRELOAD library adds libc-level checks for a process we start; it
  does not apply inside a JVM that loaded our `.so`, and the report says
  so per platform.
- **An `http` grant sees requests, not packets.** Only `std.http.client`
  honours it, in-process, where the URL is known. The LD_PRELOAD layer
  sees `connect()` to a host and port and nothing of the path or verb
  inside TLS; a C extern that opens its own socket is not checked at all.
  So "may GET from this host and path" is a statement about the Aether
  client, and the report says which layer checked what.
- **The report is reachability, not behaviour.** "May reach `exec`" is
  what the compiler can prove. Whether the target is a constant, a config
  value or attacker-supplied is dataflow we don't have and shouldn't fake
  with heuristics. Observed behaviour under tests stays a separate column.
- **Interop has a cost, small but real.** `enforce` is a TLS frame push
  and pop per export call; the checks sit on fs, net and os entry points
  only, never on string or collection ops. The owned-string bridge is one
  copy at the boundary. Zero-copy into a Java or Python host is not on
  offer here, and we'll measure the per-call overhead rather than assert it.
- **Concurrency and budgets stay open.** Self-confinement in 4 is a
  per-thread guarantee until #2955 settles what a host may do across
  threads and reentry, and nothing here bounds memory or time (#2954).
  This proposal neither depends on them nor pre-empts their answers.

## Delivery order

1. Vocabulary and report: fine categories in `--emit=effects` with one
   edge each, in `aether_describe`, and the emit-lib doc rewrite. Aether.
2. `std.sandbox` narrowing as data (`narrow`, `to_string`, `parse`), and
   aeb's matcher replaced by it. Aether, then aeb.
3. aeb `seeks {}` checked against the report; `caps()` derived. aeb.
4. Selaenium end to end: two artifacts, `configure()` + `enforce` on
   exports, the owned-string bridge in the ABI. Selaenium and Aether.
5. Digest-keyed report diffs in aeb's veto; aeo reading the report. Later.

Every step lands with the test that proves its guard: a forbidden
connect, cache write, launch and listen each attempted, and each test shown
to fail with its guard removed, per CONTRIBUTING's "prove the test can
fail".

## Questions for Nic

1. Are the nine `std.sandbox` categories plus `http` the right fine set to
   freeze as a vocabulary, or does `os` want splitting further (`env` read
   vs process control) before it becomes an ABI?
1a. Does `http` belong in `std.sandbox` as a category, enforced by
   `std.http.client`, or should it stay a client-level allowlist as sae
   keeps it in `services/net`? I'd put it in the vocabulary, so a report
   and a seek can name it, and have the client be its one enforcer.
2. Should `narrow` refuse every pattern combination it can't express
   exactly, or widen conservatively with a warning? I'd refuse.
3. Does the per-call `enforce` cost on an export path concern you enough
   to want an "enforce once at configure, trust exports" mode? I'd rather
   not add the mode until a number says to.
4. Is the owned-string allocate and release pair something you'd rather
   see in the generated SDKs than in the runtime ABI?
