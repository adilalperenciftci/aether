# Elixir Fork-Join Benchmark (Savina-style)

defmodule ForkJoin do
  @num_workers 8
  @messages_per_worker (System.get_env("BENCHMARK_MESSAGES") |> case do
    nil -> 100_000
    val -> div(String.to_integer(val), 8)
  end)

  def start do
    total = @num_workers * @messages_per_worker
    IO.puts("=== Elixir Fork-Join Throughput Benchmark ===")
    IO.puts("Workers: #{@num_workers}, Messages: #{total}\n")

    parent = self()

    # The clock starts before the workers exist, as in every language here
    # (FAIRNESS.md, rule 5).
    start_time = :erlang.monotonic_time(:nanosecond)

    # Create workers
    workers = Enum.map(1..@num_workers, fn _ ->
      spawn(fn -> worker_loop(0, 0, parent) end)
    end)
    worker_tuple = List.to_tuple(workers)

    # Send messages round-robin
    send_work(worker_tuple, 0, total)

    # Signal workers to report
    Enum.each(workers, fn w -> send(w, {:done, self()}) end)

    # Collect results: the messages and the sum of their values
    {total_processed, checksum} = collect_results(@num_workers, 0, 0)

    end_time = :erlang.monotonic_time(:nanosecond)
    elapsed_ns = end_time - start_time
    elapsed_sec = elapsed_ns / 1_000_000_000.0

    if total_processed != total do
      IO.puts("VALIDATION FAILED: expected #{total}, got #{total_processed}")
    end

    throughput = total / elapsed_sec / 1_000_000
    ns_per_msg = elapsed_ns / total

    IO.puts("Checksum: #{checksum}")
    IO.puts("ns/msg:         #{:io_lib.format("~.2f", [ns_per_msg])}")
    IO.puts("Throughput:     #{:io_lib.format("~.2f", [throughput])} M msg/sec")
  end

  defp send_work(_workers, i, total) when i >= total, do: :ok
  defp send_work(workers, i, total) do
    worker_idx = rem(i, @num_workers)
    send(elem(workers, worker_idx), {:work, i})
    send_work(workers, i + 1, total)
  end

  defp worker_loop(processed, sum, parent) do
    receive do
      {:work, value} ->
        worker_loop(processed + 1, sum + value, parent)
      {:done, from} ->
        send(from, {:result, processed, sum})
    end
  end

  defp collect_results(0, acc, sum_acc), do: {acc, sum_acc}
  defp collect_results(n, acc, sum_acc) do
    receive do
      {:result, count, sum} ->
        collect_results(n - 1, acc + count, sum_acc + sum)
    end
  end
end

ForkJoin.start()
