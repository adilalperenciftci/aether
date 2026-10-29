// Windows trust anchors, the same for both HTTPS clients (#2675).
//
// Neither client read the Windows certificate store, so a program copied to a
// machine without MSYS2 or Git for Windows could make no HTTPS request at all,
// and the two looked for different bundle files (OpenSSL's list in
// aether_http.c, the pure-Aether client's in std.cryptography.tls13_client),
// so one could work on a machine where the other failed. Both now trust,
// unless SSL_CERT_FILE or SSL_CERT_DIR names the store, every certificate in
// the system ROOT store (what Python's ssl module loads on Windows) together
// with the first bundle file of the one list below. The bundle joins the store
// rather than standing in for it: Windows adds a root to the store on demand,
// the first time CryptoAPI needs it, so a root a server chains to can be
// missing from the store of a machine that has never met that server.
//
// The tls13_client module reaches these through extern declarations, which is
// why they exist (returning nothing) on every platform. They live in a file of
// their own (#3426): in aether_http.c, beside the OpenSSL code that uses them
// too, every program that imported the pure client linked the whole HTTP
// client for them.

#include "aether_tls_trust.h"
#include "../../runtime/aether_resource_caps.h"
#include "../string/aether_string.h"

#include <stdio.h>
#include <string.h>

#ifdef _WIN32
#include <windows.h>
#include <wincrypt.h>

/* The first file of the bundle list that exists, in `out`; "" when none
 * does. In order: the bundle the release archive ships beside the program
 * (<root>\bin\prog.exe -> <root>\share\ssl\ca-bundle.crt, or the program's own
 * directory when it is not in a bin\), MSYS2's ca-certificates for MINGW64
 * and UCRT64 under both names it has used, and Git for Windows'. */
const char* aether_tls_windows_ca_bundle(char* out, size_t cap) {
    static const char* fixed[] = {
        "C:\\msys64\\mingw64\\etc\\ssl\\certs\\ca-bundle.crt",
        "C:\\msys64\\ucrt64\\etc\\ssl\\certs\\ca-bundle.crt",
        "C:\\msys64\\mingw64\\etc\\ssl\\cert.pem",
        "C:\\msys64\\ucrt64\\etc\\ssl\\cert.pem",
        "C:\\Program Files\\Git\\mingw64\\etc\\ssl\\certs\\ca-bundle.crt",
        NULL
    };
    char exe_path[MAX_PATH];
    DWORD n = GetModuleFileNameA(NULL, exe_path, sizeof(exe_path));
    if (n > 0 && n < sizeof(exe_path)) {
        char* p = strrchr(exe_path, '\\');           // ...\bin\prog.exe -> ...\bin
        if (p) {
            *p = '\0';
            char* q = strrchr(exe_path, '\\');        // ...\bin -> ...
            if (q && _stricmp(q, "\\bin") == 0) *q = '\0';
        }
        snprintf(out, cap, "%s\\share\\ssl\\ca-bundle.crt", exe_path);
        DWORD a = GetFileAttributesA(out);
        if (a != INVALID_FILE_ATTRIBUTES && !(a & FILE_ATTRIBUTE_DIRECTORY)) return out;
    }
    for (int i = 0; fixed[i]; i++) {
        DWORD a = GetFileAttributesA(fixed[i]);
        if (a != INVALID_FILE_ATTRIBUTES && !(a & FILE_ATTRIBUTE_DIRECTORY)) {
            snprintf(out, cap, "%s", fixed[i]);
            return out;
        }
    }
    if (cap) out[0] = '\0';
    return out;
}

/* Calls `each` with the DER of every certificate in the ROOT system store of
 * the current user, which includes the machine's. Returns how many. */
int aether_tls_windows_root_store_each(void (*each)(const unsigned char* der, size_t len, void* arg),
                                       void* arg) {
    HCERTSTORE store = CertOpenSystemStoreW(0, L"ROOT");
    if (!store) return 0;
    int n = 0;
    PCCERT_CONTEXT c = NULL;
    while ((c = CertEnumCertificatesInStore(store, c)) != NULL) {
        if ((c->dwCertEncodingType & X509_ASN_ENCODING) && c->cbCertEncoded > 0) {
            each(c->pbCertEncoded, (size_t)c->cbCertEncoded, arg);
            n++;
        }
    }
    CertCloseStore(store, 0);
    return n;
}

typedef struct { char* buf; size_t len, cap; int oom; } PemOut;

static void pem_out_append(PemOut* o, const char* s, size_t n) {
    if (o->oom) return;
    if (o->len + n + 1 > o->cap) {
        size_t want = o->cap ? o->cap * 2 : 65536;
        while (want < o->len + n + 1) want *= 2;
        char* grown = (char*)aether_caps_realloc(o->buf, o->cap, want);
        if (!grown) { o->oom = 1; return; }
        o->buf = grown;
        o->cap = want;
    }
    memcpy(o->buf + o->len, s, n);
    o->len += n;
    o->buf[o->len] = '\0';
}

/* One certificate as a PEM block, base64 in lines of 64. */
static void pem_out_cert(const unsigned char* der, size_t len, void* arg) {
    static const char b64[] =
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    PemOut* o = (PemOut*)arg;
    pem_out_append(o, "-----BEGIN CERTIFICATE-----\n", 28);
    char line[65];
    size_t col = 0;
    for (size_t i = 0; i < len; i += 3) {
        unsigned v = (unsigned)der[i] << 16;
        if (i + 1 < len) v |= (unsigned)der[i + 1] << 8;
        if (i + 2 < len) v |= der[i + 2];
        line[col++] = b64[(v >> 18) & 63];
        line[col++] = b64[(v >> 12) & 63];
        line[col++] = i + 1 < len ? b64[(v >> 6) & 63] : '=';
        line[col++] = i + 2 < len ? b64[v & 63] : '=';
        if (col == 64) {
            line[col++] = '\n';
            pem_out_append(o, line, col);
            col = 0;
        }
    }
    if (col) {
        line[col++] = '\n';
        pem_out_append(o, line, col);
    }
    pem_out_append(o, "-----END CERTIFICATE-----\n", 26);
}
#endif  // _WIN32

/* Every certificate of the Windows ROOT system store as PEM text, a fresh
 * counted string the caller releases; "" when there is none, and on any other
 * platform. NULL only when out of memory. */
char* aether_tls_windows_store_pem(void) {
#ifdef _WIN32
    PemOut o = { NULL, 0, 0, 0 };
    aether_tls_windows_root_store_each(pem_out_cert, &o);
    if (o.oom) { aether_caps_free(o.buf, o.cap); return NULL; }
    if (o.buf) return (char*)string_adopt_caps_buffer(o.buf, o.len, o.cap);
#endif
    return (char*)string_empty();
}

/* The first bundle file of the list above that exists, a fresh counted string
 * the caller releases; "" when none does, and on any other platform. NULL only
 * when out of memory. */
char* aether_tls_windows_bundle(void) {
#ifdef _WIN32
    char path[MAX_PATH + 64];
    aether_tls_windows_ca_bundle(path, sizeof(path));
    size_t n = strlen(path);
#else
    const char* path = "";
    size_t n = 0;
#endif
    return (char*)string_new_with_length(path, n);
}
