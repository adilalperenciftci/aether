# Elixir Thread Ring Benchmark (Savina-style)

defmodule ThreadRing do
  @ring_size 100
  @num_hops (System.get_env("BENCHMARK_MESSAGES") |> case do
    nil -> 100_000
    val -> String.to_integer(val)
  end)

  def start do
    IO.puts("=== Elixir Thread Ring Benchmark ===")
    IO.puts("Ring size: #{@ring_size}, Hops: #{@num_hops}\n")

    parent = self()

    # Create ring of processes
    first = spawn(fn -> ring_node(nil, parent, 0) end)
    {last, nodes} = create_ring(first, @ring_size - 1, parent, [first])

    # Close the ring: last -> first (not first -> last!)
    send(last, {:set_next, first})

    start_time = :erlang.monotonic_time(:nanosecond)

    # Send initial token
    send(first, {:token, @num_hops})

    # Wait for completion
    receive do
      :done ->
        end_time = :erlang.monotonic_time(:nanosecond)
        elapsed_ns = end_time - start_time
        elapsed_sec = elapsed_ns / 1_000_000_000.0

        # The receipts summed over the ring, the checksum.
        receipts = collect_receipts(nodes, 0)

        throughput = (@num_hops + 1) / elapsed_sec / 1_000_000
        ns_per_msg = elapsed_ns / (@num_hops + 1)

        IO.puts("Checksum: #{receipts}")
        IO.puts("ns/msg:         #{:io_lib.format("~.2f", [ns_per_msg])}")
        IO.puts("Throughput:     #{:io_lib.format("~.2f", [throughput])} M msg/sec")
    after
      60_000 ->
        IO.puts("Timeout!")
        System.halt(1)
    end
  end

  defp create_ring(prev, 0, _parent, nodes), do: {prev, nodes}
  defp create_ring(prev, n, parent, nodes) do
    next = spawn(fn -> ring_node(prev, parent, 0) end)
    send(prev, {:set_next, next})
    create_ring(next, n - 1, parent, [next | nodes])
  end

  defp collect_receipts([], acc), do: acc
  defp collect_receipts([node | rest], acc) do
    send(node, {:report, self()})
    receive do
      {:count, count} -> collect_receipts(rest, acc + count)
    end
  end

  defp ring_node(next, parent, received) do
    receive do
      {:set_next, new_next} ->
        ring_node(new_next, parent, received)
      {:token, 0} ->
        # Token exhausted: tell the parent, and stay to report the count
        send(parent, :done)
        ring_node(next, parent, received + 1)
      {:token, hops} ->
        send(next, {:token, hops - 1})
        ring_node(next, parent, received + 1)
      {:report, from} ->
        send(from, {:count, received})
    end
  end
end

ThreadRing.start()
