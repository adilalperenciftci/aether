// Pony Thread Ring Benchmark (Savina-style)
// N actors arranged in a ring, passing a token M times

use "time"
use "collections"

actor RingNode
  let _id: USize
  let _main: Main
  var _next: (RingNode | None) = None
  var _received: U64 = 0

  new create(id: USize, main: Main) =>
    _id = id
    _main = main

  be set_next(next: RingNode) =>
    _next = next

  be pass(token: U64) =>
    _received = _received + 1
    if token == 0 then
      _main.done()
    else
      match _next
      | let n: RingNode => n.pass(token - 1)
      end
    end

  // How many tokens this node received: the receipts summed over the ring
  // are the checksum.
  be report() =>
    _main.receipts(_received)

actor Main
  let _env: Env
  var _start: U64 = 0
  var _finish: U64 = 0
  let _ring_size: USize = 100
  var _num_hops: U64 = 100_000
  let _nodes: Array[RingNode]
  var _reports: USize = 0
  var _receipts: U64 = 0

  new create(env: Env) =>
    _env = env
    _nodes = Array[RingNode](_ring_size)

    // Read BENCHMARK_MESSAGES from environment
    for v in env.vars.values() do
      if v.contains("BENCHMARK_MESSAGES=") then
        try
          let parts = v.split("=")
          let val_str = parts(1)?
          _num_hops = val_str.u64()?
        end
      end
    end

    _env.out.print("=== Pony Thread Ring Benchmark ===")
    _env.out.print("Ring size: " + _ring_size.string() + ", Hops: " + _num_hops.string() + "\n")

    // The clock starts before the ring exists, as in every language here
    // (FAIRNESS.md, rule 5).
    _start = Time.nanos()

    // Create ring of actors
    var i: USize = 0
    while i < _ring_size do
      _nodes.push(RingNode(i, this))
      i = i + 1
    end

    // Connect ring
    i = 0
    while i < _ring_size do
      try
        let curr = _nodes(i)?
        let next_idx = (i + 1) % _ring_size
        let next_node = _nodes(next_idx)?
        curr.set_next(next_node)
      end
      i = i + 1
    end

    // Start the token passing
    try
      _nodes(0)?.pass(_num_hops)
    end

  be done() =>
    _finish = Time.nanos()
    for node in _nodes.values() do
      node.report()
    end

  be receipts(count: U64) =>
    _receipts = _receipts + count
    _reports = _reports + 1
    if _reports == _ring_size then
      let total_messages = _num_hops + 1
      let elapsed_ns = _finish - _start
      let ns_per_msg = elapsed_ns.f64() / total_messages.f64()
      let throughput = 1_000_000_000.0 / ns_per_msg

      _env.out.print("Checksum: " + _receipts.string())
      _env.out.print("ns/msg:         " + ns_per_msg.string())
      _env.out.print("Throughput:     " + (throughput / 1_000_000.0).string() + " M msg/sec")
    end
