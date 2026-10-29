# Writing security-sensitive code in Aether

Rules for code where getting it wrong is a vulnerability rather than a bug:
crypto, TLS, authentication, anything comparing a secret or consuming
randomness.

Every rule here is written from a real defect found in this tree, and each one
is the kind that **passes its tests**. That is the point: a handshake that
completes, a hash that verifies, a benchmark that speeds up are all compatible
with a serious flaw. Correctness testing does not catch these; the rule has to
be applied deliberately.

## Never substitute a default for missing entropy

If the CSPRNG fails, **fail**. Do not return zeros, a counter, a timestamp, or
a cached value.

```aether,fragment
// WRONG -- a helper that looks defensive and is catastrophic
fn rand_into(n: int) -> ptr {
    s, sn, err = cryptography.random_bytes(n)
    b = bytes.new(n)
    if string.equals(err, "") == 1 {
        bytes.copy_from_string(b, 0, s, n)
    }
    return b            // on failure: n zero bytes, silently
}
```

That shipped in a TLS server draft, and its three callers used the result as
the server random, the **ECDSA P-256 signing nonce**, and the **X25519 private
key**. A predictable ECDSA nonce discloses the signing key outright: one
signature is enough. The handshake completes; the test passes; the key is gone.

```aether,fragment
// RIGHT -- null, and every caller refuses
fn rand_into(n: int) -> ptr {
    s, sn, err = cryptography.random_bytes(n)
    if string.equals(err, "") != 1 { return null }
    if sn < n { return null }
    ...
}
```

The general form: **a security primitive has no safe default.** Where ordinary
code degrades gracefully, this code stops. Check the length returned as well as
the error: a short read is a failure.

## Compare secrets in constant time

Any comparison of a MAC, tag, token or password hash must take the same time
regardless of where the first difference is. Accumulate differences; never
return early.

```aether,fragment
// RIGHT
fn bytes_equal(a: ptr, b: ptr, n: int) -> int {
    diff = 0
    i = 0
    while i < n {
        diff = diff | ((bytes.get(a, i) ^ bytes.get(b, i)) & 0xFF)
        i = i + 1
    }
    if diff == 0 { return 1 }
    return 0
}
```

A `while` loop that `return 0`s on the first mismatch leaks the length of the
matching prefix, which is enough to recover a tag byte by byte over enough
attempts. This applies to `string.equals` on a secret too: it is a plain
comparison and is fine for a route name, wrong for a token.

## Fail closed, and name what failed

Every verification path ends in a refusal, not a fallthrough. The error should
say which check failed, because the alternative is a dropped connection the
peer cannot diagnose.

```aether,fragment
if fin_ok == 0 {
    ... free everything ...
    return null, "client Finished MAC verification failed"
}
```

Two habits that follow:

- **Free on the failure path too.** A refusal that leaks is still a refusal,
  but a long-lived server refusing repeatedly is a memory-exhaustion vector.
- **State the constraints you cannot meet.** A TLS server that only signs with
  ECDSA P-256 must say so, or an RSA certificate produces a plausible-looking
  server that fails at the signature step and the peer sees only a closed
  socket. Put it in the module header, not just the commit message.

## A library must not print

No `println` in `std` or `contrib` module code. Errors are already returned
through the `(value, err)` convention; printing them as well means a handshake
path writes a line **per connection** in production, and the operator cannot
turn it off.

Nine debug `println` calls reached review in one TLS server draft. They were
useful while writing it, and every one of them was a leak of internal state to
stdout at scale.

If you need progress output while developing, delete it before review, or gate
it behind an explicit debug flag the caller opts into.

## Do not invent crypto, and check what already exists

`std.cryptography` carries the primitives (AES, ChaCha20-Poly1305, P-256/384/521,
Ed25519, X25519, RSA, SHA-2/3, HKDF, ML-KEM, and the TLS 1.3 record, key
schedule, handshake and certificate layers). Before writing a construction,
check whether the piece exists, and whether the piece you need is the *inverse*
of something already present. The TLS server work was one layer, not a stack,
because the record layer and key schedule were already role-neutral.

Where you must write something new:

- **Test against a third party, not only against yourself.** Two halves of one
  codebase agreeing proves they share a wire format; it does not prove the
  format is right. `tests/integration/crypto_tls13_server_hs` parses a real
  ClientHello captured from `openssl s_client`, and the TLS vertical-slice test
  ends with `curl` against the pure server, for exactly this reason.
- **Use known-answer vectors where they exist.** RFC 8448 for TLS 1.3, RFC 7748
  for X25519, the Wycheproof corpus for the rest.
