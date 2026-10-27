/* The proxy event loop's resolver, and the loop's requests that wait on it
 * (#3267, #3275, #3283, #3284). POSIX only, as the loop is. */
#include "test_harness.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <time.h>
#if !defined(_WIN32)
#include <sys/socket.h>
#include <sys/time.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <pthread.h>
#include <unistd.h>
#include <poll.h>
#include "../../std/net/aether_http_server.h"
#include "../../std/net/aether_http_internal.h"
#include "../../std/net/aether_http_evloop.h"
#include "../../std/net/aether_net_addr.h"
#include "../../std/http/proxy/aether_proxy.h"

/* The proxy event loop's resolver (#3267, #3275). The tests give it a lookup
 * they hold until they let it go, which stands in for a resolver that is slow
 * to answer, and which gives each lookup an address of its own: 127.0.0.n
 * for the nth. */
static pthread_mutex_t rs_lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t  rs_cond = PTHREAD_COND_INITIALIZER;
static int rs_release, rs_fail, rs_lookups, rs_answered;

static int rs_lookup(const char* host, int port, struct AetherAddrList* out) {
    (void)host;
    pthread_mutex_lock(&rs_lock);
    int nth = ++rs_lookups;
    pthread_cond_broadcast(&rs_cond);
    while (!rs_release) pthread_cond_wait(&rs_cond, &rs_lock);
    int fail = rs_fail;
    pthread_mutex_unlock(&rs_lock);
    out->n = 0;
    if (fail) return -1;
    struct sockaddr_in* a = (struct sockaddr_in*)&out->ss[0];
    memset(&out->ss[0], 0, sizeof(out->ss[0]));
    a->sin_family = AF_INET;
    a->sin_port = htons((unsigned short)port);
    a->sin_addr.s_addr = htonl(0x7f000000u | (unsigned)nth);
    out->len[0] = (socklen_t)sizeof(*a);
    out->n = 1;
    return 0;
}

static void rs_on_answer(void* ctx, unsigned name) {
    (void)ctx; (void)name;
    pthread_mutex_lock(&rs_lock);
    rs_answered++;
    pthread_cond_broadcast(&rs_cond);
    pthread_mutex_unlock(&rs_lock);
}

static void rs_reset(int release, int fail) {
    pthread_mutex_lock(&rs_lock);
    rs_release = release;
    rs_fail = fail;
    rs_lookups = 0;
    rs_answered = 0;
    pthread_mutex_unlock(&rs_lock);
}

static void rs_let_go(void) {
    pthread_mutex_lock(&rs_lock);
    rs_release = 1;
    pthread_cond_broadcast(&rs_cond);
    pthread_mutex_unlock(&rs_lock);
}

/* Until *counter reaches `n`, for five seconds at most; the count then. */
static int rs_wait_for(int* counter, int n) {
    struct timespec until;
    clock_gettime(CLOCK_REALTIME, &until);
    until.tv_sec += 5;
    pthread_mutex_lock(&rs_lock);
    while (*counter < n && pthread_cond_timedwait(&rs_cond, &rs_lock, &until) == 0) {}
    int got = *counter;
    pthread_mutex_unlock(&rs_lock);
    return got;
}

static int64_t rs_now_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (int64_t)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

static unsigned rs_addr_of(const struct AetherAddrList* a) {
    return ntohl(((const struct sockaddr_in*)&a->ss[0])->sin_addr.s_addr);
}

/* The loop's dial never waits on a lookup: with the resolver held, asking
 * for a name, and dialling it, come back at once, the dial saying the answer
 * is on its way. Dials waiting on one name share one lookup, and its answer
 * is kept for the next. The loop looked names up on its driver thread, and
 * every connection it held waited (#3267). */
TEST(http_resolver_never_waits_on_a_lookup) {
    rs_reset(0, 0);
    HttpResolver* r = http_resolver_new(rs_on_answer, NULL);
    if (!r) return;                      /* a build without threads has no loop */
    http_resolver_set_lookup(r, rs_lookup);
    struct AetherAddrList a;
    int64_t t0 = rs_now_ms();
    ASSERT_EQ(0, http_resolver_answer(r, "slow.test", 8080, &a));
    ASSERT_EQ(1, rs_wait_for(&rs_lookups, 1));   /* the lookup is under way */
    ASSERT_EQ(0, http_resolver_answer(r, "slow.test", 8080, &a));
    HttpUpstreamConn up;
    ASSERT_EQ(-1, http_upstream_acquire_nb("slow.test", 8080, 0, r, &up));
    ASSERT_EQ(1, http_upstream_lookup(&up));
    ASSERT_EQ(1, http_resolver_answer(r, "127.0.0.1", 9, &a));   /* numeric: none */
    ASSERT_TRUE(rs_now_ms() - t0 < 1000);
    rs_let_go();
    ASSERT_EQ(1, rs_wait_for(&rs_answered, 1));
    ASSERT_EQ(1, http_resolver_answer(r, "slow.test", 8080, &a));
    ASSERT_EQ(1, a.n);
    ASSERT_EQ(1, rs_lookups);            /* three asks, one lookup */
    http_resolver_free(r);
}

