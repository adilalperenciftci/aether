#!/usr/bin/env python3
"""Tests of run.py's own failure paths (not of the compiler):

  1. A cell's binary that another process holds open, so it cannot be
     removed (on Windows a process still exiting, or Defender scanning, holds
     a file for a moment). The run must still complete, the cell keep its
     status, and the file be reported as left, never a traceback.
  2. A fault inside the runner on one cell (OWNERSHIP_GRID_FAULT names it).
     The cell is run once more, then reported as HARNESS, and the check
     fails with exit code 2 and a message saying the runner failed, while
     the other cells keep their statuses.

    python tests/ownership_grid/test_runner.py

Needs build/ae (`make compiler ae stdlib`). Uses build/ownership_grid_test/
and removes it at the end. Exit code 0 when both pass.
"""

import os
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
OUT = os.path.join(ROOT, "build", "ownership_grid_test")
EXE = ".exe" if os.name == "nt" else ""
RUN = [sys.executable, os.path.join(HERE, "run.py"), "--jobs", "2", "--out", OUT]


def run(args, env=None):
    p = subprocess.run(RUN + args, capture_output=True, text=True, env=env)
    return p.returncode, p.stdout + p.stderr


def fail(msg, output):
    print("FAIL: " + msg)
    print(output)
    return 1


def held_binary():
    """A file at the path of K1-P1-T1's binary, held open by another process."""
    bindir = os.path.join(OUT, "gcc", "bin")
    os.makedirs(bindir, exist_ok=True)
    path = os.path.join(bindir, "k1_p1_t1" + EXE)
    with open(path, "wb") as f:
        f.write(b"held by test_runner.py")
    holder = subprocess.Popen([sys.executable, "-c",
                               "import sys, time\n"
                               "f = open(sys.argv[1], 'rb')\n"
                               "print('held', flush=True)\n"
                               "time.sleep(600)\n", path],
                              stdout=subprocess.PIPE, text=True)
    holder.stdout.readline()
    try:
        rc, out = run(["--only", "K1-P1-T1"])
    finally:
        holder.kill()
        holder.wait()
    if rc != 0:
        return fail("the run with a held binary exited %d" % rc, out)
    if "Traceback" in out:
        return fail("the run with a held binary printed a traceback", out)
    if "ownership grid (gcc): OK 1" not in out:
        return fail("K1-P1-T1 is not OK with its binary held", out)
    if os.name == "nt" and "could not be removed" not in out:
        return fail("the held binary was not reported as left", out)
    print("PASS: a held binary leaves the run complete (%s)"
          % ("reported as left" if os.name == "nt" else "POSIX removes an open file"))
    return 0


def harness_fault():
    env = dict(os.environ)
    env["OWNERSHIP_GRID_FAULT"] = "K1-P1-T2"
    rc, out = run(["--check", "--only", "K1-P1-T1,K1-P1-T2"], env)
    if rc != 2:
        return fail("a runner fault exited %d, not 2" % rc, out)
    if "Traceback" in out:
        return fail("a runner fault printed a traceback", out)
    if "HARNESS FAILURE" not in out or "K1-P1-T2" not in out:
        return fail("a runner fault was not reported as a harness failure of K1-P1-T2", out)
    if "OK 1" not in out:
        return fail("the other cell lost its status", out)
    print("PASS: a runner fault on one cell is a HARNESS failure (exit 2), the other cell OK")
    return 0


def main():
    if not os.path.exists(os.path.join(ROOT, "build", "ae" + EXE)):
        print("test_runner.py: build/ae not found; run `make compiler ae stdlib` first")
        return 2
    shutil.rmtree(OUT, ignore_errors=True)
    try:
        bad = held_binary() + harness_fault()
    finally:
        shutil.rmtree(OUT, ignore_errors=True)
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
