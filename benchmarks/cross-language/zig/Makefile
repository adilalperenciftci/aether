.PHONY: all clean flags ping_pong counting thread_ring fork_join skynet

# The build is build.zig's, for the native CPU, in ReleaseFast: the Zig
# equivalent of the C benchmarks' -O3 -march=native -flto (build.zig says why).
# The runner (run_benchmarks.ae) runs `make <pattern>` here and starts
# zig-out/bin/<pattern>.
ZIG = zig

all: ping_pong counting thread_ring fork_join skynet

ping_pong counting thread_ring fork_join skynet:
	$(ZIG) build -Doptimize=ReleaseFast

# What the runner records with the results (run_benchmarks.ae).
flags:
	@echo "$(ZIG) build -Doptimize=ReleaseFast (target: the native CPU)"

clean:
	rm -rf .zig-cache zig-out
