#!/usr/bin/env python3
# Stands in for GitHub in tests/release.sh: serves a folder that is laid out as GitHub's
# download addresses are, on this machine alone and at a port the system chooses, and says
# which port on its first line.
#   python3 tests/release-github.py <folder>
import http.server
import socketserver
import sys

folder = sys.argv[1]


class Server(http.server.ThreadingHTTPServer):
    # http.server looks up the name of the address it binds, and nothing here uses the name.
    # Packmoji found that lookup to take 35 seconds on one of GitHub's Macs.
    def server_bind(self):
        socketserver.TCPServer.server_bind(self)
        self.server_name, self.server_port = self.server_address[:2]


class Files(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=folder, **kwargs)

    # What was asked for, a line each, for whoever reads the log of a rehearsal that failed.
    def log_message(self, format, *args):
        print(format % args, flush=True)


server = Server(("127.0.0.1", 0), Files)
print(f"port {server.server_port}", flush=True)
server.serve_forever()
