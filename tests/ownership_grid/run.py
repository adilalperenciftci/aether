#!/usr/bin/env python3
"""Runner of the ownership grid: generate, build, run, classify, report.

    python tests/ownership_grid/run.py [options]

Every cell gen.py makes is written to build/ownership_grid/cells/, built
with build/ae once, linking poison_alloc.c (-Wl,--wrap=free,--wrap=realloc
and the runtime's NUMA frees), run twice (as it is, and with
OWNERSHIP_GRID_POISON=1, which poisons every freed block), and given one
status:

  OK          every value right, no growth, nothing under the poisoning allocator
  UNMEASURED  values right and nothing under the poisoning allocator, but the
              heap count is not exact here (mem.heap_in_use_exact), so growth
              was not measured
  LEAK        mem.steady_growth is not 0; the size kept is the median of three
              runs, in bytes per 100 calls
  INCOMPLETE  the poisoned run did not finish (a timeout) or could not be built,
              so the use-after-free check did not happen
  NOCOMPILE   aetherc refused the program, or the C did not compile (which one
              is kept)
  TIMEOUT     the build or the plain run did not finish
  CRASH       the plain run died, and the poisoned run pins no memory error
  WRONG       a value is wrong in the plain run
  UAF         the poisoned run stopped on a double free, crashed (an access
              violation, heap corruption), or read a wrong value
  HARNESS     the runner itself failed on the cell twice (never a finding: the
              check fails and says so)

Each cell also has a TARGET, the status the approved design wants (gen.py):
OK, or REFUSED for a function that frees a parameter it borrows. The report
says how far each cell is from it.

Options:
  --mode gcc|nogcc|both  the C path: gcc is the default build, nogcc builds with
                         AE_CC="<cc> -DAETHER_GCC_COMPAT=0" (default gcc)
  --jobs N               parallel cells (default NPROC, else the CPU count / 2)
  --only PAT[,PAT]       only cells whose id matches one of the fnmatch patterns
  --shard k/n            only shard k of n (k may be a list, 2,3/3), as CI splits the grid;
                         OWNERSHIP_GRID_SHARD sets it too
  --check                compare with baseline.txt; exit 1 when a cell got worse or a
                         baseline cell is no longer generated, 2 on a harness failure
  --update-baseline      write baseline.txt from this run (an --only run updates its cells)
  --no-shim              build without the poisoning allocator (no UAF column)
  --keep-bins            keep each cell's binary (deleted after its runs otherwise)
  --report-only          rewrite report.md and report.csv from <out>/results.json
  --out DIR              output directory (default build/ownership_grid)

OWNERSHIP_GRID_FAULT=<cell id> makes the runner fail on that cell (a test of
the harness-failure path: tests/ownership_grid/test_runner.py).

Writes <out>/report.md, <out>/report.csv and <out>/results.json.
"""

import argparse
import concurrent.futures
import csv
import datetime
import fnmatch
import json
import os
import platform
import re
import statistics
import subprocess
import sys
import threading
import time
import traceback

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)
import gen  # noqa: E402

WINDOWS = os.name == "nt"
EXE = ".exe" if WINDOWS else ""
AE = os.path.join(ROOT, "build", "ae" + EXE)
SHIM = os.path.join(HERE, "poison_alloc.c")
BASELINE = os.path.join(HERE, "baseline.txt")
WRAPS = "-Wl,--wrap=free,--wrap=realloc,--wrap=aether_numa_free,--wrap=aether_numa_free_aligned"

BUILD_TIMEOUT = 600
RUN_TIMEOUT = 120
EXIT_WRONG, EXIT_LEAK, EXIT_POISON, EXIT_POISON_HARNESS = 12, 13, 86, 87

STATUSES = ["OK", "UNMEASURED", "LEAK", "INCOMPLETE", "NOCOMPILE", "TIMEOUT", "CRASH", "WRONG", "UAF",
            "HARNESS"]
# How bad a status is, for the check: a move to a higher tier is a regression.
# UNMEASURED is compared apart (see compare); HARNESS fails the check anyway.
TIER = {"OK": 0, "UNMEASURED": 0, "LEAK": 1, "INCOMPLETE": 2, "NOCOMPILE": 2, "TIMEOUT": 3, "CRASH": 3,
        "WRONG": 3, "UAF": 3, "HARNESS": 4}
# The order the worst cells are listed in.
SEVERITY = {"HARNESS": -1, "UAF": 0, "WRONG": 1, "CRASH": 2, "TIMEOUT": 3, "INCOMPLETE": 4, "NOCOMPILE": 5,
            "LEAK": 6, "UNMEASURED": 7, "OK": 8}

# A LEAK cell is worse than its baseline when it leaks more than twice as
# much and more than this many bytes per 100 calls more. Measured: the same
# cell's growth moved by up to about 1 KB per 100 calls between runs (a few
# allocator blocks), never by a factor of two; a real new leak in a shape is
# at least one string or environment per call, 1.8 KB or more per 100 calls.
LEAK_NOISE_BYTES = 2048

WIN_CODES = {
    0xC0000005: "access violation",
    0xC00000FD: "stack overflow",
    0xC0000374: "heap corruption",
    0xC0000409: "stack buffer overrun / fast fail",
    0xC000001D: "illegal instruction",
    0xC0000094: "integer divide by zero",
    0x80000003: "breakpoint",
    3: "abort()",
}


def no_error_dialogs():
    """Children inherit the error mode: no Windows Error Reporting dialog for
    a crashing cell, which would hang the run."""
    if WINDOWS:
        import ctypes
        SEM_FAILCRITICALERRORS, SEM_NOGPFAULTERRORBOX, SEM_NOOPENFILEERRORBOX = 0x0001, 0x0002, 0x8000
        ctypes.windll.kernel32.SetErrorMode(SEM_FAILCRITICALERRORS | SEM_NOGPFAULTERRORBOX | SEM_NOOPENFILEERRORBOX)


