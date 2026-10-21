.PHONY: all clean flags ping_pong counting thread_ring fork_join skynet

# The Go benchmarks build with the go command's defaults, which are its
# release build: the compiler optimises and inlines by default and links the
# whole program, so there is no -O or LTO switch to add (FAIRNESS.md, build
# parity).
GO = go
ifeq ($(OS),Windows_NT)
EXE = .exe
endif

# A stale GOROOT pointing at another Go than the `go` on PATH fails with
# 'compile: version "go1.X" does not match go tool version "go1.Y"'; the go
# command finds its own root when none is set.
unexport GOROOT

all: ping_pong counting thread_ring fork_join skynet

ping_pong counting thread_ring fork_join skynet:
	$(GO) build -o $@$(EXE) $@.go

# What the runner records with the results (run_benchmarks.ae).
flags:
	@echo "$(GO) build (defaults)"

clean:
	rm -f ping_pong counting thread_ring fork_join skynet *.exe
