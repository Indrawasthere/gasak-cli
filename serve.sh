#!/bin/bash

# ─────────────────────────────────────────────────────────────
# GASAK DIST SERVER - Server Supeng Side (Secure & Hardcoded Port)
# ─────────────────────────────────────────────────────────────

set -euo pipefail

DIST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIST_DIR" || exit 1

chmod +x gasak 2>/dev/null || true

echo "-> Starting SECURE distribution server on port 9001..."

# Jalankan python server dengan whitelist system secara inline (Port 9001 di-hardcode biar gak dicolong bash)
python3 -c "
import http.server
import socketserver
import os

ALLOWED_FILES = {
    'gasak',
    'install.sh',
    'log_cleaner.py',
    'deploy_parkee.py',
    'settlement_rfs.py',
    'decode_and_merge.py',
    'version.txt',
    'server.properties'
}

class SecureGasakDistHandler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        requested_file = os.path.basename(self.path.strip('/'))

        # Blokir jika akses root atau file di luar whitelist
        if self.path == '/' or (requested_file and requested_file not in ALLOWED_FILES):
            self.send_error(404, 'File Not Found')
            return

        super().do_GET()

    def end_headers(self):
        self.send_header('Cache-Control', 'no-store, no-cache, must-revalidate')
        self.send_header('Pragma', 'no-cache')
        self.send_header('Expires', '0')
        super().end_headers()

    def guess_type(self, path):
        if os.path.basename(path) == 'gasak':
            return 'application/octet-stream'
        return super().guess_type(path)

socketserver.TCPServer.allow_reuse_address = True
with socketserver.TCPServer(('', 9001), SecureGasakDistHandler) as httpd:
    httpd.serve_forever()
"
