.PHONY: all clean flags ping_pong counting thread_ring fork_join skynet

# The Elixir benchmarks are scripts: `elixir <pattern>.exs` compiles the
# module to BEAM bytecode as it loads it, before the timed region starts, and
# the BEAM's JIT compiles that for the host CPU. There is nothing to build
# ahead of the run; these targets only check that elixir is there.
ELIXIR = elixir

all: ping_pong counting thread_ring fork_join skynet

ping_pong counting thread_ring fork_join skynet:
	@$(ELIXIR) --version > /dev/null

# What the runner records with the results (run_benchmarks.ae).
flags:
	@echo "$(ELIXIR) <pattern>.exs (compiled to BEAM bytecode at load; the JIT compiles for the host CPU)"

clean:
	@:
