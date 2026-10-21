.PHONY: all clean flags ping_pong counting thread_ring fork_join skynet

# ponyc compiles a directory into a release build by default (optimised,
# whole program, LLVM LTO) for the CPU it runs on, the equivalent of the
# C benchmarks' -O3 -march=native -flto (FAIRNESS.md, build parity).
PONYC = ponyc

all: ping_pong counting thread_ring fork_join skynet

ping_pong counting thread_ring fork_join skynet:
	cd $@ && $(PONYC) . -o .

# What the runner records with the results (run_benchmarks.ae).
flags:
	@echo "$(PONYC) . (release, for the host CPU)"

clean:
	rm -f */ping_pong */counting */thread_ring */fork_join */skynet
