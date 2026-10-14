# Ownership grid

Stage 1 of the ownership design (`docs/design/ownership-model.md`, PR
#2883): a generated test per value kind, place and transfer, which measures
whether Aether gets ownership right for that shape today. It replaces
probing by hand and filing one issue per shape: a new ownership finding
becomes a cell, and the stages of the design close cells.

## What a cell is

A cell is one value **kind** (a fresh string, a `string?`, a closure that
captures a fresh string, an `fn[2]`, a struct owning a string, a
`(string, int)` tuple, a `string[2]`, a `Doc[2]`, a named function used as a
closure, the error slot of an `int!`) held in one **place** (a local, a local
rebound in a loop, a struct field, an array element, a tuple slot, an
optional, a module `var`, a closure's capture or cell, a list or map, actor
state, a message field, a `ptr` slot, a part of a parameter, a temporary)
and moved by one **transfer** (store and leave, overwrite, `break`/`continue`,
early `return`, a caught panic, a reader, a keeper, a freer, return, hand
back, `defer`, alias, store into a global, capture). Its id is
`<kind>-<place>-<transfer>`, `K1-P5-T7` for instance, and the tables in
`gen.py` (`KINDS`, `PLACES`, `TRANSFERS`) say what each code is.

A fourth axis is the **producer**: which std C function made the string.
`docs/design/ownership-r1-inventory.md` classes every std function that
returns a string by what it returns (A, a counted string the caller owns;
A~, a counted string another holder keeps; B, a plain malloc'd buffer; C, a
pointer into memory C keeps; D, a literal; a tuple carrying one of those).
The kinds `SA1` to `ST2` take the string of one real function per class (two
where the class is large or mixed: `string.replace`, `string.concat_wrapped`,
`string_list_get`, `path.join`, `path.rel`, `string.seq_head`,
`string.to_cstr`, `path.separator`, `http.mime_type`, `fs.read_binary`,
`fs.realpath`) through the main places (local, field, element, module `var`,
capture, list, message) and transfers (scope exit, overwrite, caught panic,
keep, return, alias), so a change to how the producers return their strings
shows in the grid.

Each cell is a standalone program, written by `gen.py` into
`build/ownership_grid/cells/<id>.ae`. It runs the shape in a function called
100 times per round, checks every value it reads against the one it stored
(the expected values come from the construction), and measures
`mem.steady_growth` over rounds of 100 calls. When a cell fails, its program
is the reproducer: `build/ae run build/ownership_grid/cells/k1_p5_t7.ae`.

There is no garbage collector to wait for: a cell passes only when each
round of 100 calls gives back everything it took before the next round
reads the heap. A value freed only at program exit, or freed a round late by
a sweep (an actor ended later, say), is growth, so it is a LEAK. A cell that
ends actors ends them itself (`scheduler_reclaim_released`) before it reads
the heap.

`run.py` builds each cell twice: as it is, and against `poison_alloc.c`
(linked with `-Wl,--wrap=free,--wrap=realloc`), which fills every freed
block with 0xDD, never hands it back to the heap, and stops the program on a
second free. To rerun one by hand:

    AE_CC="gcc -Wl,--wrap=free,--wrap=realloc" build/ae build \
        build/ownership_grid/cells/k1_p5_t7.ae --extra tests/ownership_grid/poison_alloc.c -o p.exe
    ./p.exe

The poisoning build needs a gcc/ld linker: macOS's linker has no `--wrap`,
so there it is skipped and no cell is UAF. The leak measurement needs an
exact heap count (`mem.heap_in_use_exact()`: Windows, or a sanitizer
allocator); elsewhere a cell prints that growth was not measured, and no cell
is LEAK.

Not every combination is meaningful (an array cannot hold an array, a
module `var` cannot hold an array, only a string has a free a callee can
call, a cell that is the same program as another). `gen.py` decides, and
`python3 tests/ownership_grid/gen.py --skips` lists every skipped
combination with its reason; the report lists them grouped by reason.

## Statuses

| status | meaning |
|---|---|
| OK | every value right, no growth, nothing under the poisoning allocator |
| LEAK | `mem.steady_growth` is not 0; the report gives the bytes per 100 calls |
| UAF | under the poisoning allocator: a double free, a crash, or a value wrong only there (a read of a freed block) |
| WRONG | a value is wrong without the poisoning allocator |
| NOCOMPILE | aetherc refused the program (NC-a) or the generated C did not compile (NC-c); the first error is kept |
| CRASH | the program died without the poisoning allocator, and nothing under it pins a memory error |
| TIMEOUT | the program did not finish in 120 s |

## Running it

    make ownership-grid            # every cell, the default C path
    make ownership-grid-check      # the same, then compare with baseline.txt
    make ownership-grid OWNERSHIP_GRID_ARGS="--mode both"     # also -DAETHER_GCC_COMPAT=0
    make ownership-grid OWNERSHIP_GRID_ARGS="--only 'K3-*,K4-P5-*'"

`NPROC` bounds the parallel cells. The output is `build/ownership_grid/`:
`report.md` (counts overall, per kind and per place; the total LEAK, the
bytes per 100 calls summed over every LEAK cell, which is the number to
drive to zero; the ten worst cells; the producers by class; the std modules
the cells reach and the ones none reaches; the cells the PR #2883 comments
found by hand; one matrix per kind, places by transfers; every cell that is
not OK with its first error or wrong value; the skipped combinations),
`report.csv` (a row per cell and C path), `results.json` (what
`run.py --report-only` rewrites the report from), `cells/` (the programs)
and `<path>/bin/` (each build's and run's log; the binaries too with
`--keep-bins`, deleted otherwise since they come to 4 GB). Builds go through
a cache of the grid's own, `build/ownership_grid/cache`, capped at 1 GB.

## The baseline and the check

`baseline.txt` holds every cell's status on main: `<cell> <default C path>
<-DAETHER_GCC_COMPAT=0 path, or ->`. `make ownership-grid-check` fails when
a cell is worse than its baseline: OK became anything else, LEAK became
NOCOMPILE, TIMEOUT, CRASH, WRONG or UAF, NOCOMPILE became one of the last
four. A cell that got worse is run again before it counts, so one unlucky
heap reading does not fail the check. Changes within a tier (UAF to WRONG, a
LEAK of another size) are listed but do not fail it, and nor do cells that
got better: those are listed so the baseline can be updated.

A fix that makes cells better updates the baseline in the same PR:

    make ownership-grid-check OWNERSHIP_GRID_ARGS="--mode both --update-baseline"

and the diff of `baseline.txt` is the list of shapes the fix closed. A fix
that makes any cell worse fails the check, whatever it was fixing, and the
check then writes no baseline (a regression is recorded only on purpose, by
`make ownership-grid OWNERSHIP_GRID_ARGS=--update-baseline`, without the
check). With `--only`, `--update-baseline` rewrites only the lines of the
cells it ran.

The baseline was measured on Windows (MinGW gcc), where the heap count is
exact. A few cells move between UAF and WRONG from run to run (whether the
freed block was reused before the read), which the check ignores; an actor
cell can read the heap a little early under heavy parallel load, which is
why a worse cell is run again before it fails the check.

## Adding a cell

A new ownership finding is a new kind, place or transfer in `gen.py` (or a
case the generator skipped that is meaningful after all), not a test of its
own. Add it, run `make ownership-grid-check`, and add its line to the
baseline with the status it has on main.
