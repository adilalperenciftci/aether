# The openssl CLI configuration a test that makes certificates uses (#2776).
#
#   . "$ROOT/tests/lib/test_openssl_conf.sh"
#   test_openssl_conf "$TMP"      # before the first `openssl req`
#
# Without a configuration of its own, `openssl req -x509` reads the machine's
# openssl.cnf, and what a certificate carries depends on it. OpenSSL 1.1.1's
# (the openssl on the macOS x86_64 runner) adds its v3_ca section, with a
# basicConstraints of its own, to every `req -x509`, and 1.1.1's -addext
# appends to those rather than replacing them: the test CA carried
# basicConstraints twice, which OpenSSL 3 refuses as "invalid certificate".
# This writes a configuration with nothing in it but what `req` requires,
# so a certificate carries the extensions its test asks for and no others,
# under any openssl, and exports OPENSSL_CONF to it.
test_openssl_conf() {
    printf '[ req ]\ndistinguished_name = req_dn\n[ req_dn ]\n' > "$1/openssl.cnf"
    if command -v cygpath >/dev/null 2>&1; then
        OPENSSL_CONF="$(cygpath -m "$1/openssl.cnf")"
    else
        OPENSSL_CONF="$1/openssl.cnf"
    fi
    export OPENSSL_CONF
}
