-module(ping_pong).
-export([start/0, ping/4, pong/2]).

get_messages() ->
    case os:getenv("BENCHMARK_MESSAGES") of
        false -> 100000;
        Val -> list_to_integer(Val)
    end.

%% Returns the sum of the values ping got back, which the runner checks.
ping(Pong, N, _I, Sum) when N =< 0 ->
    Pong ! done,
    Sum;
ping(Pong, N, I, Sum) ->
    Pong ! {ping, self(), I},
    receive
        {pong, Value} ->
            % Validate received value matches what was sent
            if
                Value =/= I ->
                    io:format(standard_error, "Ping validation error: expected ~p, got ~p~n", [I, Value]);
                true -> ok
            end,
            ping(Pong, N - 1, I + 1, Sum + Value)
    end.

pong(Expected, Messages) when Expected >= Messages ->
    receive
        done -> done
    end;
pong(Expected, Messages) ->
    receive
        {ping, Ping, Value} ->
            % Validate received value matches expected sequence
            if
                Value =/= Expected ->
                    io:format(standard_error, "Pong validation error: expected ~p, got ~p~n", [Expected, Value]);
                true -> ok
            end,
            % Echo back the EXACT value received
            Ping ! {pong, Value},
            pong(Expected + 1, Messages)
    end.

start() ->
    Messages = get_messages(),
    io:format("=== Erlang Ping-Pong Benchmark ===~n"),
    io:format("Messages: ~p~n~n", [Messages]),

    Parent = self(),

    % monotonic_time is the correct clock for benchmarks per the Erlang docs.
    % Process creation is inside the timed region, as in every other language here.
    Start = erlang:monotonic_time(nanosecond),

    Pong = spawn(fun() -> pong(0, Messages) end),

    % Run ping-pong - spawn returns the PID, we need to link it to receive done
    spawn_link(fun() ->
        Sum = ping(Pong, Messages, 0, 0),
        Parent ! {done, Sum}
    end),

    % Wait for completion
    Checksum = receive
        {done, S} -> S
    after 60000 ->
        io:format("Timeout!~n"),
        halt(1)
    end,

    % Calculate metrics
    End = erlang:monotonic_time(nanosecond),
    ElapsedNs = End - Start,
    ElapsedSec = ElapsedNs / 1000000000.0,

    NsPerMsg = ElapsedNs / Messages,
    MsgPerSec = Messages / ElapsedSec,

    io:format("Checksum: ~p~n", [Checksum]),
    io:format("ns/msg:         ~.2f~n", [NsPerMsg]),
    io:format("Throughput:     ~.2f M msg/sec~n", [MsgPerSec / 1000000]),

    halt(0).
