.PHONY: all clean flags ping_pong counting thread_ring fork_join skynet

# The build is Cargo's: the release profile in Cargo.toml and the flags in
# .cargo/config.toml. This file only names the targets the runner builds
# (run_benchmarks.ae runs `make <pattern>` in every language's directory).
CARGO = cargo

all: ping_pong counting thread_ring fork_join skynet

ping_pong counting thread_ring fork_join skynet:
	$(CARGO) build --release --bin $@

# What the runner records with the results: the release profile and the
# rustflags, read from the files that set them.
flags:
	@printf 'cargo build --release; '; sed -n '/^\[profile.release\]/,/^$$/p' Cargo.toml | grep '=' | tr '\n' ' '; \
	  [ -f .cargo/config.toml ] && grep rustflags .cargo/config.toml | tr '\n' ' '; echo

clean:
	$(CARGO) clean