/* Names never take each other's place. The resolve cache was 64 slots, one
 * name each, so two upstreams whose names fell in one slot evicted each
 * other, and each request that met an evicted name moved its whole client
 * connection off the loop (#3275): "auth" and "cart" on one port did, and
 * so did one host on two ports 64 apart. */
TEST(http_resolver_keeps_names_apart) {
    rs_reset(1, 0);
    HttpResolver* r = http_resolver_new(rs_on_answer, NULL);
    if (!r) return;
    http_resolver_set_lookup(r, rs_lookup);
    const char* hosts[4] = { "auth", "cart", "localhost", "localhost" };
    int ports[4] = { 8080, 8080, 9000, 9064 };
    unsigned got[4];
    struct AetherAddrList a;
    for (int i = 0; i < 4; i++) {
        ASSERT_EQ(0, http_resolver_answer(r, hosts[i], ports[i], &a));
        ASSERT_EQ(i + 1, rs_wait_for(&rs_answered, i + 1));
        ASSERT_EQ(1, http_resolver_answer(r, hosts[i], ports[i], &a));
        got[i] = rs_addr_of(&a);
    }
    for (int i = 0; i < 4; i++) {
        ASSERT_EQ(1, http_resolver_answer(r, hosts[i], ports[i], &a));
        ASSERT_EQ((int)got[i], (int)rs_addr_of(&a));
    }
    ASSERT_EQ(4, rs_lookups);
    http_resolver_free(r);
}

/* A name that does not resolve fails its dials at once, without a lookup
 * each, and the dial says why: the exchange answers it as the worker path's
 * "could not resolve host". */
TEST(http_resolver_fails_a_name_that_does_not_resolve) {
    rs_reset(1, 1);
    HttpResolver* r = http_resolver_new(rs_on_answer, NULL);
    if (!r) return;
    http_resolver_set_lookup(r, rs_lookup);
    struct AetherAddrList a;
    ASSERT_EQ(0, http_resolver_answer(r, "nohost.test", 80, &a));
    ASSERT_EQ(1, rs_wait_for(&rs_answered, 1));
    int64_t failed_at = rs_now_ms();
    int got = http_resolver_answer(r, "nohost.test", 80, &a);
    HttpUpstreamConn up;
    int fd = http_upstream_acquire_nb("nohost.test", 80, 0, r, &up);
    int why = http_upstream_lookup(&up);
    /* Within the second the failure answers for. A runner stalled past it
     * asks again, as it should, and these say nothing. */
    if (rs_now_ms() - failed_at < 900) {
        ASSERT_EQ(-1, got);
        ASSERT_EQ(-1, fd);
        ASSERT_EQ(-1, why);
        ASSERT_EQ(1, rs_lookups);
    }
    http_resolver_free(r);
}

/* The resolver starts a thread for a name while the threads it has are
 * taken: with one thread idle and two names asked back to back, the second
 * waited behind the first (#3284). Here the first lookup is held, and the
 * second must still be looked up. */
static pthread_mutex_t rs2_lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t  rs2_cond = PTHREAD_COND_INITIALIZER;
static int rs2_release, rs2_started;

static int rs2_lookup(const char* host, int port, struct AetherAddrList* out) {
    pthread_mutex_lock(&rs2_lock);
    rs2_started++;
    pthread_cond_broadcast(&rs2_cond);
    if (strcmp(host, "held.test") == 0)
        while (!rs2_release) pthread_cond_wait(&rs2_cond, &rs2_lock);
    pthread_mutex_unlock(&rs2_lock);
    struct sockaddr_in* a = (struct sockaddr_in*)&out->ss[0];
    memset(&out->ss[0], 0, sizeof(out->ss[0]));
    a->sin_family = AF_INET;
    a->sin_port = htons((unsigned short)port);
    a->sin_addr.s_addr = htonl(0x7f000001u);
    out->len[0] = (socklen_t)sizeof(*a);
    out->n = 1;
    return 0;
}

