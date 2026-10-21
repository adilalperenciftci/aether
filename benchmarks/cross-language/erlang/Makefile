.PHONY: all clean flags ping_pong counting thread_ring fork_join skynet

# Use standard Erlang compilation for fair baseline comparison
ERLC = erlc
ERLC_FLAGS =
ERL = erl
ERL_FLAGS = -noshell

all: ping_pong counting thread_ring fork_join skynet

ping_pong counting thread_ring fork_join skynet:
	$(ERLC) $(ERLC_FLAGS) $@.erl

run_ping_pong: ping_pong
	$(ERL) $(ERL_FLAGS) -s ping_pong start

# Skynet creates 1,111 processes for a million leaves (FAIRNESS.md), well
# under the default limit, so it runs with no +P.
run_skynet: skynet
	$(ERL) $(ERL_FLAGS) -s skynet start

# What the runner records with the results (run_benchmarks.ae).
flags:
	@echo "$(ERLC) $(ERLC_FLAGS) (BEAM bytecode; the JIT compiles for the host CPU)"

clean:
	rm -f *.beam

.DEFAULT_GOAL := all
