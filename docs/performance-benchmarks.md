# Aether Performance Benchmarks

## Overview

The Aether benchmark suite measures message-passing throughput, latency, memory efficiency, and scalability across 11 programming languages using 5 patterns from the [Savina Actor Benchmark Suite](https://dl.acm.org/doi/10.1145/2687357.2687368) (Imam & Sarkar, Rice University, 2014).

## Benchmark Patterns

### Ping-Pong

Two actors exchange messages back and forth. Measures pure message-passing latency with zero computation.

- 2 actors, configurable message count via `BENCHMARK_MESSAGES`
- Tests: message send/receive overhead, mailbox performance

**Location:** `benchmarks/cross-language/aether/ping_pong.ae`

### Counting

Single actor counts incoming messages from the main thread. Tests unidirectional throughput and single-actor scheduler optimizations.

- 1 actor, main thread sends all messages
- Activates Main Thread Actor Mode (synchronous processing, no scheduler overhead)

**Location:** `benchmarks/cross-language/aether/counting.ae`

### Thread Ring

Token passed through a ring of 100 actors with sequential dependencies. Measures scheduling overhead with many actors.

- 100 actors in a ring, token forwarded around
- Benefits from locality-aware placement (all actors on same core)

**Location:** `benchmarks/cross-language/aether/thread_ring.ae`

### Fork-Join

Round-robin fan-out to 8 worker actors. Tests parallel dispatch throughput and batch send optimization.

- 8 worker actors, messages distributed round-robin from main thread
- Activates Batch Send optimization (groups messages by target core)

**Location:** `benchmarks/cross-language/aether/fork_join.ae`

### Skynet

Recursive 10-ary tree summing 1M leaves. Tests actor creation rate, message aggregation, and tree coordination.

- Recursive tree: each node spawns 10 children; below a subtree of 1000 leaves a node sums its range in a plain loop
- Every language creates the same 1,111 concurrency units for a million leaves, and the rate divides by them

**Location:** `benchmarks/cross-language/aether/skynet.ae`

## Languages

All 11 languages implement all 5 patterns:

| Language | Runtime | Concurrency Model | Build |
|----------|---------|-------------------|-------|
| **Aether** | Native (Aether runtime) | Actors on the runtime's scheduler | `-O3 -march=native -flto` |
| **C** | Native (pthread) | A thread per unit, single-sender mailboxes on C11 atomics | `-O3 -march=native -flto` |
| **C++** | Native (std::thread) | A thread per unit, single-sender mailboxes on `std::atomic` | `-O3 -march=native -flto` |
| **Go** | Go runtime | Goroutines with buffered channels | `go build` |
| **Rust** | Native (std::thread) | A thread per unit, single-sender mailboxes on `std` atomics | release profile, fat LTO, `target-cpu=native` |
| **Java** | JVM | Platform threads and `LinkedTransferQueue`; virtual threads for the ring; `ForkJoinPool` for skynet | `javac`, the JIT |
| **Zig** | Native (std.Thread) | A thread per unit, single-sender mailboxes on `std.atomic` | `ReleaseFast`, native CPU |
| **Elixir** | BEAM VM | Lightweight processes + mailboxes | the JIT |
| **Erlang** | BEAM VM | Lightweight processes + mailboxes | `erlc`, the JIT |
| **Pony** | Native (Pony runtime) | GC-free actors, ref capabilities | `ponyc` release |
| **Scala** | JVM | As Java, through `java.util.concurrent` | `sbt compile`, the JIT |

## Methodology

[benchmarks/cross-language/FAIRNESS.md](../benchmarks/cross-language/FAIRNESS.md)
holds the suite's rules, each language's technique and why, and the audits
that produced them, with every alternative measured.

### Statistical Approach

Each benchmark runs **5 times** (`BENCH_RUNS`) after **1 warmup run**
(`BENCH_WARMUP`), the same for every language. The **median** throughput is
reported (the middle of the sorted runs), with the minimum, the maximum and
the coefficient of variation. All individual run values are stored.

**Metrics reported per language:**

| Metric | Description |
|--------|-------------|
| Throughput (M msg/s) | Messages processed per second (median of N runs) |
| Per CPU-s (M msg/CPU-s) | Messages per second of CPU time, user + system, every thread |
| Latency (ns/msg) | Nanoseconds per message (median) |
| CPU s | CPU time of a run |
| Memory (MB) | Peak resident set size via `/usr/bin/time` |
| Relative (%) | Percentage of the fastest language's throughput |
| CV% | Coefficient of variation (sample standard deviation over the mean, times 100): run-to-run stability |
| Range | Minimum and maximum throughput across the runs |
| Efficiency | Throughput per MB of memory (M msg/s/MB) |

**CV% interpretation.** The thresholds below are general statistical
stability bands for coefficient of variation, not Aether-specific
targets. They tell you how much to trust a single run's headline
figure, regardless of which language is being measured:

- **< 5%** (green): run-to-run variance is small; reported medians are trustworthy.
- **5-15%** (orange): moderate variance; read medians alongside Min-Max range.
- **> 15%** (red): high variance; investigate thermal throttling, OS scheduling, or shared-host noise before citing numbers.

### Measurement

- Wall-clock time from each language's monotonic clock, around the creation of the units and every message
- CPU time and peak RSS via `/usr/bin/time -v` (Linux) or `-l` (macOS); n/a on Windows, where MSYS's `time` cannot see a native program
- Every run's checksum is checked against the value a correct run prints (skynet: 499,999,500,000 for 1M leaves, and 1,111 units); a wrong one is reported as `[FAIL]`, not measured

### Fairness

- Standard library only; the same message count (`BENCHMARK_MESSAGES`), units and messages in every language
- Each language is built by its own build file at its release level for the host CPU; the runner passes no flags and records each build's
- Skynet divides by the units created, the same 1,111 everywhere
- Each language's technique follows a rule set by the shape of the work, not picked per pattern from the results: the thread-per-unit languages share one mailbox design that spins, then sleeps, where the units fit the cores and sleeps at once where they do not
- Results JSON includes the methodology, the toolchain versions and the build flags

## Running Benchmarks

### Full Suite (all languages)

```bash
make benchmark
```

This builds the Aether benchmark runner (`run_benchmarks.ae`), compiles all 11 languages, runs all 5 patterns, writes JSON results, and launches the visualization server (`server.ae`) at `http://localhost:8080`. Both the runner and the server are written in Aether using only the stdlib, no extern FFI, no C helper files.

### Aether Only

```bash
cd benchmarks/cross-language/aether
make ping_pong && ./ping_pong
```

### Configuration

```bash
# Override message count
BENCHMARK_MESSAGES=10000000 make benchmark

# Override number of timed runs
BENCH_RUNS=10 make benchmark

# Override warmup runs (every language gets the same)
BENCH_WARMUP=3 make benchmark
```

### Visualization

After `make benchmark`, a web UI opens at `http://localhost:8080` showing:

- **Summary strip**: Aether rank, throughput, vs fastest, efficiency, spread
- **Charts**: Throughput and memory bar charts with Aether highlighted
- **Sortable table**: Click any column header to sort. Columns include throughput, latency, memory, relative performance bar, CV%, min-max range, and efficiency
- **Pattern tabs**: Switch between all 5 benchmark patterns
- **Methodology box**: Explains what's being measured and how to interpret CV%

Results are stored as JSON in `benchmarks/cross-language/visualize/results_*.json` with full metadata (hardware, runs, warmup, methodology).

## Active Optimizations

These Aether runtime optimizations affect benchmark performance:

| Optimization | Effect | File |
|-------------|--------|------|
| Main Thread Actor Mode | Single-actor programs bypass scheduler entirely | `runtime/actors/aether_send_message.c` |
| Inline message path | Single-field messages (int, int64, uint64, duration, ptr) skip heap allocation, value stored in `Message.payload_int` | `compiler/codegen/codegen.c` |
| Batch send | Main-thread fan-out groups messages by target core, reducing atomics from N to num_cores | `runtime/scheduler/multicore_scheduler.c` |
| Partial batch enqueue | `queue_enqueue_batch` returns how many fit instead of all-or-nothing | `runtime/scheduler/lockfree_queue.h` |
| Work inlining | Same-core sends invoke `actor->step()` immediately, skipping the scheduler drain loop | `runtime/scheduler/multicore_scheduler.c` |
| Computed goto dispatch | Message handlers use GCC computed-goto dispatch tables | `compiler/codegen/codegen_actor.c` |
| TLS caching | `current_core_id` cached in local variables, avoiding repeated `tlv_get_addr` on macOS | `runtime/scheduler/multicore_scheduler.c` |
| SPSC queues | Lock-free single-producer single-consumer ring buffers for cross-core messaging | `runtime/scheduler/lockfree_queue.h` |
| Adaptive batching | Batch size adjusts dynamically (64-1024) based on queue utilization | `runtime/actors/aether_adaptive_batch.h` |

## References

- [Savina, An Actor Benchmark Suite](https://dl.acm.org/doi/10.1145/2687357.2687368) (Imam & Sarkar, 2014)
- [Cross-Language Benchmark Source](../benchmarks/cross-language/)
- [Runtime Optimizations](runtime-optimizations.md)
- [Scheduler Architecture](scheduler-quick-reference.md)
