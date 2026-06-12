#!/bin/bash

# ─────────────────────────────────────────────────────────────
# GASAK DIST SERVER - Server Supeng Side
# ─────────────────────────────────────────────────────────────

set -euo pipefail

PORT=9001
DIST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

cd "$DIST_DIR" || exit 1

chmod +x gasak 2>/dev/null || true

echo "-> Starting distribution server on port ${PORT}..."

# Jalankan python server internal dengan tipe inline script
python3 -c "
import http.server
import socketserver
import os
import sys

class GasakDistHandler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header('Cache-Control', 'no-store, no-cache, must-revalidate')
        super().end_headers()

    def guess_type(self, path):
        if os.path.basename(path) == 'gasak':
            return 'application/octet-stream'
        return super().guess_type(path)

socketserver.TCPServer.allow_reuse_address = True
with socketserver.TCPServer(('', ${PORT}), GasakDistHandler) as httpd:
    httpd.serve_forever()
"
