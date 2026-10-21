%% Erlang Skynet Benchmark
%% Based on https://github.com/atemerev/skynet
%% Uses native Erlang processes (lightweight ~2KB each).
%% For 1M leaves, start with: erl +P 2000000 -noshell -s skynet start
-module(skynet).
-export([start/0]).

get_leaves() ->
    case os:getenv("SKYNET_LEAVES") of
        false ->
            case os:getenv("BENCHMARK_MESSAGES") of
                false -> 1000000;
                Val -> list_to_integer(Val)
            end;
        Val -> list_to_integer(Val)
    end.

%% Units created; also the divisor. See FAIRNESS.md.
-define(SEQ_THRESHOLD, 1000).
total_actors(N) when N =< ?SEQ_THRESHOLD -> 1;
total_actors(N) -> (N div ?SEQ_THRESHOLD) + total_actors(N div 10).

%% Each node spawns 10 children or reports its offset (leaf).
%% Results bubble up via message passing.
%% Same threshold as every other language here.
skynet_node(Offset, Size, Parent) when Size =< ?SEQ_THRESHOLD ->
    Parent ! seq_sum(Offset, Size, 0);
skynet_node(Offset, Size, Parent) ->
    ChildSize = Size div 10,
    Self = self(),
    lists:foreach(fun(I) ->
        spawn(fun() ->
            skynet_node(Offset + I * ChildSize, ChildSize, Self)
        end)
    end, lists:seq(0, 9)),
    Sum = collect(10, 0),
    Parent ! Sum.

seq_sum(_Offset, 0, Acc) -> Acc;
seq_sum(Offset, N, Acc) -> seq_sum(Offset, N - 1, Acc + Offset + N - 1).

collect(0, Acc) -> Acc;
collect(N, Acc) ->
    receive
        Value ->
            collect(N - 1, Acc + Value)
    end.

start() ->
    NumLeaves = get_leaves(),
    TotalActors = total_actors(NumLeaves),

    io:format("=== Erlang Skynet Benchmark ===~n"),
    io:format("Leaves: ~p, concurrency units: ~p (sequential below ~p)~n~n",
              [NumLeaves, TotalActors, ?SEQ_THRESHOLD]),

    Self = self(),
    Start = erlang:monotonic_time(nanosecond),
    spawn(fun() -> skynet_node(0, NumLeaves, Self) end),
    Sum = receive V -> V after 120000 -> timeout end,
    End = erlang:monotonic_time(nanosecond),

    ElapsedNs = max(End - Start, 1),

    io:format("Sum: ~p~n", [Sum]),
    io:format("Checksum: ~p~n", [Sum]),
    %% Always printed: a tree small enough to finish within a microsecond
    %% printed no rate at all, which the runner reads as a broken run.
    io:format("ns/msg:         ~p~n", [ElapsedNs div TotalActors]),
    io:format("Throughput:     ~.2f M msg/sec~n", [TotalActors * 1000.0 / ElapsedNs]),
    halt(0).
