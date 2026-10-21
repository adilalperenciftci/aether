#ifndef AE_RELEASE_PLATFORM_H
#define AE_RELEASE_PLATFORM_H

/* Include libc headers before checking __GLIBC__ (it is not a compiler
 * predefined macro). Kept separate so every CPU/libc branch can be exercised
 * without building or running a foreign copy of the entire ae driver. */
#include <stdlib.h>

/* Host triple as the release convention spells it ("linux-x86_64",
 * "linux-x86_64-musl", "macos-arm64"). Returns NULL for unsupported hosts,
 * which forces the git-clone path. */
static const char* ae_host_triple(void) {
#if defined(__linux__)
    /* The libc headers describe the ABI this ae runs against. musl has no
     * identifying macro; among our supported Linux toolchains it is the
     * non-glibc case. Do not label Android/bionic or uClibc as musl. */
#  if defined(__ANDROID__) || defined(__BIONIC__) || defined(__UCLIBC__)
    return NULL;
#  else
#    if defined(__GLIBC__)
#      define AE_LINUX_LIBC_SUFFIX ""
#    else
#      define AE_LINUX_LIBC_SUFFIX "-musl"
#    endif
#    if defined(__x86_64__)
    return "linux-x86_64" AE_LINUX_LIBC_SUFFIX;
#    elif defined(__aarch64__)
    return "linux-arm64" AE_LINUX_LIBC_SUFFIX;
#    else
    return NULL;
#    endif
#    undef AE_LINUX_LIBC_SUFFIX
#  endif
#elif defined(__APPLE__)
#  if defined(__aarch64__)
    return "macos-arm64";
#  elif defined(__x86_64__)
    return "macos-x86_64";
#  else
    return NULL;
#  endif
#elif defined(_WIN32)
#  if defined(__x86_64__) || defined(_M_X64)
    return "windows-x86_64";
#  elif defined(_M_ARM64) || defined(__aarch64__)
    return "windows-arm64";
#  else
    return NULL;
#  endif
#elif defined(__FreeBSD__)
#  if defined(__x86_64__)
    return "freebsd-x86_64";
#  elif defined(__aarch64__)
    return "freebsd-arm64";
#  else
    return NULL;
#  endif
#else
    return NULL;
#endif
}

#endif /* AE_RELEASE_PLATFORM_H */
