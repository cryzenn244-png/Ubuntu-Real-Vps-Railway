#!/usr/bin/env python3
"""Internal readiness endpoint: only reports ready when VNC and websockify accept TCP connections."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import socket

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path != "/health":
            self.send_error(404)
            return
        ready = all(self._port_open(port) for port in (5901, 6081))
        body = b"ready\n" if ready else b"starting\n"
        self.send_response(200 if ready else 503)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)
    @staticmethod
    def _port_open(port):
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.5):
                return True
        except OSError:
            return False
    def log_message(self, fmt, *args):
        print("[miracle-health] " + fmt % args, flush=True)

ThreadingHTTPServer(("127.0.0.1", 9001), Handler).serve_forever()
