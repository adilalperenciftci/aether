/* The time limit of a sweep test on Windows (#2758), a native program that
 * tests/lib/sweep_timeout.sh starts beside the command it bounds.
 *
 *   sweep_watchdog WINPID DURATION GOFILE
 *
 * WINPID is the Windows pid of the MSYS2 subshell that is about to run the
 * command; the subshell waits until GOFILE exists before it starts it. The
 * watchdog puts that subshell in a new job object, creates GOFILE, and waits
 * for the subshell to exit. Everything the subshell starts from then on, MSYS2
 * processes and native programs alike, is created inside the job. When the
 * limit passes first, TerminateJobObject ends every process in it and the
 * watchdog exits with 124, which the shell side reports as timeout(1) does.
 *
 * Why not timeout(1). On Windows a signal sent to the MSYS2 process standing
 * in for a native program makes the MSYS2 runtime walk the Windows process
 * table by recorded parent pids, which Windows recycles, and signal every
 * MSYS2 process-group leader it finds there: on the CI runner that reached the
 * step's own bash (exit code 2304), and a SIGTERM walk injects an exit into
 * any native process it reaches. timeout(1) sends exactly such a signal to its
 * process group when a test hangs. TerminateJobObject sends no signal at all
 * and reaches only the processes the test itself started. See
 * tests/lib/server_jobs.sh for the walk (#2479).
 *
 * The job is created with JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE, so if the
 * watchdog itself is ended (an outer limit, a cancelled CI job) the test's
 * processes go with it. When the command finishes by itself the kill is
 * disarmed before the watchdog exits, so whatever it left running stays, as
 * it does under timeout(1). The job allows no breakaway: the MSYS2 runtime
 * creates its children with CREATE_BREAKAWAY_FROM_JOB only when the job it
 * runs in allows that.
 *
 * DURATION is a number of seconds, fractions allowed, with an optional
 * suffix s, m, h or d, as for timeout(1); 0 means no limit.
 *
 * Exit status: 0 when the command ended by itself, 124 when the limit ended
 * it, 125 when the watchdog could not bound it. GOFILE is created in every
 * case where the watchdog runs at all, so the command never waits forever:
 * after a 125 it runs without a limit, and the shell side says so. */
#ifndef _WIN32
int main(void) { return 125; }
#else
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void release(const char* go) {
    HANDLE f = CreateFileA(go, GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_WRITE |
                           FILE_SHARE_DELETE, NULL, CREATE_ALWAYS,
                           FILE_ATTRIBUTE_NORMAL, NULL);
    if (f == INVALID_HANDLE_VALUE) {
        fprintf(stderr, "sweep_watchdog: cannot create %s (error %lu)\n",
                go, (unsigned long)GetLastError());
        return;
    }
    CloseHandle(f);
}

/* Milliseconds in a timeout(1) duration, INFINITE for 0, or -1 when the text
 * is not a duration. */
static long long parse_duration(const char* s) {
    char* end = NULL;
    double v = strtod(s, &end);
    if (end == s || v < 0) return -1;
    double scale = 1.0;
    if (*end == 's') { end++; }
    else if (*end == 'm') { scale = 60.0; end++; }
    else if (*end == 'h') { scale = 3600.0; end++; }
    else if (*end == 'd') { scale = 86400.0; end++; }
    if (*end != '\0') return -1;
    double ms = v * scale * 1000.0;
    if (ms == 0.0) return (long long)INFINITE;
    if (ms >= (double)(INFINITE - 1)) return (long long)(INFINITE - 1);
    if (ms < 1.0) ms = 1.0;
    return (long long)ms;
}

int main(int argc, char** argv) {
    if (argc != 4) {
        fprintf(stderr, "usage: sweep_watchdog WINPID DURATION GOFILE\n");
        return 125;
    }
    const char* go = argv[3];
    char* end = NULL;
    unsigned long pid = strtoul(argv[1], &end, 10);
    long long ms = parse_duration(argv[2]);
    if (end == argv[1] || *end != '\0' || pid == 0 || ms < 0) {
        fprintf(stderr, "sweep_watchdog: bad arguments '%s' '%s'\n", argv[1], argv[2]);
        release(go);
        return 125;
    }

    HANDLE proc = OpenProcess(PROCESS_SET_QUOTA | PROCESS_TERMINATE | SYNCHRONIZE |
                              PROCESS_QUERY_LIMITED_INFORMATION, FALSE, (DWORD)pid);
    HANDLE job = proc ? CreateJobObjectW(NULL, NULL) : NULL;
    JOBOBJECT_EXTENDED_LIMIT_INFORMATION li;
    memset(&li, 0, sizeof li);
    li.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
    if (!proc || !job ||
        !SetInformationJobObject(job, JobObjectExtendedLimitInformation, &li, sizeof li) ||
        !AssignProcessToJobObject(job, proc)) {
        fprintf(stderr, "sweep_watchdog: cannot put pid %lu in a job (error %lu)\n",
                pid, (unsigned long)GetLastError());
        release(go);
        return 125;
    }
    release(go);

    DWORD w = WaitForSingleObject(proc, (DWORD)ms);
    if (w == WAIT_TIMEOUT) {
        TerminateJobObject(job, 124);
        WaitForSingleObject(proc, 10000);
        return 124;
    }
    /* Ended by itself: disarm, so closing the job leaves alone whatever the
     * command started and meant to keep running. */
    memset(&li, 0, sizeof li);
    SetInformationJobObject(job, JobObjectExtendedLimitInformation, &li, sizeof li);
    CloseHandle(job);
    CloseHandle(proc);
    return w == WAIT_OBJECT_0 ? 0 : 125;
}
#endif
