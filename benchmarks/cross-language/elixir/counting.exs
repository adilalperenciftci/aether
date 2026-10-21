# Elixir Counting Actor Benchmark (Savina-style)

defmodule Counting do
  @messages (System.get_env("BENCHMARK_MESSAGES") |> case do
    nil -> 100_000
    val -> String.to_integer(val)
  end)

  def start do
    IO.puts("=== Elixir Counting Actor Benchmark ===")
    IO.puts("Messages: #{@messages}\n")

    parent = self()

    # The clock starts before the counter exists, as in every language here
    # (FAIRNESS.md, rule 5).
    start_time = :erlang.monotonic_time(:nanosecond)
    counter = spawn(fn -> counter_loop(0, parent) end)

    # Send all messages: a recursive loop, as in Erlang and in fork_join.exs,
    # not Enum.each, which adds an anonymous function call per message.
    send_messages(counter, @messages)

    # Signal done
    send(counter, {:done, self()})

    # Wait for count
    receive do
      {:count, count} ->
        end_time = :erlang.monotonic_time(:nanosecond)
        elapsed_ns = end_time - start_time
        elapsed_sec = elapsed_ns / 1_000_000_000.0

        if count != @messages do
          IO.puts("VALIDATION FAILED: expected #{@messages}, got #{count}")
        end

        throughput = @messages / elapsed_sec / 1_000_000
        ns_per_msg = elapsed_ns / @messages

        IO.puts("Checksum: #{count}")
        IO.puts("ns/msg:         #{:io_lib.format("~.2f", [ns_per_msg])}")
        IO.puts("Throughput:     #{:io_lib.format("~.2f", [throughput])} M msg/sec")
    after
      60_000 ->
        IO.puts("Timeout!")
        System.halt(1)
    end
  end

  defp send_messages(_counter, 0), do: :ok

  defp send_messages(counter, n) do
    send(counter, :increment)
    send_messages(counter, n - 1)
  end

  defp counter_loop(count, parent) do
    receive do
      :increment ->
        counter_loop(count + 1, parent)
      {:done, from} ->
        send(from, {:count, count})
    end
  end
end

Counting.start()
