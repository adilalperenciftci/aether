#!/usr/bin/env elixir

# Elixir ping-pong benchmark using processes
defmodule PingPong do
  @messages (System.get_env("BENCHMARK_MESSAGES") |> case do
    nil -> 100_000
    val -> String.to_integer(val)
  end)

  # Returns the sum of the values ping got back, which the runner checks.
  def ping(pong_pid, 0, _, sum) do
    send(pong_pid, :done)
    sum
  end

  def ping(pong_pid, n, i, sum) do
    send(pong_pid, {:ping, self(), i})
    receive do
      {:pong, value} ->
        # Validate received value matches what was sent
        if value != i do
          IO.puts(:stderr, "Ping validation error: expected #{i}, got #{value}")
        end
        ping(pong_pid, n - 1, i + 1, sum + value)
    end
  end

  def pong(expected) do
    receive do
      {:ping, sender, value} ->
        # Validate received value matches expected sequence
        if value != expected do
          IO.puts(:stderr, "Pong validation error: expected #{expected}, got #{value}")
        end
        # Echo back the EXACT value received
        send(sender, {:pong, value})
        pong(expected + 1)
      :done ->
        :ok
    end
  end

  def run() do
    IO.puts("=== Elixir Ping-Pong Benchmark ===")
    IO.puts("Messages: #{@messages}")
    IO.puts("Using Erlang/OTP processes\n")

    ping_pid = self()

    start = :erlang.monotonic_time(:nanosecond)
    pong_pid = spawn(fn -> pong(0) end)
    checksum = ping(pong_pid, @messages, 0, 0)
    finish = :erlang.monotonic_time(:nanosecond)

    total_ns = finish - start
    ns_per_msg = total_ns / @messages
    throughput = 1.0e9 / ns_per_msg

    IO.puts("Checksum: #{checksum}")
    IO.puts("ns/msg:         #{Float.round(ns_per_msg, 2)}")
    IO.puts("Throughput:     #{Float.round(throughput / 1.0e6, 2)} M msg/sec")
  end
end

PingPong.run()
