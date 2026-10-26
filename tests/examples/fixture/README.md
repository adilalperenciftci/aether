# Fixture for tests/examples/check.ae

The self-test `make check-examples` runs first: the checker must find
exactly 15 problems here, one of each kind it reports.

- [good.ae](good.ae) builds, runs and prints its Output block
- [modular.ae](modular.ae) imports a module of its own ([helper](helper/module.ae))
- [needs.ae](needs.ae) only builds, and says what it needs
- [mismatch.ae](mismatch.ae) prints something else
- [missing.ae](missing.ae) does not exist
- [warn.ae](warn.ae) builds with a warning, and [warn_uncoded.ae](warn_uncoded.ae)
  with one that has no code
- [slow.ae](slow.ae) runs past the time bound
- [noneeds.ae](noneeds.ae) neither prints an Output block nor says what it needs
- [notlast.ae](notlast.ae) has an Output block that does not end the file
- [badrun.ae](badrun.ae) runs a tool other than `ae` or `sh`
- [wrongname.ae](wrongname.ae) runs another file
- [failing.ae](failing.ae) exits with a status other than 0
- [badpart.ae](badpart.ae) and [orphan.ae](orphan.ae) belong to no example
- [contrib_needs.ae](contrib_needs.ae) imports a contrib bridge and says what it needs
- [contrib_bare.ae](contrib_bare.ae) imports one and does not

Not linked: [unlinked.ae], and leftover.bin is not source.
