/* #3138: descriptor ownership at both sides of the pure TLS bridge.
 * Reuse the closed number inside the callback, making the worker race
 * deterministic: any second close destroys the replacement descriptor. */
#include "../../../std/net/aether_http_server.c"
#include <assert.h>
#include <fcntl.h>
#include <signal.h>

static int owned_fd;
static int replacement_fd;
static int close_calls;

static void close_and_reuse(int fd) {
    assert(close(fd) == 0);
    replacement_fd = open("/dev/null", O_RDONLY);
    assert(replacement_fd >= 0);
    if (replacement_fd != fd) {
        assert(dup2(replacement_fd, fd) == fd);
        close(replacement_fd);
        replacement_fd = fd;
    }
}

static void* refuse(int fd, const char* cert, const char* key) {
    (void)cert; (void)key;
    close_and_reuse(fd);
    return NULL;
}

static void release_conn(void* conn) {
    assert(conn == &owned_fd);
    close_calls++;
    close_and_reuse(owned_fd);
}

static void check_refusal(pt_server_accept_fn accept_fn, const char* cert, const char* key) {
    int pair[2];
    assert(socketpair(AF_UNIX, SOCK_STREAM, 0, pair) == 0);
    /* EOF during ClientHello must release the socket wrapper too. */
    close(pair[1]);
    assert(accept_fn(pair[0], cert, key) == NULL);
    if (fcntl(pair[0], F_GETFD) >= 0) fprintf(stderr, "refusal left fd open: cert=%s key=%s\n", cert, key);
    assert(fcntl(pair[0], F_GETFD) == -1 && errno == EBADF);
}

int test_tls_ownership(const char* cert, const char* key) {
    signal(SIGPIPE, SIG_IGN);
    pt_server_accept_fn real_accept = (pt_server_accept_fn)
        aether_callback_lookup("aether_pure_tls_server_accept");
    assert(real_accept);
    check_refusal(real_accept, "/no-such-aether-cert", key);
    check_refusal(real_accept, cert, "/no-such-aether-key");
    check_refusal(real_accept, key, key); /* no certificate in PEM */
    check_refusal(real_accept, cert, cert); /* no private key in PEM */
    for (int i = 0; i < 16; i++) check_refusal(real_accept, cert, key);

    aether_callback_register("aether_pure_tls_server_accept", (void*)refuse);
    HttpServer server = {0};
    server.tls_enabled = 1;
    server.is_pure_tls = 1;
    owned_fd = open("/dev/null", O_RDONLY);
    assert(owned_fd >= 0);
    http_server_drain_connection(&server, owned_fd);
    assert(fcntl(replacement_fd, F_GETFD) >= 0);
    close(replacement_fd);

    aether_callback_register("aether_pure_tls_server_close", (void*)release_conn);
    owned_fd = open("/dev/null", O_RDONLY);
    assert(owned_fd >= 0);
    HttpConn conn = {0};
    conn.fd = owned_fd;
    conn.pure_tls = &owned_fd;
    conn.linger_on_close = 1;
    conn_close(&conn);
    assert(close_calls == 1 && conn.fd == -1 && conn.pure_tls == NULL);
    assert(fcntl(replacement_fd, F_GETFD) >= 0);
    conn_close(&conn); /* repeated teardown must also be harmless */
    assert(close_calls == 1 && fcntl(replacement_fd, F_GETFD) >= 0);
    close(replacement_fd);

    /* Plain HTTP retains its C-side ownership. */
    conn.fd = open("/dev/null", O_RDONLY);
    assert(conn.fd >= 0);
    owned_fd = conn.fd;
    conn.linger_on_close = 0;
    conn_close(&conn);
    assert(conn.fd == -1 && fcntl(owned_fd, F_GETFD) == -1 && errno == EBADF);

    /* The weak fallback also consumes the fd when the module is absent. */
    owned_fd = open("/dev/null", O_RDONLY);
    assert(owned_fd >= 0);
    assert(aether_pure_tls_server_accept(owned_fd, cert, key) == NULL);
    assert(fcntl(owned_fd, F_GETFD) == -1 && errno == EBADF);
    puts("PASS: pure TLS descriptor ownership");
    return 0;
}
