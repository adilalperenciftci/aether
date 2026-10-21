.PHONY: all clean flags ping_pong counting thread_ring fork_join skynet

# The build is build.zig's; the runner starts zig-out/bin/<pattern>
# (run_benchmarks.ae runs `make <pattern>` in every language's directory).
ZIG = zig

all: ping_pong counting thread_ring fork_join skynet

ping_pong counting thread_ring fork_join skynet:
	$(ZIG) build -Doptimize=ReleaseFast

# What the runner records with the results (run_benchmarks.ae).
flags:
	@echo "$(ZIG) build -Doptimize=ReleaseFast"

clean:
	rm -rf .zig-cache zig-out
