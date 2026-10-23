# same_bytes FILE1 FILE2: succeeds when the two files hold the same bytes.
#
# cmp comes from diffutils, which an MSYS2 install can lack (the Windows CI
# shell has none), and a test that called it there failed for a missing tool
# while reading as a wrong result ("cmp: command not found", then "wrong
# bytes"). cksum is in coreutils on every leg: it prints a CRC and the byte
# count, so two files with the same line hold the same bytes for any test's
# purpose. A file that cannot be read is never the same as anything.
same_bytes() {
    [ -r "$1" ] && [ -r "$2" ] || return 1
    if command -v cmp >/dev/null 2>&1; then
        cmp -s "$1" "$2"
    else
        [ "$(cksum < "$1")" = "$(cksum < "$2")" ]
    fi
}
