// A child's env spliced in the parent (#3200, #3211):
// runtime/utils/aether_spawn.c's aether_spawn_env, which std.os's run_pipe
// and the sandboxed spawners build their children's environments with.
#include "test_harness.h"
#ifndef _WIN32
#include "../../runtime/utils/aether_spawn.h"
#include <stdlib.h>
#include <string.h>

static int env_has(char** env, const char* entry) {
    for (int i = 0; env && env[i]; i++)
        if (strcmp(env[i], entry) == 0) return 1;
    return 0;
}

static int env_count(char** env) {
    int n = 0;
    while (env && env[n]) n++;
    return n;
}

/* A set entry replaces the base's entry of the same name, and only that
 * one: `PATH` is not `PATHEXT`, whose name it begins. The prefix used to
 * match, and `PATH=...` dropped `PATHEXT=...` from the child's env. */
TEST_CATEGORY(spawn_env_replaces_the_whole_name_only, TEST_CATEGORY_RUNTIME) {
    char* base[] = { (char*)"PATHEXT=.COM", (char*)"PATH=/bin", (char*)"A=1", NULL };
    const char* set[] = { "PATH=/usr/bin" };
    char** env = aether_spawn_env(base, set, 1);
    ASSERT_NOT_NULL(env);
    ASSERT_TRUE(env_has(env, "PATHEXT=.COM"));
    ASSERT_TRUE(env_has(env, "PATH=/usr/bin"));
    ASSERT_TRUE(!env_has(env, "PATH=/bin"));
    ASSERT_TRUE(env_has(env, "A=1"));
    ASSERT_EQ(3, env_count(env));
    free(env);
}

/* A set entry with no `=` names a variable as a whole too: `PATH` took
 * `PATHEXT=...` with it, as a prefix. */
TEST_CATEGORY(spawn_env_set_name_alone, TEST_CATEGORY_RUNTIME) {
    char* base[] = { (char*)"PATHEXT=.COM", (char*)"PATH=/bin", NULL };
    const char* set[] = { "PATH" };
    char** env = aether_spawn_env(base, set, 1);
    ASSERT_NOT_NULL(env);
    ASSERT_TRUE(env_has(env, "PATHEXT=.COM"));
    ASSERT_TRUE(!env_has(env, "PATH=/bin"));
    ASSERT_TRUE(env_has(env, "PATH"));
    ASSERT_EQ(2, env_count(env));
    free(env);
}

/* An entry of the base with no `=` (a name alone) is a name too. */
TEST_CATEGORY(spawn_env_name_without_value, TEST_CATEGORY_RUNTIME) {
    char* base[] = { (char*)"AETHER_IPC_FD", (char*)"AETHER_IPC_FDX=1", NULL };
    const char* set[] = { "AETHER_IPC_FD=3" };
    char** env = aether_spawn_env(base, set, 1);
    ASSERT_NOT_NULL(env);
    ASSERT_TRUE(!env_has(env, "AETHER_IPC_FD"));
    ASSERT_TRUE(env_has(env, "AETHER_IPC_FDX=1"));
    ASSERT_TRUE(env_has(env, "AETHER_IPC_FD=3"));
    ASSERT_EQ(2, env_count(env));
    free(env);
}
#endif
