-module(thread_ring).
-export([start/0]).

-define(RING_SIZE, 100).

get_num_hops() ->
    case os:getenv("BENCHMARK_MESSAGES") of
        false -> 100000;
        Val -> list_to_integer(Val)
    end.

start() ->
    NumHops = get_num_hops(),
    io:format("=== Erlang Thread Ring Benchmark ===~n"),
    io:format("Ring size: ~p, Hops: ~p~n~n", [?RING_SIZE, NumHops]),

    % The clock starts before the ring exists, as in every language here
    % (FAIRNESS.md, rule 5); monotonic_time is the clock for benchmarks.
    Start = erlang:monotonic_time(nanosecond),

    % Create ring of processes
    Parent = self(),
    First = spawn(fun() -> ring_node(undefined, Parent, 0) end),
    {Last, Nodes} = create_ring(First, ?RING_SIZE - 1, Parent, [First]),

    % Close the ring: Last -> First (not First -> Last!)
    Last ! {set_next, First},

    % Send initial token
    First ! {token, NumHops},

    % Wait for completion
    receive
        done ->
            End = erlang:monotonic_time(nanosecond),
            ElapsedNs = End - Start,
            ElapsedSec = ElapsedNs / 1000000000.0,

            % The receipts summed over the ring, the checksum.
            Receipts = collect_receipts(Nodes, 0),

            NsPerMsg = ElapsedNs / (NumHops + 1),
            MsgPerSec = (NumHops + 1) / ElapsedSec,
            io:format("Checksum: ~p~n", [Receipts]),
            io:format("ns/msg:         ~.2f~n", [NsPerMsg]),
            io:format("Throughput:     ~.2f M msg/sec~n", [MsgPerSec / 1000000])
    after 60000 ->
        io:format("Timeout!~n"),
        halt(1)
    end,

    halt(0).

create_ring(Prev, 0, _Parent, Nodes) ->
    {Prev, Nodes};
create_ring(Prev, N, Parent, Nodes) ->
    Next = spawn(fun() -> ring_node(Prev, Parent, 0) end),
    Prev ! {set_next, Next},
    create_ring(Next, N - 1, Parent, [Next | Nodes]).

collect_receipts([], Acc) -> Acc;
collect_receipts([Node | Rest], Acc) ->
    Node ! {report, self()},
    receive
        {count, Count} -> collect_receipts(Rest, Acc + Count)
    end.

ring_node(Next, Parent, Received) ->
    receive
        {set_next, NewNext} ->
            ring_node(NewNext, Parent, Received);
        {token, 0} ->
            % Token exhausted: tell the parent, and stay to report the count
            Parent ! done,
            ring_node(Next, Parent, Received + 1);
        {token, Hops} ->
            Next ! {token, Hops - 1},
            ring_node(Next, Parent, Received + 1);
        {report, From} ->
            From ! {count, Received}
    end.