def kill_tree(proc):
    try:
        if WINDOWS:
            subprocess.run(["taskkill", "/T", "/F", "/PID", str(proc.pid)],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        else:
            proc.kill()
    except OSError:
        pass


def run_cmd(argv, env, cwd, timeout):
    """(returncode or None on timeout, combined output, seconds)."""
    t0 = time.time()
    flags = 0
    if WINDOWS:
        flags = 0x00000200  # CREATE_NEW_PROCESS_GROUP
    proc = subprocess.Popen(argv, cwd=cwd, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                            creationflags=flags)
    try:
        out, _ = proc.communicate(timeout=timeout)
        rc = proc.returncode
    except subprocess.TimeoutExpired:
        kill_tree(proc)
        try:
            out, _ = proc.communicate(timeout=30)
        except subprocess.TimeoutExpired:
            out = b""
        rc = None
    return rc, out.decode("utf-8", "replace"), time.time() - t0


# Files that could not be removed during the run (Windows holds a file a
# process is still exiting from, or that Defender is scanning); retried at
# the end of the run, and reported, never a failure.
LEFT_FILES = []
LEFT_LOCK = threading.Lock()


def remove_quietly(path, tries=8):
    """Removes path, retrying with a short backoff; False if it is still there."""
    delay = 0.05
    for _ in range(tries):
        try:
            if os.path.exists(path):
                os.remove(path)
            return True
        except OSError:
            time.sleep(delay)
            delay = min(delay * 2, 1.0)
    with LEFT_LOCK:
        LEFT_FILES.append(path)
    return False


def command_output(argv):
    """A command's first line of output, or "" when it cannot run (a native
    Python under MSYS2 make, for one, finds no `git` on its PATH)."""
    try:
        return subprocess.run(argv, capture_output=True, text=True).stdout.strip()
    except OSError:
        return ""


def compiler_version():
    return command_output([os.path.join(ROOT, "build", "aetherc" + EXE), "--version"]) or "aetherc"


def git_head(fmt):
    return command_output(["git", "-C", ROOT, "log", "-1", "--format=" + fmt]) or "an unknown commit"


def describe_exit(rc):
    if rc is None:
        return "timeout"
    code = rc & 0xFFFFFFFF if WINDOWS else rc
    if WINDOWS and code in WIN_CODES:
        return "exit 0x%X (%s)" % (code, WIN_CODES[code])
    if not WINDOWS and rc < 0:
        return "signal %d" % -rc
    return "exit %d" % rc


ERROR_LINE = re.compile(r"error", re.I)
C_ERROR = re.compile(r"(\.c|\.h|\.ae):\d+(:\d+)?: (fatal )?error|undefined reference|ld returned|collect2")
AETHERC_ERROR = re.compile(r"error\[E\d+\]|Type checking failed|aborting: \d+ error|^error: ", re.M)
SHIM_ERROR = re.compile(r"__wrap_|__real_|poison_alloc")
PATH_PREFIX = re.compile(r"(?:[A-Za-z]:)?[\\/][^\s:]*[\\/](?=[^\\/\s:]+\.(?:ae|c|h):)")


def compile_error(log):
    """('aetherc' | 'C', first error line), file names without their directory."""
    lines = [PATH_PREFIX.sub("", ln.strip()) for ln in log.splitlines()]
    first_c = next((ln for ln in lines if C_ERROR.search(ln)), None)
    first_a = next((ln for ln in lines if AETHERC_ERROR.search(ln)), None)
    if first_a and not first_c:
        return "aetherc", first_a
    if first_c:
        return "C", first_c
    first = next((ln for ln in lines if ERROR_LINE.search(ln)), lines[-1] if lines else "")
    return "aetherc", first


class Mode:
    def __init__(self, name):
        self.name = name
        base = os.environ.get("AE_CC") or os.environ.get("CC") or ("gcc" if WINDOWS else "cc")
        self.cc = base + (" -DAETHER_GCC_COMPAT=0" if name == "nogcc" else "")
        self.env_cc = None if (name == "gcc" and not os.environ.get("AE_CC")) else self.cc
        self.shim_cc = self.cc + " " + WRAPS


def shim_supported():
    return platform.system() != "Darwin"


def build_env(out, cc):
    env = dict(os.environ)
    # A cache of the grid's own, bounded, so its thousands of programs neither
    # evict the user's builds from ~/.aether/cache nor fill the disk.
    env["AETHER_CACHE_DIR"] = os.path.join(out, "cache")
    env.setdefault("AETHER_CACHE_MAX_MB", "1024")
    if cc is None:
        env.pop("AE_CC", None)
    else:
        env["AE_CC"] = cc
    return env


KEEP_BINS = False


def new_result(cell, mode, src):
    return {"id": cell.id, "kind": cell.kind, "place": cell.place, "transfer": cell.transfer,
            "target": cell.target, "file": os.path.relpath(src, ROOT).replace("\\", "/"), "mode": mode.name,
            "status": "", "detail": "", "leak": "", "run": "", "shim": "", "build_s": 0.0, "run_s": 0.0}


def build(cell, mode, out, src, stem, use_shim, res):
    """Builds the cell; (exe, None) or (None, (status, detail))."""
    exe = stem + EXE
    if not remove_quietly(exe):
        # A binary from an earlier run that Windows still holds: build beside it.
        exe = "%s.%d%s" % (stem, os.getpid(), EXE)
        remove_quietly(exe)
    argv = [AE, "build", src, "-o", exe]
    if use_shim:
        argv[3:3] = ["--extra", SHIM]
    rc, log, secs = run_cmd(argv, build_env(out, mode.shim_cc if use_shim else mode.env_cc),
                            os.path.dirname(stem), BUILD_TIMEOUT)
    res["build_s"] += secs
    with open(stem + ".build.log", "w", encoding="utf-8") as f:
        f.write(log)
    if rc is None:
        return None, ("TIMEOUT", "the build did not finish in %d s" % BUILD_TIMEOUT)
    if rc != 0 or not os.path.exists(exe):
        stage, line = compile_error(log)
        if use_shim and SHIM_ERROR.search(log):
            return None, ("SHIM", "the build with poison_alloc.c failed: " + line[:200])
        return None, ("NOCOMPILE", "%s: %s" % (stage, line[:300]))
    return exe, None


def run_cell(cell, mode, out, use_shim):
    """Builds one cell under one C path, runs it plain and poisoned; a result dict.

    The one build links poison_alloc.c (where the linker has --wrap), whose
    frees pass through to the C heap unless OWNERSHIP_GRID_POISON is set: the
    plain run measures leaks on the C heap as it is, the poisoned run catches
    double frees and reads of freed blocks."""
    if os.environ.get("OWNERSHIP_GRID_FAULT") == cell.id:
        raise RuntimeError("OWNERSHIP_GRID_FAULT names this cell")
    src = os.path.join(out, "cells", cell.file)
    stem = os.path.join(out, mode.name, "bin", cell.file[:-3])
    res = new_result(cell, mode, src)
    exe, failed = build(cell, mode, out, src, stem, use_shim, res)
    shim_built = use_shim
    if failed and failed[0] == "SHIM":
        # The cell may build without the allocator: run it plain, and say the
        # use-after-free check did not happen.
        shim_note = failed[1]
        shim_built = False
        exe, failed = build(cell, mode, out, src, stem, False, res)
    else:
        shim_note = ""
    if failed:
        res["status"], res["detail"] = failed
        return res
    plain_env = dict(os.environ)
    plain_env.pop("OWNERSHIP_GRID_POISON", None)
    rc, outp, secs = run_cmd([exe], plain_env, os.path.dirname(stem), RUN_TIMEOUT)
    res["run_s"] += secs
    with open(stem + ".run.log", "w", encoding="utf-8") as f:
        f.write(outp)
    plain = classify_run(rc, outp)
    res["run"] = describe_exit(rc)
    if plain[0] == "LEAK":
        # Two more runs: the size kept is the median, steadier than one run.
        sizes = [plain[2]]
        for _ in range(2):
            rc2, outp2, secs2 = run_cmd([exe], plain_env, os.path.dirname(stem), RUN_TIMEOUT)
            res["run_s"] += secs2
            again = classify_run(rc2, outp2)
            if again[0] == "LEAK":
                sizes.append(again[2])
        size = int(statistics.median(sizes))
        plain = ("LEAK", "%d bytes per 100 calls%s" % (size, plain[3]), size, plain[3])
    shim = None
    if shim_built:
        poison_env = dict(plain_env)
        poison_env["OWNERSHIP_GRID_POISON"] = "1"
        src_rc, soutp, ssecs = run_cmd([exe], poison_env, os.path.dirname(stem), RUN_TIMEOUT)
        res["run_s"] += ssecs
        with open(stem + ".p.run.log", "w", encoding="utf-8") as f:
            f.write(soutp)
        res["shim"] = describe_exit(src_rc)
        shim = classify_shim(src_rc, soutp)
    elif use_shim:
        shim = ("NOTRUN", shim_note)
    status, detail = combine(plain, shim)
    res["status"], res["detail"] = status, detail
    if status == "LEAK":
        res["leak"] = str(plain[2])
    if not KEEP_BINS:
        # The program is the reproducer; the binaries come to 2 GB over the grid.
        remove_quietly(exe)
    return res


def run_cell_safely(cell, mode, out, use_shim):
    """run_cell, with any fault of the runner itself caught: the cell is run
    once more, and a second fault makes it HARNESS, which fails the check
    with the fault named, never a traceback that ends the whole run."""
    errors = []
    for _ in range(2):
        try:
            return run_cell(cell, mode, out, use_shim)
        except Exception as e:  # noqa: BLE001, the point is to catch anything
            errors.append("%s: %s" % (type(e).__name__, e))
            last = traceback.format_exc()
    src = os.path.join(out, "cells", cell.file)
    res = new_result(cell, mode, src)
    res["status"] = "HARNESS"
    res["detail"] = "the runner failed on this cell twice: " + "; ".join(errors)
    try:
        with open(os.path.join(out, mode.name, "bin", cell.file[:-3] + ".harness.log"), "w",
                  encoding="utf-8") as f:
            f.write(last)
    except OSError:
        pass
    return res


def first_line(text, prefix):
    for ln in text.splitlines():
        if ln.startswith(prefix):
            return ln.strip()
    return ""


def classify_run(rc, out):
    """(status, detail, leak bytes per 100 calls, note) of the plain run."""
    if rc is None:
        return "TIMEOUT", "no exit within %d s" % RUN_TIMEOUT, 0, ""
    if rc == 0:
        if "growth not measured" in out:
            return "UNMEASURED", "the heap count is not exact here", 0, ""
        return "OK", "", 0, ""
    if rc == EXIT_WRONG:
        return "WRONG", first_line(out, "WRONG:"), 0, ""
    if rc == EXIT_LEAK:
        m = re.search(r"LEAK: (-?\d+) bytes per (\d+) calls", out)
        if not m:
            return "LEAK", "growth not read from the output", 0, ""
        n = int(m.group(1)) * 100 // max(1, int(m.group(2)))
        note = "" if m.group(2) == "100" else " (measured per %s calls)" % m.group(2)
        return "LEAK", "%d bytes per 100 calls%s" % (n, note), abs(n), note
    tail = " / ".join(ln.strip() for ln in out.strip().splitlines()[-2:])
    return "CRASH", "%s%s" % (describe_exit(rc), (": " + tail[:200]) if tail else ""), 0, ""


def classify_shim(rc, out):
    """(kind, detail) of the poisoned run: CLEAN, DOUBLEFREE, CRASH (a memory
    fault), WRONG, OTHER (another end), TIMEOUT or HARNESS."""
    if rc is None:
        return "TIMEOUT", "the poisoned run did not finish in %d s" % RUN_TIMEOUT
    if rc in (0, EXIT_LEAK):  # growth means nothing there: nothing is freed
        return "CLEAN", ""
    if rc == EXIT_POISON:
        return "DOUBLEFREE", first_line(out, "POISON:") or "double free"
    if rc == EXIT_POISON_HARNESS:
        return "HARNESS", first_line(out, "POISON HARNESS:") or "the poisoning allocator failed"
    if rc == EXIT_WRONG:
        return "WRONG", "poisoned: " + first_line(out, "WRONG:")
    if is_memory_fault(rc):
        return "CRASH", "poisoned: " + describe_exit(rc)
    # A stack overflow, a panic's abort or any other end: no evidence of a
    # freed block, so the plain run's status stands.
    return "OTHER", "poisoned: " + describe_exit(rc)


def is_memory_fault(rc):
    """An end that a read or a free of freed memory makes: an access
    violation, heap corruption or a fast fail on Windows; SIGSEGV, SIGBUS or
    glibc's abort on a bad free elsewhere."""
    if WINDOWS:
        return (rc & 0xFFFFFFFF) in (0xC0000005, 0xC0000374, 0xC0000409)
    return rc in (-11, -7, -6)


def combine(plain, shim):
    """One status from the plain run and the poisoned one (None: not built
    with the allocator, by choice or on a platform without --wrap)."""
    st, detail = plain[0], plain[1]
    besides = "" if st in ("OK", "UNMEASURED") else " (plain run: %s %s)" % (st, detail)
    if shim and shim[0] in ("DOUBLEFREE", "CRASH"):
        # A memory error the poisoned run pins outranks what the plain run saw.
        return "UAF", (shim[1] + besides).strip()
    if st in ("WRONG", "CRASH", "TIMEOUT"):
        return st, detail
    if shim and shim[0] == "WRONG":
        return "UAF", shim[1]
    if shim and shim[0] == "HARNESS":
        return "HARNESS", shim[1]
    if shim and shim[0] in ("TIMEOUT", "NOTRUN", "OTHER"):
        return "INCOMPLETE", "the use-after-free check did not run: %s%s" % (shim[1], besides)
    return st, detail


# ---------------------------------------------------------------------------
# Baseline: one line per cell, `<cell> <default path> <nogcc path or ->`, a
# status being OK, LEAK:<bytes per 100 calls>, UAF, ...


def parse_status(tok):
    if tok.startswith("LEAK:"):
        return "LEAK", int(tok[5:])
    return tok, None


def format_status(status, leak):
    if status == "LEAK" and str(leak).lstrip("-").isdigit():
        return "LEAK:%d" % int(leak)
    return status


def read_baseline():
    """{id: {mode: (status, leak bytes or None)}}."""
    base = {}
    if not os.path.exists(BASELINE):
        return base
    with open(BASELINE, encoding="utf-8") as f:
        for ln in f:
            ln = ln.strip()
            if not ln or ln.startswith("#"):
                continue
            parts = ln.split()
            base[parts[0]] = {"gcc": parse_status(parts[1])}
            if len(parts) > 2 and parts[2] != "-":
                base[parts[0]]["nogcc"] = parse_status(parts[2])
    return base


def write_baseline(results, old):
    by = {}
    for r in results:
        by.setdefault(r["id"], {})[r["mode"]] = format_status(r["status"], r["leak"])
    # Every cell the generator makes: this run's status where it ran (an
    # --only run updates its own cells), the old line's elsewhere.
    ids = [c.id for c in gen.cells() if c.id in by or c.id in old]
    with open(BASELINE, "w", encoding="utf-8", newline="\n") as f:
        f.write("# Ownership grid baseline: each cell's status on main (tests/ownership_grid/README.md).\n")
        f.write("# <cell> <status on the default C path> <status with -DAETHER_GCC_COMPAT=0, or ->\n")
        f.write("# LEAK:<n> is n bytes per 100 calls. `make ownership-grid-check` fails when a cell gets\n")
        f.write("# worse than this, or leaks more than twice as much and more than %d bytes more.\n"
                % LEAK_NOISE_BYTES)
        f.write("# Measured at %s (%s) on %s.\n" % (git_head("%h"), compiler_version(), platform.system()))
        for cid in ids:
            cols = []
            for mode in ("gcc", "nogcc"):
                got = by.get(cid, {}).get(mode)
                if got is None and mode in old.get(cid, {}):
                    got = format_status(*old[cid][mode])
                cols.append(got or "-")
            f.write("%s %s %s\n" % (cid, cols[0], cols[1]))


def verdict(r, b):
    """'worse', 'better', 'changed' or 'same' for result r against baseline b."""
    bst, bleak = b
    st = r["status"]
    if st == "HARNESS":
        return "worse"
    if st == "UNMEASURED":
        # Values and use after free were checked, growth was not.
        if bst in ("OK", "LEAK", "UNMEASURED"):
            return "same"
        return "better" if TIER[bst] > 0 else "same"
    if TIER[st] > TIER[bst]:
        return "worse"
    if TIER[st] < TIER[bst]:
        return "better"
    if st == "LEAK" and bleak is not None and r["leak"] not in ("", None):
        now = int(r["leak"])
        if now > 2 * bleak and now - bleak > LEAK_NOISE_BYTES:
            return "worse"
        if bleak > 2 * now and bleak - now > LEAK_NOISE_BYTES:
            return "better"
        return "same"
    return "changed" if st != bst else "same"


def compare(results, base):
    worse, better, changed, new = [], [], [], []
    for r in results:
        b = base.get(r["id"], {}).get(r["mode"])
        if b is None:
            new.append(r)
            continue
        v = verdict(r, b)
        if v == "worse":
            worse.append((r, b))
        elif v == "better":
            better.append((r, b))
        elif v == "changed":
            changed.append((r, b))
    return worse, better, changed, new


def at_target(r):
    if r["target"] == "REFUSED":
        return r["status"] == "NOCOMPILE" and r["detail"].startswith("aetherc")
    return r["status"] == "OK"


# ---------------------------------------------------------------------------
# Report

ABBR = {"OK": "OK", "UNMEASURED": "UNM", "LEAK": "LEAK", "INCOMPLETE": "INC", "UAF": "**UAF**",
        "WRONG": "**WRONG**", "CRASH": "**CRASH**", "TIMEOUT": "TIME", "NOCOMPILE": "NC", "HARNESS": "**HARNESS**"}


def cell_mark(rs):
    marks = []
    for r in rs:
        s = r["status"]
        if s == "NOCOMPILE":
            m = "NC-c" if r["detail"].startswith("C:") else "NC-a"
        else:
            m = ABBR[s]
        if r.get("target") == "REFUSED":
            m += " (R)"
        marks.append(m)
    return "/".join(marks)


def leak_total(rows):
    """Bytes per 100 calls summed over the LEAK cells (each the median of three runs)."""
    return sum(int(r["leak"]) for r in rows if r["status"] == "LEAK" and str(r["leak"]).lstrip("-").isdigit())


def std_modules():
    """{module: set of extern names} for every std/**/module.ae."""
    mods = {}
    std = os.path.join(ROOT, "std")
    for dirpath, _, files in os.walk(std):
        if "module.ae" in files:
            mod = "std." + os.path.relpath(dirpath, std).replace(os.sep, ".")
            names = set()
            with open(os.path.join(dirpath, "module.ae"), encoding="utf-8", errors="replace") as f:
                for ln in f:
                    m = re.match(r"\s*extern\s+([A-Za-z_]\w*)\s*\(", ln)
                    if m:
                        names.add(m.group(1))
            mods[mod] = names
    return mods


def modules_exercised(results):
    mods = std_modules()
    by_name = {}
    for mod, names in mods.items():
        for n in names:
            by_name.setdefault(n, mod)
    hits = {}
    files = sorted({r["file"] for r in results})
    for rel in files:
        path = os.path.join(ROOT, rel)
        if not os.path.exists(path):
            continue
        seen = set()
        with open(path, encoding="utf-8") as f:
            for ln in f:
                m = re.match(r"import (std\.[\w.]+)", ln)
                if m:
                    seen.add(m.group(1))
                m = re.match(r"extern ([A-Za-z_]\w*)\(", ln)
                if m and m.group(1) in by_name and m.group(1) != "exit":
                    seen.add(by_name[m.group(1)])
        for mod in seen:
            hits[mod] = hits.get(mod, 0) + 1
    used = sorted(hits.items(), key=lambda kv: (-kv[1], kv[0]))
    unused = sorted(m for m in mods if m not in hits)
    return used, unused


def counts(rows):
    c = {s: 0 for s in STATUSES}
    for r in rows:
        c[r["status"]] += 1
    return c


def present_statuses(rows):
    c = counts(rows)
    return [s for s in STATUSES if c[s] or s in ("OK", "LEAK", "UAF", "WRONG")]


def write_report(out, results, modes, wall, njobs, check_text=None, left=0):
    order = {c.id: i for i, c in enumerate(gen.cells())}
    results = sorted(results, key=lambda r: (order.get(r["id"], 0), r["mode"]))
    by_id = {}
    for r in results:
        by_id.setdefault(r["id"], []).append(r)
    ncells = len(by_id)
    L = []
    L.append("# Ownership grid report")
    L.append("")
    L.append("Generated by `tests/ownership_grid/run.py` on %s, %s, at `%s` (%s)."
             % (datetime.date.today().isoformat(), compiler_version(), git_head("%h %s"), platform.platform()))
    L.append("")
    L.append("%d cells, C path%s: %s. %d combinations skipped (listed at the end), and %d combinations of a "
             "producer kind with a place or transfer outside its axis not generated. Wall time %.0f s with %d jobs, "
             "%.1f cells per minute (all C paths)."
             % (ncells, "s" if len(modes) > 1 else "", ", ".join(m.name for m in modes), len(gen.skipped()),
                gen.PRODUCER_NOT_CROSSED, wall, njobs, ncells * len(modes) * 60.0 / max(wall, 1)))
    if not shim_supported():
        L.append("")
        L.append("The poisoning allocator was not built: this linker has no `--wrap` (macOS), so no cell is UAF here.")
    if any(r["status"] == "UNMEASURED" for r in results):
        L.append("")
        L.append("**The heap count is not exact on this platform: growth was not measured, so this run checks "
                 "values and use after free only.**")
    if left:
        L.append("")
        L.append("%d binaries could not be removed (Windows still held them); they are left in `<path>/bin/`." % left)
    L.append("")
    L.append("Statuses: OK; UNM (UNMEASURED: growth not measured here); LEAK (mem.steady_growth is not 0, sized by "
             "the median of three runs); INC (INCOMPLETE: the use-after-free check did not run); NC-a / NC-c "
             "(NOCOMPILE: aetherc refused it / the C did not compile); TIME (TIMEOUT); CRASH; WRONG; UAF; HARNESS "
             "(the runner failed). `(R)` marks a cell whose target is REFUSED. Where two C paths ran, a cell shows "
             "`<default>/<-DAETHER_GCC_COMPAT=0>`.")
    if check_text:
        L.append("")
        L.append("## Check against baseline.txt")
        L.append("")
        L += check_text
    L.append("")
    L.append("## Counts")
    L.append("")
    for m in modes:
        rows = [r for r in results if r["mode"] == m.name]
        c = counts(rows)
        L.append("**%s** (%d cells): " % (m.name, len(rows)) +
                 ", ".join("%s %d" % (s, c[s]) for s in STATUSES if c[s] or s in ("OK", "LEAK", "UAF", "WRONG")))
        L.append("")
        L.append("**Total LEAK on the %s path: %d bytes per 100 calls**, summed over every LEAK cell, each the median "
                 "of three runs (the number to drive to zero)." % (m.name, leak_total(rows)))
        L.append("")
        off = [r for r in rows if not at_target(r)]
        L.append("**Cells not at their target on the %s path: %d of %d** (the target is OK for %d cells and REFUSED "
                 "for %d)." % (m.name, len(off), len(rows), sum(r["target"] == "OK" for r in rows),
                               sum(r["target"] == "REFUSED" for r in rows)))
        L.append("")
    m0 = modes[0].name
    rows0 = [r for r in results if r["mode"] == m0]
    cols = present_statuses(rows0)
    for title, key in (("kind", "kind"), ("place", "place")):
        L.append("By %s (%s path):" % (title, m0))
        L.append("")
        L.append("| %s | cells | %s | not at target |" % (title, " | ".join(cols)))
        L.append("|---|---|%s|---|" % "|".join("---" for _ in cols))
        present = {r[key] for r in rows0}
        canon = ([k.id for k in gen.KINDS] + ["KE"]) if key == "kind" else [p for p, _ in gen.PLACES]
        keys = [k for k in canon if k in present] + sorted(present - set(canon))
        for k in keys:
            sub = [r for r in rows0 if r[key] == k]
            c = counts(sub)
            L.append("| %s | %d | %s | %d |" % (k, len(sub), " | ".join(str(c[s]) if c[s] else "" for s in cols),
                                                 sum(not at_target(r) for r in sub)))
        L.append("")
    # Distance from target.
    L.append("## Distance from the target (%s path)" % m0)
    L.append("")
    L.append("The target is the status the approved design wants: OK, or REFUSED where a function frees a value it "
             "borrows (a parameter), which the checker will refuse in stage 4. Cells by status today and target:")
    L.append("")
    L.append("| target | %s |" % " | ".join(cols))
    L.append("|---|%s|" % "|".join("---" for _ in cols))
    for tgt in ("OK", "REFUSED"):
        sub = [r for r in rows0 if r["target"] == tgt]
        c = counts(sub)
        L.append("| %s (%d) | %s |" % (tgt, len(sub), " | ".join(str(c[s]) if c[s] else "" for s in cols)))
    L.append("")
    # Worst cells.
    L.append("## Worst cells (%s path)" % m0)
    L.append("")
    bad = [r for r in rows0 if r["status"] != "OK"]
    bad.sort(key=lambda r: (SEVERITY[r["status"]], -int(r["leak"] or 0), order.get(r["id"], 0)))
    for r in bad[:10]:
        L.append("- `%s` %s: %s (`%s`)" % (r["id"], r["status"], r["detail"] or "-", r["file"]))
    L.append("")
    # Producers.
    L.append("## Producers (the R1 inventory's classes)")
    L.append("")
    L.append("Each producer kind takes the string one real std C function makes through the places %s and the "
             "transfers %s." % (", ".join(gen.PRODUCER_PLACES), ", ".join(gen.PRODUCER_TRANSFERS)))
    L.append("")
    L.append("| kind | class | C function | module | cells | %s | LEAK bytes |" % " | ".join(cols))
    L.append("|---|---|---|---|---|%s|---|" % "|".join("---" for _ in cols))
    for k in gen.PRODUCERS:
        sub = [r for r in rows0 if r["kind"] == k.id]
        c = counts(sub)
        L.append("| %s | %s | `%s` | %s | %d | %s | %d |" % (k.id, k.pclass, k.function, k.module, len(sub),
                                                         " | ".join(str(c[s]) if c[s] else "" for s in cols),
                                                         leak_total(sub)))
    L.append("")
    # Modules.
    used, unused = modules_exercised(results)
    L.append("## Std modules the grid exercises")
    L.append("")
    L.append("Imported by a cell, or reached through an extern a cell declares (cells per module): " +
             ", ".join("%s (%d)" % (m, n) for m, n in used) + ".")
    L.append("")
    L.append("Std modules no cell reaches (the gaps): " + (", ".join(unused) if unused else "none") + ".")
    L.append("")
    # The shapes found by hand before the grid existed.
    L.append("## Cells the comments on PR #2883 found by hand")
    L.append("")
    L.append("| cell | status | the comment's finding |")
    L.append("|---|---|---|")
    for cid, what in gen.FOUND.items():
        if cid in by_id:
            got = " / ".join(("%s %s" % (r["status"], r["detail"])).strip() for r in by_id[cid])
            L.append("| %s | %s | %s |" % (cid, got.replace("|", "\\|"), what))
    L.append("")
    # Matrices.
    L.append("## Matrices: places x transfers, one per kind")
    L.append("")
    tcols = [t for t, _ in gen.TRANSFERS] + [t for t, _ in gen.KE_TRANSFERS]
    kinds = []
    for c in gen.cells():
        if c.kind not in kinds and c.id in by_id:
            kinds.append(c.kind)
    for k in kinds:
        kc = [c for c in gen.cells() if c.kind == k and c.id in by_id]
        tc = [t for t in tcols if any(c.transfer == t for c in kc)]
        pls = [p for p, _ in gen.PLACES if any(c.place == p for c in kc)]
        L.append("### %s %s" % (k, gen.kind_title(k)))
        L.append("")
        L.append("| place | %s |" % " | ".join(tc))
        L.append("|---|%s|" % "|".join("---" for _ in tc))
        for p in pls:
            row = []
            for t in tc:
                cid = "%s-%s-%s" % (k, p, t)
                row.append(cell_mark(by_id[cid]) if cid in by_id else "")
            L.append("| %s %s | %s |" % (p, gen.PLACE_TITLE.get(p, ""), " | ".join(row)))
        L.append("")
    L.append("Transfers: " + "; ".join("%s %s" % (t, d) for t, d in gen.TRANSFERS + gen.KE_TRANSFERS) + ".")
    L.append("")
    # Every cell not at target.
    L.append("## Every cell that is not at its target")
    L.append("")
    L.append("| cell | path | status | target | detail | program |")
    L.append("|---|---|---|---|---|---|")
    for r in sorted([r for r in results if not at_target(r)],
                    key=lambda r: (SEVERITY[r["status"]], order.get(r["id"], 0), r["mode"])):
        L.append("| %s | %s | %s | %s | %s | `%s` |" % (r["id"], r["mode"], r["status"], r["target"],
                                                        (r["detail"] or "-").replace("|", "\\|"), r["file"]))
    L.append("")
    # Skips.
    L.append("## Skipped combinations")
    L.append("")
    reasons = {}
    for s in gen.skipped():
        reasons.setdefault(s.reason, []).append("%s-%s-%s" % (s.kind, s.place, s.transfer))
    for reason, ids in sorted(reasons.items(), key=lambda kv: -len(kv[1])):
        L.append("- %s (%d): %s" % (reason, len(ids), ", ".join(ids[:12]) + (", ..." if len(ids) > 12 else "")))
    L.append("")
    with open(os.path.join(out, "report.md"), "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(L))
    with open(os.path.join(out, "report.csv"), "w", encoding="utf-8", newline="") as f:
        w = csv.writer(f)
        w.writerow(["cell", "kind", "place", "transfer", "path", "status", "target", "at_target", "detail",
                    "leak_bytes_per_100_calls", "run", "shim_run", "build_s", "run_s", "program"])
        for r in results:
            w.writerow([r["id"], r["kind"], r["place"], r["transfer"], r["mode"], r["status"], r["target"],
                        "yes" if at_target(r) else "no", r["detail"], r["leak"], r["run"], r["shim"],
                        "%.1f" % r["build_s"], "%.2f" % r["run_s"], r["file"]])


# ---------------------------------------------------------------------------


def shard_cells(cells, spec):
    """The cells of shard k of n (k may be k,k,...): the ones whose 0-based
    position in the generator's order, modulo n, is k-1, as
    tests/scripts/sweep_shard.sh splits the test sweep. The order interleaves
    kinds and places, so every shard gets a like mix of slow and fast cells."""
    m = re.fullmatch(r"(\d+(?:,\d+)*)/(\d+)", spec.strip())
    if not m:
        raise SystemExit("ownership grid: --shard must be k/n or k,k.../n, got '%s'" % spec)
    n = int(m.group(2))
    ks = {int(k) for k in m.group(1).split(",")}
    if n < 1 or any(k < 1 or k > n for k in ks):
        raise SystemExit("ownership grid: --shard must have 1 <= k <= n, got '%s'" % spec)
    return [c for i, c in enumerate(cells) if (i % n) + 1 in ks]


def run_check(results, cells, modes, out, use_shim):
    """Compares with the baseline; (exit code, report lines)."""
    base = read_baseline()
    worse, better, changed, new = compare(results, base)
    if worse:
        # A heap count or a thread can make one run unlucky: run the program
        # again, and count it worse only when it is worse again. Either way
        # the rerun's result is the one kept.
        confirmed = []
        for r, b in worse:
            if r["status"] == "HARNESS":
                confirmed.append((r, b))
                continue
            cell = next(c for c in cells if c.id == r["id"])
            again = run_cell_safely(cell, next(m for m in modes if m.name == r["mode"]), out, use_shim)
            r.update(again)
            v = verdict(r, b)
            if v == "worse":
                confirmed.append((r, b))
            elif v == "better":
                better.append((r, b))
            elif v == "changed":
                changed.append((r, b))
        worse = confirmed
    generated = {c.id for c in gen.cells()}
    missing = sorted(cid for cid in base if cid not in generated)
    harness = [r for r in results if r["status"] == "HARNESS"]
    lines = []
    if any(r["status"] == "UNMEASURED" for r in results):
        lines += ["The heap count is not exact on this platform (mem.heap_in_use_exact): this check compares "
                  "values and use after free only, not leaks.", ""]
    for title, rows in (("Worse than the baseline (the check fails)", worse),
                        ("Better than the baseline (update baseline.txt)", better),
                        ("Changed within a tier", changed)):
        lines.append("%s: %d" % (title, len(rows)))
        lines.append("")
        for r, b in rows:
            lines.append("- `%s` (%s): %s -> %s %s" % (r["id"], r["mode"], format_status(*b),
                                                       format_status(r["status"], r["leak"]), r["detail"]))
        lines.append("")
    if missing:
        lines.append("In the baseline but no longer generated (the check fails; a removed cell is removed from "
                     "baseline.txt on purpose): %d" % len(missing))
        lines.append("")
        lines += ["- `%s`" % cid for cid in missing]
        lines.append("")
    if new:
        lines.append("Not in the baseline: %d (%s)" % (len(new), ", ".join(r["id"] for r in new[:20])))
        lines.append("")
    if harness:
        lines.append("HARNESS FAILURE: the runner itself failed on %d cell(s), twice each. This is a fault of the "
                     "grid's runner or the machine, not a finding about the compiler; the cells' logs end in "
                     "`.harness.log`:" % len(harness))
        lines.append("")
        lines += ["- `%s` (%s): %s" % (r["id"], r["mode"], r["detail"]) for r in harness]
        lines.append("")
    rc = 2 if harness else (1 if worse or missing else 0)
    return rc, lines


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--mode", default="gcc", choices=["gcc", "nogcc", "both"])
    ap.add_argument("--jobs", type=int, default=0)
    ap.add_argument("--only", default="")
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--update-baseline", action="store_true")
    ap.add_argument("--no-shim", action="store_true")
    ap.add_argument("--keep-bins", action="store_true", help="keep each cell's binary")
    ap.add_argument("--out", default=os.path.join(ROOT, "build", "ownership_grid"))
    ap.add_argument("--report-only", action="store_true", help="rewrite the report from <out>/results.json")
    ap.add_argument("--shard", default=os.environ.get("OWNERSHIP_GRID_SHARD", ""),
                    help="k/n or k,k.../n: only the cells whose position modulo n is k-1")
    a = ap.parse_args(argv)
    global KEEP_BINS
    KEEP_BINS = a.keep_bins
    no_error_dialogs()
    if a.report_only:
        out = os.path.abspath(a.out)
        with open(os.path.join(out, "results.json"), encoding="utf-8") as f:
            saved = json.load(f)
        write_report(out, saved["results"], [Mode(m) for m in saved["modes"]], saved["wall"], saved["jobs"],
                     saved.get("check"))
        if a.update_baseline:
            if any(r["status"] == "UNMEASURED" for r in saved["results"]):
                print("ownership grid: baseline.txt not written: growth was not measured on this platform")
                return 1
            write_baseline(saved["results"], read_baseline())
            print("ownership grid: wrote %s" % os.path.relpath(BASELINE, ROOT))
        return 0
    if not os.path.exists(AE):
        print("ownership grid: %s not found; run `make compiler ae stdlib` first" % AE, file=sys.stderr)
        return 2
    jobs = a.jobs or int(os.environ.get("NPROC", "0") or 0) or max(1, (os.cpu_count() or 2) // 2)
    modes = [Mode("gcc"), Mode("nogcc")] if a.mode == "both" else [Mode(a.mode)]
    use_shim = shim_supported() and not a.no_shim
    out = os.path.abspath(a.out)
    cells = gen.cells()
    if a.only:
        pats = a.only.split(",")
        cells = [c for c in cells if any(fnmatch.fnmatch(c.id, p) for p in pats)]
    if a.shard:
        cells = shard_cells(cells, a.shard)
    os.makedirs(os.path.join(out, "cells"), exist_ok=True)
    for m in modes:
        os.makedirs(os.path.join(out, m.name, "bin"), exist_ok=True)
    for c in cells:
        with open(os.path.join(out, "cells", c.file), "w", encoding="utf-8", newline="\n") as f:
            f.write(c.source)
    print("ownership grid: %d cells x %d C path(s)%s, %d jobs, poisoning allocator %s"
          % (len(cells), len(modes), (", shard " + a.shard) if a.shard else "", jobs,
             "on" if use_shim else "off"), flush=True)
    t0 = time.time()
    results = []
    lock = threading.Lock()
    done = [0]
    total = len(cells) * len(modes)
    with concurrent.futures.ThreadPoolExecutor(max_workers=jobs) as ex:
        futs = [ex.submit(run_cell_safely, c, m, out, use_shim) for m in modes for c in cells]
        for fu in concurrent.futures.as_completed(futs):
            r = fu.result()
            with lock:
                results.append(r)
                done[0] += 1
                if r["status"] != "OK" or done[0] % 50 == 0:
                    print("  [%d/%d] %s %s %s %s" % (done[0], total, r["mode"], r["id"], r["status"],
                                                      r["detail"][:120]), flush=True)
    wall = time.time() - t0
    check_text = None
    rc = 0
    if a.check:
        rc, check_text = run_check(results, cells, modes, out, use_shim)
        print("\n".join(check_text))
    # The files Windows held during the run: once more now, then left.
    left = [p for p in list(LEFT_FILES) if not remove_quietly_final(p)]
    with open(os.path.join(out, "results.json"), "w", encoding="utf-8") as f:
        json.dump({"wall": wall, "jobs": jobs, "modes": [m.name for m in modes], "results": results,
                   "check": check_text}, f)
    write_report(out, results, modes, wall, jobs, check_text, len(left))
    unmeasured = any(r["status"] == "UNMEASURED" for r in results)
    if a.update_baseline:
        if rc:
            print("ownership grid: baseline.txt not written: the check failed (run without --check to record it)")
        elif unmeasured:
            print("ownership grid: baseline.txt not written: growth was not measured on this platform, and the "
                  "baseline records leaks")
            rc = rc or 1
        else:
            write_baseline(results, read_baseline())
            print("ownership grid: wrote %s" % os.path.relpath(BASELINE, ROOT))
    for m in modes:
        c = counts([r for r in results if r["mode"] == m.name])
        print("ownership grid (%s): %s" % (m.name, ", ".join("%s %d" % (s, c[s]) for s in STATUSES if c[s])))
    if left:
        print("ownership grid: %d binaries could not be removed (Windows still held them): %s"
              % (len(left), ", ".join(os.path.basename(p) for p in left[:5])))
    print("ownership grid: %.0f s wall, %.1f cells/min; report in %s"
          % (wall, total * 60.0 / max(wall, 1), os.path.relpath(os.path.join(out, "report.md"), ROOT)))
    if a.check:
        if unmeasured:
            print("ownership grid check: the heap count is not exact here; values and use after free only")
        msg = {0: "passed", 1: "FAILED, a cell got worse or a baseline cell is no longer generated",
               2: "FAILED, the runner itself failed (see HARNESS FAILURE above)"}[rc]
        print("ownership grid check: %s" % msg)
    return rc


def remove_quietly_final(path):
    try:
        if os.path.exists(path):
            os.remove(path)
        return True
    except OSError:
        time.sleep(1)
        try:
            if os.path.exists(path):
                os.remove(path)
            return True
        except OSError:
            return False


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
