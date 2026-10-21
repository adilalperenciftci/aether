.PHONY: all clean flags ping_pong counting thread_ring fork_join skynet

# javac compiles to bytecode; the JVM's JIT compiles it for the CPU it runs
# on, which is the JVM's equivalent of -march=native, and the runner gives
# every language the same warmup run first (FAIRNESS.md, build parity).
JAVAC = javac

all: ping_pong counting thread_ring fork_join skynet

ping_pong:
	$(JAVAC) -d classes PingPong.java
counting:
	$(JAVAC) -d classes Counting.java
thread_ring:
	$(JAVAC) -d classes ThreadRing.java
fork_join:
	$(JAVAC) -d classes ForkJoin.java
skynet:
	$(JAVAC) -d classes Skynet.java

# What the runner records with the results (run_benchmarks.ae).
flags:
	@echo "$(JAVAC) -d classes (bytecode; the JIT compiles for the host CPU)"

clean:
	rm -rf classes