TEST(http_resolver_looks_up_beside_a_slow_name) {
    rs_reset(1, 0);
    rs2_release = 0;
    rs2_started = 0;
    HttpResolver* r = http_resolver_new(rs_on_answer, NULL);
    if (!r) return;
    http_resolver_set_lookup(r, rs2_lookup);
    struct AetherAddrList a;
    /* One thread, made idle again by a lookup that ends at once. */
    ASSERT_EQ(0, http_resolver_answer(r, "first.test", 80, &a));
    ASSERT_EQ(1, rs_wait_for(&rs_answered, 1));
    /* Two names back to back: one held, one not. */
    ASSERT_EQ(0, http_resolver_answer(r, "held.test", 80, &a));
    ASSERT_EQ(0, http_resolver_answer(r, "quick.test", 80, &a));
    ASSERT_EQ(2, rs_wait_for(&rs_answered, 2));   /* quick.test, held or not */
    ASSERT_EQ(1, http_resolver_answer(r, "quick.test", 80, &a));
    pthread_mutex_lock(&rs2_lock);
    rs2_release = 1;
    pthread_cond_broadcast(&rs2_cond);
    pthread_mutex_unlock(&rs2_lock);
    ASSERT_EQ(3, rs_wait_for(&rs_answered, 3));
    http_resolver_free(r);
}

/* The proxy event loop with a lookup held (#3267, #3283). Requests to a name
 * the resolver has not answered wait on the loop without holding its
 * drivers: a request to every driver that needs no lookup is answered
 * meanwhile. They share the one lookup and are answered when it is; one
 * whose client left while it waited takes nothing down with it. And the
 * upstream timeout covers the wait and the call after it together: a lookup
 * held 700 ms ahead of an upstream that takes 700 ms, under a one second
 * timeout, is a 504, where the wait used to come on top of the timeout and
 * the request was answered 200 after 1.4 s. */
int http_server_port(HttpServer* server);

static void rs_ok(HttpRequest* req, HttpServerResponse* res, void* ud) {
    (void)req;
    if (ud) usleep(700000);              /* the slow upstream */
    http_response_set_status(res, 200);
    http_response_set_body(res, "ok");
}

/* Bound to 127.0.0.1 and started; each caller sets that host on the server
 * it creates too, where the suite's loopback check sees it. */
static HttpServer* rs_start(HttpServer* s) {
    if (http_server_bind_raw(s, "127.0.0.1", 0) != 0) return NULL;
    if (http_server_start_background_raw(s) != 0) return NULL;
    return s;
}

static int rs_send(int port, const char* path) {
    int fd = (int)socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) return -1;
    struct sockaddr_in a;
    memset(&a, 0, sizeof(a));
    a.sin_family = AF_INET;
    a.sin_port = htons((unsigned short)port);
    a.sin_addr.s_addr = htonl(0x7f000001u);
    char req[256];
    int n = snprintf(req, sizeof(req), "GET %s HTTP/1.1\r\nHost: t\r\n\r\n", path);
    if (connect(fd, (struct sockaddr*)&a, sizeof(a)) != 0 ||
        send(fd, req, (size_t)n, 0) != n) {
        close(fd);
        return -1;
    }
    return fd;
}

/* The status of the response on `fd`, 0 when none came in `ms`. */
static int rs_status(int fd, int ms) {
    char buf[1024];
    int got = 0;
    int64_t due = rs_now_ms() + ms;
    while (got < (int)sizeof(buf) - 1) {
        int64_t left = due - rs_now_ms();
        if (left <= 0) break;
        struct pollfd p = { fd, POLLIN, 0 };
        if (poll(&p, 1, (int)left) <= 0) break;
        int n = (int)recv(fd, buf + got, sizeof(buf) - 1 - (size_t)got, 0);
        if (n <= 0) break;
        got += n;
        buf[got] = '\0';
        if (strstr(buf, "\r\n\r\n")) return got >= 12 ? atoi(buf + 9) : 0;
    }
    return 0;
}

/* A gateway proxying /p to `upstream`, and what it was built from, which the
 * caller frees after the server, as the mount asks. */
typedef struct {
    HttpServer*      server;
    AetherProxyPool* pool;
    AetherProxyOpts* opts;
} RsGateway;

