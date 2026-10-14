#!/usr/bin/env python3
"""Runner of the ownership grid: generate, build, run, classify, report.

    python tests/ownership_grid/run.py [options]

Every cell gen.py makes is written to build/ownership_grid/cells/, built
with build/ae once, linking poison_alloc.c (-Wl,--wrap=free,--wrap=realloc),
run twice (as it is, and with OWNERSHIP_GRID_POISON=1, which poisons every
freed block), and given one status:

  OK         every value right, no growth, nothing under the poisoning allocator
  LEAK       mem.steady_growth is not 0 (the bytes per 100 calls are kept)
  UAF        under the poisoning allocator: a double free, a crash, or a value
             that is wrong only there (a read of a freed, 0xDD-filled block)
  WRONG      a value is wrong without the poisoning allocator
  NOCOMPILE  aetherc refused the program, or the C did not compile (which one
             is kept)
  CRASH      the program died without the poisoning allocator, and nothing
             under it pins a memory error
  TIMEOUT    the program did not finish

Options:
  --mode gcc|nogcc|both  the C path: gcc is the default build, nogcc builds with
                         AE_CC="<cc> -DAETHER_GCC_COMPAT=0" (default gcc)
  --jobs N               parallel cells (default NPROC, else the CPU count / 2)
  --only PAT[,PAT]       only cells whose id matches one of the fnmatch patterns
  --check                compare with baseline.txt and exit 1 when a cell got worse
  --update-baseline      write baseline.txt from this run (an --only run updates its cells)
  --no-shim              skip the poisoning allocator build (no UAF column)
  --keep-bins            keep each cell's binaries (deleted after its runs otherwise)
  --report-only          rewrite report.md and report.csv from <out>/results.json
  --shard k/n            only shard k of n (k may be a list, 2,3/3), as CI splits the grid;
                         OWNERSHIP_GRID_SHARD sets it too
  --out DIR              output directory (default build/ownership_grid)

Writes <out>/report.md and <out>/report.csv.
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
import shutil
import subprocess
import sys
import threading
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)
import gen  # noqa: E402

WINDOWS = os.name == "nt"
EXE = ".exe" if WINDOWS else ""
AE = os.path.join(ROOT, "build", "ae" + EXE)
SHIM = os.path.join(HERE, "poison_alloc.c")
BASELINE = os.path.join(HERE, "baseline.txt")

BUILD_TIMEOUT = 600
RUN_TIMEOUT = 120
EXIT_WRONG, EXIT_LEAK, EXIT_POISON = 12, 13, 86

STATUSES = ["OK", "LEAK", "NOCOMPILE", "TIMEOUT", "CRASH", "WRONG", "UAF"]
# How bad a status is, for the check: a move to a higher tier is a regression.
TIER = {"OK": 0, "LEAK": 1, "NOCOMPILE": 2, "TIMEOUT": 3, "CRASH": 3, "WRONG": 3, "UAF": 3}
# The order the worst cells are listed in.
SEVERITY = {"UAF": 0, "WRONG": 1, "CRASH": 2, "TIMEOUT": 3, "NOCOMPILE": 4, "LEAK": 5, "OK": 6}

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
        self.shim_cc = self.cc + " -Wl,--wrap=free,--wrap=realloc"


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


def run_cell(cell, mode, out, use_shim):
    """Build one cell under one C path, run it plain and poisoned; a result dict.

    The one build links poison_alloc.c (where the linker has --wrap), whose
    free and realloc pass through to the C heap unless OWNERSHIP_GRID_POISON
    is set: the plain run measures leaks on the C heap as it is, the poisoned
    run catches double frees and reads of freed blocks."""
    src = os.path.join(out, "cells", cell.file)
    bindir = os.path.join(out, mode.name, "bin")
    stem = os.path.join(bindir, cell.file[:-3])
    res = {"id": cell.id, "kind": cell.kind, "place": cell.place, "transfer": cell.transfer,
           "file": os.path.relpath(src, ROOT).replace("\\", "/"), "mode": mode.name,
           "status": "", "detail": "", "leak": "", "run": "", "shim": "", "build_s": 0.0, "run_s": 0.0}
    exe = stem + EXE
    if os.path.exists(exe):
        os.remove(exe)
    argv = [AE, "build", src, "-o", exe]
    if use_shim:
        argv[3:3] = ["--extra", SHIM]
    rc, log, secs = run_cmd(argv, build_env(out, mode.shim_cc if use_shim else mode.env_cc), bindir,
                            BUILD_TIMEOUT)
    res["build_s"] = secs
    with open(stem + ".build.log", "w", encoding="utf-8") as f:
        f.write(log)
    if rc != 0 or not os.path.exists(exe):
        if rc is None:
            res["status"], res["detail"] = "NOCOMPILE", "build timed out"
            return res
        stage, line = compile_error(log)
        res["status"], res["detail"] = "NOCOMPILE", "%s: %s" % (stage, line[:300])
        return res
    plain_env = dict(os.environ)
    plain_env.pop("OWNERSHIP_GRID_POISON", None)
    rc, outp, secs = run_cmd([exe], plain_env, bindir, RUN_TIMEOUT)
    res["run_s"] = secs
    with open(stem + ".run.log", "w", encoding="utf-8") as f:
        f.write(outp)
    normal = classify_run(rc, outp)
    res["run"] = describe_exit(rc)
    shim = None
    if use_shim:
        poison_env = dict(plain_env)
        poison_env["OWNERSHIP_GRID_POISON"] = "1"
        src_rc, soutp, ssecs = run_cmd([exe], poison_env, bindir, RUN_TIMEOUT)
        res["run_s"] += ssecs
        with open(stem + ".p.run.log", "w", encoding="utf-8") as f:
            f.write(soutp)
        res["shim"] = describe_exit(src_rc)
        shim = classify_shim(src_rc, soutp)
    status, detail = combine(normal, shim)
    res["status"], res["detail"] = status, detail
    if normal[0] == "LEAK":
        res["leak"] = normal[2]
    if not KEEP_BINS and os.path.exists(exe):
        # The program is the reproducer; the binaries come to 2 GB over the grid.
        os.remove(exe)
    return res


def first_line(text, prefix):
    for ln in text.splitlines():
        if ln.startswith(prefix):
            return ln.strip()
    return ""


def classify_run(rc, out):
    """(status, detail, leak bytes) of the run without the shim."""
    if rc is None:
        return "TIMEOUT", "no exit within %d s" % RUN_TIMEOUT, ""
    if rc == 0:
        return "OK", "", ""
    if rc == EXIT_WRONG:
        return "WRONG", first_line(out, "WRONG:"), ""
    if rc == EXIT_LEAK:
        m = re.search(r"LEAK: (-?\d+) bytes per (\d+) calls", out)
        if not m:
            return "LEAK", "growth not read from the output", "?"
        n = int(m.group(1)) * 100 // max(1, int(m.group(2)))
        per = "" if m.group(2) == "100" else " (%s per %s calls)" % (m.group(1), m.group(2))
        return "LEAK", "%d bytes per 100 calls%s" % (n, per), str(n)
    tail = " / ".join(ln.strip() for ln in out.strip().splitlines()[-2:])
    return "CRASH", "%s%s" % (describe_exit(rc), (": " + tail[:200]) if tail else ""), ""


def classify_shim(rc, out):
    """('UAF' | 'CLEAN' | 'TIMEOUT', detail) of the run under the poisoning allocator."""
    if rc is None:
        return "TIMEOUT", "timed out under the poisoning allocator"
    if rc in (0, EXIT_LEAK):  # growth means nothing there: nothing is freed
        return "CLEAN", ""
    if rc == EXIT_POISON:
        return "UAF", first_line(out, "POISON:") or "double free"
    if rc == EXIT_WRONG:
        return "UAF", "under the poisoning allocator: " + first_line(out, "WRONG:")
    return "UAF", "under the poisoning allocator: " + describe_exit(rc)


def combine(normal, shim):
    st, detail, _ = normal
    if shim and shim[0] == "UAF" and shim[1].startswith("POISON"):
        return "UAF", shim[1] + ("" if st == "OK" else " (without it: %s %s)" % (st, detail)).rstrip()
    if st in ("WRONG", "CRASH", "TIMEOUT"):
        return st, detail
    if shim and shim[0] == "UAF":
        return "UAF", shim[1]
    if shim and shim[0] == "FAILED":
        return st, (detail + "; " if detail else "") + shim[1]
    if shim and shim[0] == "TIMEOUT" and st == "OK":
        return "OK", shim[1]
    return st, detail


# ---------------------------------------------------------------------------
# Baseline


def read_baseline():
    """{id: {mode: status}}."""
    base = {}
    if not os.path.exists(BASELINE):
        return base
    with open(BASELINE, encoding="utf-8") as f:
        for ln in f:
            ln = ln.strip()
            if not ln or ln.startswith("#"):
                continue
            parts = ln.split()
            base[parts[0]] = {"gcc": parts[1]}
            if len(parts) > 2 and parts[2] != "-":
                base[parts[0]]["nogcc"] = parts[2]
    return base


def write_baseline(results, modes, old):
    by = {}
    for r in results:
        by.setdefault(r["id"], {})[r["mode"]] = r["status"]
    # Every cell the generator makes: this run's status where it ran (an
    # --only run updates its own cells), the old line's elsewhere.
    ids = [c.id for c in gen.cells() if c.id in by or c.id in old]
    by = {cid: by.get(cid, {}) for cid in ids}
    with open(BASELINE, "w", encoding="utf-8", newline="\n") as f:
        f.write("# Ownership grid baseline: each cell's status on main (tests/ownership_grid/README.md).\n")
        f.write("# <cell> <status on the default C path> <status with -DAETHER_GCC_COMPAT=0, or ->\n")
        f.write("# `make ownership-grid-check` fails when a cell gets worse than this.\n")
        f.write("# Measured at %s (%s) on %s.\n" % (git_head("%h"), compiler_version(), platform.system()))
        for cid in ids:
            g = by[cid].get("gcc") or old.get(cid, {}).get("gcc", "-")
            n = by[cid].get("nogcc") or old.get(cid, {}).get("nogcc", "-")
            f.write("%s %s %s\n" % (cid, g, n))


def compare(results, base):
    worse, better, changed, new = [], [], [], []
    for r in results:
        b = base.get(r["id"], {}).get(r["mode"])
        if b is None:
            new.append(r)
            continue
        if TIER[r["status"]] > TIER[b]:
            worse.append((r, b))
        elif TIER[r["status"]] < TIER[b]:
            better.append((r, b))
        elif r["status"] != b:
            changed.append((r, b))
    return worse, better, changed, new


# ---------------------------------------------------------------------------
# Report

ABBR = {"OK": "OK", "LEAK": "LEAK", "UAF": "**UAF**", "WRONG": "**WRONG**", "CRASH": "**CRASH**",
        "TIMEOUT": "TIME", "NOCOMPILE": "NC"}


def cell_mark(rs):
    marks = []
    for r in rs:
        s = r["status"]
        if s == "NOCOMPILE":
            marks.append("NC-c" if r["detail"].startswith("C:") else "NC-a")
        else:
            marks.append(ABBR[s])
    return "/".join(marks)


def leak_total(rows):
    """(sum of |growth| over the LEAK cells, how many of them were negative)."""
    total, neg = 0, 0
    for r in rows:
        if r["status"] == "LEAK" and r["leak"] not in ("", "?"):
            n = int(r["leak"])
            total += abs(n)
            neg += n < 0
    return total, neg


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


def write_report(out, results, modes, wall, njobs, check_text=None):
    order = {c.id: i for i, c in enumerate(gen.cells())}
    results = sorted(results, key=lambda r: (order.get(r["id"], 0), r["mode"]))
    by_id = {}
    for r in results:
        by_id.setdefault(r["id"], []).append(r)
    ncells = len(by_id)
    version = compiler_version()
    head = git_head("%h %s")
    L = []
    L.append("# Ownership grid report")
    L.append("")
    L.append("Generated by `tests/ownership_grid/run.py` on %s, %s, at `%s` (%s)."
             % (datetime.date.today().isoformat(), version, head, platform.platform()))
    L.append("")
    L.append("%d cells, C path%s: %s. %d combinations skipped (listed at the end), and %d combinations of a "
             "producer kind with a place or transfer outside its axis not generated. Wall time %.0f s with %d jobs, "
             "%.1f cells per minute (all C paths)."
             % (ncells, "s" if len(modes) > 1 else "", ", ".join(m.name for m in modes), len(gen.skipped()),
                gen.PRODUCER_NOT_CROSSED, wall, njobs, ncells * len(modes) * 60.0 / wall))
    if not shim_supported():
        L.append("")
        L.append("The poisoning allocator was not built: this linker has no `--wrap` (macOS), so no cell is UAF here.")
    L.append("")
    L.append("Statuses: OK; LEAK (mem.steady_growth is not 0); UAF (under the poisoning allocator: a double free, a crash, "
             "or a value wrong only there); WRONG (a wrong value without it); NC-a / NC-c (NOCOMPILE: aetherc refused "
             "it / the C did not compile); CRASH; TIME (TIMEOUT). Where two C paths ran, a cell shows "
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
        L.append("**%s** (%d cells): " % (m.name, len(rows)) + ", ".join("%s %d" % (s, c[s]) for s in STATUSES))
        L.append("")
        total, n_neg = leak_total(rows)
        L.append("**Total LEAK on the %s path: %d bytes per 100 calls**, summed over every LEAK cell (the number "
                 "to drive to zero)%s." % (m.name, total, "; %d of them shrank the heap instead, a free that came a "
                                            "round late, counted by its size" % n_neg if n_neg else ""))
        L.append("")
    m0 = modes[0].name
    rows0 = [r for r in results if r["mode"] == m0]
    for title, key, names in (("kind", "kind", None), ("place", "place", None)):
        L.append("By %s (%s path):" % (title, m0))
        L.append("")
        L.append("| %s | cells | %s |" % (title, " | ".join(STATUSES)))
        L.append("|---|---|%s|" % "|".join("---" for _ in STATUSES))
        present = {r[key] for r in rows0}
        canon = ([k.id for k in gen.KINDS] + ["KE"]) if key == "kind" else [p for p, _ in gen.PLACES]
        keys = [k for k in canon if k in present] + sorted(present - set(canon))
        for k in keys:
            sub = [r for r in rows0 if r[key] == k]
            c = counts(sub)
            label = k
            L.append("| %s | %d | %s |" % (label, len(sub), " | ".join(str(c[s]) if c[s] else "" for s in STATUSES)))
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
    L.append("| kind | class | C function | module | cells | %s | LEAK bytes |" % " | ".join(STATUSES))
    L.append("|---|---|---|---|---|%s|---|" % "|".join("---" for _ in STATUSES))
    for k in gen.PRODUCERS:
        sub = [r for r in rows0 if r["kind"] == k.id]
        c = counts(sub)
        L.append("| %s | %s | `%s` | %s | %d | %s | %d |" % (k.id, k.pclass, k.function, k.module, len(sub),
                                                         " | ".join(str(c[s]) if c[s] else "" for s in STATUSES),
                                                         leak_total(sub)[0]))
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
        cols = [t for t in tcols if any(c.transfer == t for c in kc)]
        pls = [p for p, _ in gen.PLACES if any(c.place == p for c in kc)]
        L.append("### %s %s" % (k, gen.kind_title(k)))
        L.append("")
        L.append("| place | %s |" % " | ".join(cols))
        L.append("|---|%s|" % "|".join("---" for _ in cols))
        for p in pls:
            row = []
            for t in cols:
                cid = "%s-%s-%s" % (k, p, t)
                row.append(cell_mark(by_id[cid]) if cid in by_id else "")
            L.append("| %s %s | %s |" % (p, gen.PLACE_TITLE.get(p, ""), " | ".join(row)))
        L.append("")
    L.append("Transfers: " + "; ".join("%s %s" % (t, d) for t, d in gen.TRANSFERS + gen.KE_TRANSFERS) + ".")
    L.append("")
    # Every non-OK cell.
    L.append("## Every cell that is not OK")
    L.append("")
    L.append("| cell | path | status | detail | program |")
    L.append("|---|---|---|---|---|")
    for r in sorted([r for r in results if r["status"] != "OK"],
                    key=lambda r: (SEVERITY[r["status"]], order.get(r["id"], 0), r["mode"])):
        L.append("| %s | %s | %s | %s | `%s` |" % (r["id"], r["mode"], r["status"],
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
        w.writerow(["cell", "kind", "place", "transfer", "path", "status", "detail", "leak_bytes_per_100_calls",
                    "run", "shim_run", "build_s", "run_s", "program"])
        for r in results:
            w.writerow([r["id"], r["kind"], r["place"], r["transfer"], r["mode"], r["status"], r["detail"],
                        r["leak"], r["run"], r["shim"], "%.1f" % r["build_s"], "%.2f" % r["run_s"], r["file"]])


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


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--mode", default="gcc", choices=["gcc", "nogcc", "both"])
    ap.add_argument("--jobs", type=int, default=0)
    ap.add_argument("--only", default="")
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--update-baseline", action="store_true")
    ap.add_argument("--no-shim", action="store_true")
    ap.add_argument("--keep-bins", action="store_true", help="keep each cell's two binaries")
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
            write_baseline(saved["results"], None, read_baseline())
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
        futs = [ex.submit(run_cell, c, m, out, use_shim) for m in modes for c in cells]
        for fu in concurrent.futures.as_completed(futs):
            r = fu.result()
            with lock:
                results.append(r)
                done[0] += 1
                if r["status"] != "OK" or done[0] % 50 == 0:
                    print("  [%d/%d] %s %s %s %s" % (done[0], total, r["mode"], r["id"], r["status"],
                                                      r["detail"][:120]), flush=True)
    wall = time.time() - t0
    with open(os.path.join(out, "results.json"), "w", encoding="utf-8") as f:
        json.dump({"wall": wall, "jobs": jobs, "modes": [m.name for m in modes], "results": results}, f)
    check_text = None
    rc = 0
    if a.check:
        base = read_baseline()
        worse, better, changed, new = compare(results, base)
        if worse:
            # A heap count or a thread can make one run unlucky: run the
            # program again, and count it worse only when it is worse again.
            confirmed = []
            for r, b in worse:
                cell = next(c for c in cells if c.id == r["id"])
                again = run_cell(cell, next(m for m in modes if m.name == r["mode"]), out, use_shim)
                if TIER[again["status"]] > TIER[b]:
                    confirmed.append((again, b))
                    for x in results:
                        if x["id"] == r["id"] and x["mode"] == r["mode"]:
                            x.update(again)
                else:
                    changed.append((again, b))
            worse = confirmed
        check_text = []
        for title, rows in (("Worse than the baseline (the check fails)", worse),
                            ("Better than the baseline (update baseline.txt)", better),
                            ("Changed within a tier", changed)):
            check_text.append("%s: %d" % (title, len(rows)))
            check_text.append("")
            for r, b in rows:
                check_text.append("- `%s` (%s): %s -> %s %s" % (r["id"], r["mode"], b, r["status"], r["detail"]))
            check_text.append("")
        if new:
            check_text.append("Not in the baseline: %d (%s)" % (len(new), ", ".join(r["id"] for r in new[:20])))
            check_text.append("")
        print("\n".join(check_text))
        if worse:
            rc = 1
    with open(os.path.join(out, "results.json"), "w", encoding="utf-8") as f:
        json.dump({"wall": wall, "jobs": jobs, "modes": [m.name for m in modes], "results": results,
                   "check": check_text}, f)
    write_report(out, results, modes, wall, jobs, check_text)
    if a.update_baseline and rc:
        print("ownership grid: baseline.txt not written: a cell got worse (run without --check to record it)")
    elif a.update_baseline:
        write_baseline(results, modes, read_baseline())
        print("ownership grid: wrote %s" % os.path.relpath(BASELINE, ROOT))
    for m in modes:
        c = counts([r for r in results if r["mode"] == m.name])
        print("ownership grid (%s): %s" % (m.name, ", ".join("%s %d" % (s, c[s]) for s in STATUSES)))
    print("ownership grid: %.0f s wall, %.1f cells/min; report in %s"
          % (wall, total * 60.0 / wall, os.path.relpath(os.path.join(out, "report.md"), ROOT)))
    if a.check:
        print("ownership grid check: %s" % ("FAILED, a cell got worse" if rc else "passed"))
    return rc


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
