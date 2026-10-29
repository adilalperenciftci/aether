#define _DEFAULT_SOURCE 1
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

int main(int argc, char** argv) {
    if (argc != 3 && argc != 4) {
        fprintf(stderr, "usage: %s <file> <omit|override|env|tamper> [grants]\n", argv[0]);
        return 2;
    }

    char* cat_argv[] = { (char*)"/bin/cat", argv[1], NULL };
    char* env_argv[] = { (char*)"/usr/bin/env", NULL };
    char* omitted[] = { (char*)"ONLY=explicit", NULL };
    char* overridden[] = {
        (char*)"ONLY=explicit",
        (char*)"LD_PRELOAD=",
        (char*)"AETHER_SANDBOX_GRANTS=/definitely/missing",
        NULL
    };
    char** child_env = strcmp(argv[2], "override") == 0 ? overridden : omitted;
    const char* child_path = strcmp(argv[2], "env") == 0
        ? "/usr/bin/env" : "/bin/cat";
    char** child_argv = strcmp(argv[2], "env") == 0 ? env_argv : cat_argv;

    if (strcmp(argv[2], "tamper") == 0 && argc == 4) {
        // A contained process editing its own environment before exec.
        setenv("AETHER_SANDBOX_GRANTS", argv[3], 1);
        unsetenv("AETHER_SANDBOX_SHM");
    }

    execve(child_path, child_argv, child_env);
    fprintf(stderr, "execve: %s\n", strerror(errno));
    return 111;
}