- **Test the negative cases.** A verifier that has never been shown a bad input
  is untested. Bad MAC, wrong host, expired certificate, malformed message,
  truncated input.

## Nonces, IVs and counters

- A nonce is **per message**, never reused with the same key. For ECDSA that is
  a hard requirement (nonce reuse across two signatures recovers the key, and
  so does a nonce whose top bits are predictable); for AEAD, reuse breaks
  confidentiality and authenticity both.
- **Do not take a signing nonce from the caller.** `ecdsa_sign` in
  `std.cryptography.p256` derives its nonce by RFC 6979 (HMAC-DRBG over the
  private key and the digest), so the same digest signed twice gives the same
  signature and no failing or biased random source can leak the key. It used
  to take the nonce as a parameter, and the TLS server and the mTLS client
  each had to draw one; an API that makes every caller get this right is an
  API that will be called wrong.
- **Hedge a deterministic nonce where the key lives long.** A deterministic
  nonce makes two signatures of one message share it, and a fault in one of
  them then gives the key away. `ecdsa_sign_hedged` (RFC 6979 section 3.6)
  and `ed25519.sign_hedged` mix fresh random bytes into the derivation. The
  bytes are not a nonce: whatever they hold (repeated, zero, an attacker's),
  the nonce is no weaker than the deterministic one, so taking them from
  the caller is safe where taking the nonce is not. The TLS CertificateVerify
  signatures, server and client, are hedged (#3376).
- Do not derive a nonce from something the peer controls.
- Where a counter is the nonce, the overflow case is a failure, not a wrap.

## Keys in memory, and the signatures that leave it

A long-lived private key is exposed by what it leaves behind and by what a
fault makes it compute (#3376).

- **Wipe a secret before you free it, with `bytes.wipe_free`.** A loop that
  zeroes a buffer right before `free` is a dead store, and a compiler that
  inlines it may drop it. `bytes.wipe` and `bytes.wipe_free` (and
  `aether_wipe` in C, `runtime/utils/aether_wipe.h`) zero the whole
  capacity through a call the compiler cannot see through. That covers key
  material, nonces and the text of a private key. A `string` cannot be
  wiped, so a secret that must be wiped lives in a `bytes` buffer, sized
  for its final length, because a buffer that grows leaves its old contents
  in the memory it moved out of.
- **A primitive wipes its own state.** Wiping the key is not enough if the
  hash, MAC or cipher that used it frees its state as it was: SHA-512's
  last block held an Ed25519 seed, HMAC's padded key is the key, and a
  SHA-2 context holds the digest that the shield uses as its AEAD key.
  So the rule is the whole tree's, not a choice per call, which missed one
  module after another: every module under `std/cryptography` frees every
  `bytes` buffer with `bytes.wipe_free` (`make check-crypto-wipe` fails on
  a plain `bytes.free` there, and `make ci` runs it), and wipes a context
  struct, a working matrix or an array of secret coefficients with
  `mem.wipe` (the raw-memory form) before it frees it (#3402, #3414). A
  public buffer pays a memset, which is nothing next to the cryptography
  that made it. The freed-memory probe (`tests/integration/crypto_key_wipe`)
  checks key loading, signing with each key type, an HMAC, a shield wrap
  and unwrap, an X25519 exchange and the TLS key schedule.
- **Verify a signature before it leaves the process.** One faulty RSA-CRT
  signature factors the modulus (Boneh, DeMillo and Lipton), and a fault in
  one of two signatures of the same message under a deterministic nonce
  (RFC 6979 ECDSA, Ed25519) gives the key. A fault can come from a voltage
  or clock glitch, or from Rowhammer, from software. The pure TLS server
  checks every CertificateVerify against its certificate's key
  (`tls13_cert.leaf_signature_holds`), and a signature that fails is wiped
  and never sent: the handshake ends with internal_error. The mTLS client
  checks its own the same way (`tls13_cert.client_cert_verify_holds`).
  Verify against the key the peer will use (the certificate's), not the
  private key's own public half, so a fault in the key's memory is caught
  too.

## Constant time, checked by a tool

Code that handles a secret must not branch on it, index memory with it, or
loop a number of times that depends on it: each of those makes the running
time or the cache footprint a function of the secret, and both are
measurable, across a network for the slow cases. A variable-time bignum
behind ECDSA signing leaks the nonce a few bits per signature; a few hundred
signatures then give the key.

Write it with masks:

```aether,fragment
// WRONG -- a branch on a secret bit
if bit == 1 { acc = add(acc, p) }

// RIGHT -- always compute, keep the result with a mask
mask = 0 - bit                       // all ones or zero
r = r ^ (mask & (r ^ candidate))     // r = candidate when bit is 1
```

and select from a table by reading every entry, never `table[secret]`.
`std.cryptography.ct` has `eq`, `lt`, `select` and `bytes_eq`, and
`std.cryptography.ecc` is the constant-time field and curve engine to build
on.

Reading the code is not enough to know it is constant time: the C compiler can
turn a mask back into a branch. The check is mechanical.
`tests/integration/crypto_ct_valgrind` runs each secret-key operation with its
secret inputs marked undefined for Valgrind's memcheck, which then reports
every conditional jump and every memory address computed from them; the CI job
`Crypto constant-time (Valgrind)` fails on any such report. Shown main's
bignum P-256 before the rewrite, it reported 68 secret-dependent branches.

A value the protocol reveals anyway (an ECDSA signature's retry decision, an
AEAD tag verdict, whether a key is in range) may decide a branch, and the
code says so with `ct.declassify(v)`, which the test hooks. Anything else
that memcheck reports is a leak to fix, not to declassify.

## TLS conformance corpora

The pure TLS stack is measured against outside test suites, each fetched at a
pinned commit into `$CONFORMANCE_CACHE` (default
`~/.cache/aether-conformance`) and never committed (#1298):

- **x509-limbo and bettertls** (`make conformance-x509`,
  `tests/conformance/x509_limbo`): every path-validation case of
  [x509-limbo](https://github.com/C2SP/x509-limbo), including the bettertls
  name-constraint suite it imports, through `tls13_cert.validate_chain` and
  `check_hostname`. `limbo.json` is checked against its SHA-256. The Linux
  job `ci-crypto-ct` runs it. `expected.txt` lists each case that is skipped
  or does not agree, with the reason and OpenSSL's verdict: the two TLS
  backends of `std.http` accept the same chains, except where OpenSSL accepts
  something unsafe, which the pure backend refuses.
- **BoGo** (`make conformance-bogo`, `tests/conformance/bogo`): BoringSSL's
  `ssl/test/runner` drives `shim.ae`, which runs `tls13_client` or
  `tls13_server` for each test. It needs Go (1.27 at the pinned commit) and
  git, takes about five minutes, and no CI job runs it. `config.json`
  disables each test that fails, with the reason: TLS 1.2 and earlier, which
  the pure stack does not implement, and the TLS 1.3 tests where it differs
  from BoringSSL by design. `BOGO_FLAGS="-test 'Basic-*'"` narrows a run.
  The shim handles only the flags its header lists; a test that passes any
  other counts as unimplemented (about 7450 tests at the pinned commit,
  against about 390 that pass), so BoGo does not cover:
  - session resumption (`-resume-count`, the `-on-resume-*` and
    `-expect-session-miss` checks) and with it 0-RTT (`-enable-early-data`,
    `-on-resume-shim-writes-first`, `-on-resume-expect-accept-early-data`).
    The client's resumption and 0-RTT are tested in `crypto_tls13_resume`,
    against a scripted server and `openssl s_server`; the pure server issues
    no tickets;
  - ALPN (`-advertise-alpn`, `-select-alpn`, `-expect-alpn`);
  - client certificates (`-require-any-client-certificate` and `-verify-peer`
    on a server, a certificate on a client): the pure server asks for none,
    and the client's mutual TLS is tested in `crypto_tls13_mtls_signature`;
  - SNI (`-host-name`), configured groups and signature algorithms
    (`-curves`, `-key-shares`, `-signing-prefs`, `-verify-prefs`), and the
    `-expect-*` checks of what was negotiated;
  - ECH, external PSKs, OCSP stapling and certificate compression options,
    renegotiation, DTLS and QUIC.

A case that changes verdict fails its run, so a change to the TLS code that
makes any of them pass or fail differently has to say so in the same commit.

## Review checklist

For any diff touching crypto, TLS or authentication:

- [ ] Every randomness call checks both the error **and** the length
- [ ] No security-relevant default on a failure path (no zeros, no reuse)
- [ ] MAC/tag/token comparisons are constant-time
- [ ] No branch, loop bound or memory index depends on a secret, and the
      operation is in `tests/integration/crypto_ct_valgrind`
- [ ] No signing API takes a nonce from its caller
- [ ] A signature is verified before it is sent, and secrets are freed with
      `bytes.wipe_free`
- [ ] Every verification failure returns an error naming the check
- [ ] Failure paths free what they allocated
- [ ] No `println` in library code
- [ ] Tested against a third-party implementation, not only against ourselves
- [ ] Negative cases tested: bad MAC, wrong identity, malformed input
- [ ] Constraints that fail as a dropped connection are documented in the
      module header
