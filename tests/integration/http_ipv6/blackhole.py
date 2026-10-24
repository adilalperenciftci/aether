# Holds [::1]:PORT so that a connect to it hangs rather than completing or
# being refused: a listener with a backlog of 0, its queue filled and never
# accepted, drops further SYNs. That is Linux; macOS completes the handshake
# anyway, so the runner uses this on Linux only. It stands in for an address
# that answers slowly, which is what ::1 is on Windows for a server on
# 127.0.0.1 alone (a refused SYN is retried for about two seconds there).
#
#   blackhole.py PORT READYFILE   writes READYFILE once the queue is full,
#                                 then holds until killed
import socket
import sys
import time

port = int(sys.argv[1])
b = socket.socket(socket.AF_INET6, socket.SOCK_STREAM)
b.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 1)
b.bind(("::1", port))
b.listen(0)
held = []
for _ in range(4):
    c = socket.socket(socket.AF_INET6, socket.SOCK_STREAM)
    c.setblocking(False)
    try:
        c.connect(("::1", port))
    except BlockingIOError:
        pass
    held.append(c)
time.sleep(0.2)
with open(sys.argv[2], "w") as f:
    f.write("ready\n")
while True:
    time.sleep(1)
