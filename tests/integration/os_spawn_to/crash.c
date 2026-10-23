/* The --crash child of test_os_spawn_to.ae: a crash with a defined cause.
 *
 * A write through a null pointer faulted too, but C leaves it undefined,
 * and an instrumented build reported the write instead of crashing on it
 * (UBSan, #2488). On Windows the access violation is raised as the
 * exception itself, so the child still ends with 0xC0000005 through the
 * unhandled-exception path the test covers (no error-reporting dialog holds
 * a child in its job). Elsewhere SIGSEGV is raised with its default action,
 * which ends the process as the fault did. */
#include <stdlib.h>
#ifdef _WIN32
#include <windows.h>
void os_spawn_to_crash(void) {
    RaiseException(EXCEPTION_ACCESS_VIOLATION, EXCEPTION_NONCONTINUABLE, 0, NULL);
    abort();
}
#else
#include <signal.h>
void os_spawn_to_crash(void) {
    signal(SIGSEGV, SIG_DFL);
    raise(SIGSEGV);
    abort();
}
#endif
