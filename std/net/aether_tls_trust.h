#ifndef AETHER_TLS_TRUST_H
#define AETHER_TLS_TRUST_H

/* The Windows trust anchors, the same for both HTTPS clients (#2675): see
 * aether_tls_trust.c. std.http.client's OpenSSL path (aether_http.c) calls the
 * first two; std.cryptography.tls13_client the last two, through externs. */

#include <stddef.h>

#ifdef _WIN32
/* The first file of the shared bundle list that exists, in `out`; "" when
 * none does. Returns `out`. */
const char* aether_tls_windows_ca_bundle(char* out, size_t cap);
/* Calls `each` with the DER of every certificate in the ROOT system store of
 * the current user, which includes the machine's. Returns how many. */
int aether_tls_windows_root_store_each(void (*each)(const unsigned char* der, size_t len, void* arg),
                                       void* arg);
#endif

/* Every certificate of the Windows ROOT system store as PEM text, a fresh
 * counted string the caller releases; "" when there is none, and on any other
 * platform. NULL only when out of memory. */
char* aether_tls_windows_store_pem(void);
/* The first bundle file of the shared list that exists, a fresh counted
 * string the caller releases; "" when none does, and on any other platform.
 * NULL only when out of memory. */
char* aether_tls_windows_bundle(void);

#endif /* AETHER_TLS_TRUST_H */
