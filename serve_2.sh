#!/bin/bash

# ─────────────────────────────────────────────────────────────
# GASAK DIST SERVER - Server Supeng Side (Secure Edition)
# ─────────────────────────────────────────────────────────────

set -euo pipefail

PORT=9001
DIST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

cd "$DIST_DIR" || exit 1

chmod +x gasak 2>/dev/null || true

echo "-> Starting SECURE distribution server on port ${PORT}..."

# Jalankan python server dengan whitelist system
python3 - -c "
import http.server
import socketserver
import os
import sys

# Hanya file-file ini yang boleh ditarik oleh user lapangan/client
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
        # Bersihkan path untuk mengambil nama file saja
        requested_file = os.path.basename(self.path.strip('/'))
        
        # Jika user mengakses root (/) atau file yang tidak ada di whitelist, blokir!
        if self.path == '/' or (requested_file and requested_file not in ALLOWED_FILES):
            self.send_error(404, 'File Not Found atau Akses Ditolak Men')
            return
            
        # Jika lolos verifikasi, jalankan fungsi download bawaan python
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
with socketserver.TCPServer(('', ${PORT}), SecureGasakDistHandler) as httpd:
    httpd.serve_forever()
"
