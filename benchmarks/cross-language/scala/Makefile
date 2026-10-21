.PHONY: all clean flags ping_pong counting thread_ring fork_join skynet

# sbt compiles the sources to bytecode, and its writeClasspath task (build.sbt)
# writes the runtime classpath (the classes and the Scala library) to
# classpath.txt, so the runner starts the benchmark with `java -cp` like the
# Java column. Run through sbt (`sbt runMain`), each measurement also held
# sbt's own JVM, its CPU time and its memory. The JIT compiles for the host
# CPU (FAIRNESS.md, build parity).
SBT = sbt

all: ping_pong counting thread_ring fork_join skynet

ping_pong counting thread_ring fork_join skynet: classpath.txt

classpath.txt: build.sbt project/build.properties $(wildcard *.scala)
	$(SBT) -batch -error writeClasspath

# What the runner records with the results (run_benchmarks.ae).
flags:
	@echo "sbt compile, $$(grep scalaVersion build.sbt) (bytecode; the JIT compiles for the host CPU)"

clean:
	rm -rf target project/target classpath.txt