static int rs_gateway(RsGateway* g, const char* upstream, int timeout_sec) {
    HttpServer* gw = http_server_create(0);
    if (gw) http_server_set_host(gw, "127.0.0.1");
    g->server = gw;
    g->pool = aether_proxy_pool_new(AETHER_PROXY_LB_ROUND_ROBIN, timeout_sec, 0, 0);
    g->opts = aether_proxy_opts_new();
    if (!g->server || !g->pool || !g->opts) return 0;
    if (*aether_proxy_upstream_add(g->pool, upstream, 1) ||
        *aether_proxy_use_reverse_proxy(g->server, "/p", g->pool, g->opts))
        return 0;
    if (!rs_start(g->server)) return 0;
    /* The server's own thread starts the loop, after start returns: give it
     * a moment. A build without the loop never has one. */
    for (int i = 0; i < 300 && !*(void* volatile*)&g->server->evloop; i++) usleep(10000);
    return 1;
}

static void rs_gateway_free(RsGateway* g) {
    if (g->server) {
        http_server_stop(g->server);
        http_server_free(g->server);
    }
    if (g->opts) aether_proxy_opts_free(g->opts);
    if (g->pool) aether_proxy_pool_free(g->pool);
}

TEST_CATEGORY(http_proxy_loop_waits_on_a_lookup_without_holding_its_drivers,
              TEST_CATEGORY_NETWORK) {
    HttpServer* up = http_server_create(0);
    ASSERT_NOT_NULL(up);
    http_server_set_host(up, "127.0.0.1");
    http_server_get(up, "/p", rs_ok, NULL);
    http_server_get(up, "/p/slow", rs_ok, (void*)1);
    ASSERT_NOT_NULL(rs_start(up));
    int up_port = http_server_port(up);
    char url[64];
    snprintf(url, sizeof(url), "http://slow.test:%d", up_port);

    RsGateway g = { 0 }, g2 = { 0 };
    ASSERT_TRUE(rs_gateway(&g, url, 1));
    if (!g.server->evloop) {             /* no loop on this build: nothing to see */
        rs_gateway_free(&g);
        http_server_stop(up);
        http_server_free(up);
        return;
    }
    rs_reset(0, 0);
    http_resolver_set_lookup(http_evloop_resolver((HttpEvLoop*)g.server->evloop), rs_lookup);
    int port = http_server_port(g.server);

    int a = rs_send(port, "/p");
    int b = rs_send(port, "/p");
    int gone = rs_send(port, "/p");
    ASSERT_TRUE(a >= 0 && b >= 0 && gone >= 0);
    ASSERT_EQ(1, rs_wait_for(&rs_lookups, 1));
    close(gone);                         /* its client leaves while it waits */
    /* No driver is held: a request that needs no lookup, one more than there
     * can be drivers, each answered by the path that serves it. */
    for (int i = 0; i < 9; i++) {
        int h = rs_send(port, "/health");
        ASSERT_TRUE(h >= 0);
        int status = rs_status(h, 3000);
        close(h);
        ASSERT_EQ(404, status);
    }
    ASSERT_EQ(0, rs_status(a, 100));     /* still waiting on the lookup */
    rs_let_go();
    ASSERT_EQ(200, rs_status(a, 3000));
    ASSERT_EQ(200, rs_status(b, 3000));
    ASSERT_EQ(1, rs_lookups);            /* one lookup for all three */
    close(a);
    close(b);

    /* The timeout covers the lookup and the call together (#3283). A name of
     * its own: the client's pool holds connections to slow.test now, and a
     * pooled connection needs no lookup. */
    rs_reset(0, 0);
    snprintf(url, sizeof(url), "http://slow2.test:%d", up_port);
    ASSERT_TRUE(rs_gateway(&g2, url, 1));
    http_resolver_set_lookup(http_evloop_resolver((HttpEvLoop*)g2.server->evloop), rs_lookup);
    int c = rs_send(http_server_port(g2.server), "/p/slow");
    ASSERT_TRUE(c >= 0);
    ASSERT_EQ(1, rs_wait_for(&rs_lookups, 1));
    usleep(700000);
    rs_let_go();
    int64_t t0 = rs_now_ms();
    int status = rs_status(c, 3000);
    printf("  a call after a 700 ms lookup, under a 1 s timeout: %d after %lld ms more\n",
           status, (long long)(rs_now_ms() - t0));
    close(c);
    ASSERT_EQ(504, status);

    rs_gateway_free(&g2);
    rs_gateway_free(&g);
    http_server_stop(up);
    http_server_free(up);
}
#endif
