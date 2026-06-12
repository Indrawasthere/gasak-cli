#!/bin/bash

# ─────────────────────────────────────────────────────────────
# GASAK DIST SERVER - Bulletproof Edition
# Melayani file distribusi toolchain via HTTP port 9001
# ─────────────────────────────────────────────────────────────

set -euo pipefail

DIST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIST_DIR" || exit 1

# Fix permission file penting sebelum serve
chmod +x gasak       2>/dev/null || true
chmod +x install.sh  2>/dev/null || true
chmod 644 *.py       2>/dev/null || true
chmod 644 version.txt server.properties 2>/dev/null || true

echo "-> GASAK Distribution Server starting on :9001"
echo "-> Serving from: ${DIST_DIR}"
echo "-> Files available:"
for f in gasak install.sh deploy_parkee.py settlement_rfs.py decode_and_merge.py log_cleaner.py version.txt server.properties; do
    if [ -f "$DIST_DIR/$f" ]; then
        SIZE=$(du -sh "$DIST_DIR/$f" 2>/dev/null | cut -f1)
        echo "   ✔ ${f} (${SIZE})"
    else
        echo "   ✘ ${f} — MISSING!"
    fi
done
echo ""

# Jalankan HTTP server Python
# NOTE: Heredoc single-quote ('EOF') supaya tidak ada variable expansion
python3 << 'PYEOF'
import http.server
import socketserver
import os
import sys
import logging
from datetime import datetime

# ─── WHITELIST: File yang boleh diakses ─────────────────────
ALLOWED_FILES = {
    'gasak',
    'install.sh',
    'deploy_parkee.py',
    'settlement_rfs.py',
    'decode_and_merge.py',
    'log_cleaner.py',
    'version.txt',
    'server.properties',
}

class GasakDistHandler(http.server.SimpleHTTPRequestHandler):

    def do_GET(self):
        requested_file = os.path.basename(self.path.strip('/'))

        # Blokir root path atau file yang tidak di whitelist
        if not requested_file or requested_file not in ALLOWED_FILES:
            self.send_error(404, 'File Not Found or Not Allowed')
            return

        # Cek apakah file beneran ada di disk
        if not os.path.isfile(requested_file):
            self.send_error(404, f'File {requested_file} Not Found on Disk')
            return

        super().do_GET()

    def end_headers(self):
        # No-cache headers biar client selalu ambil versi terbaru
        self.send_header('Cache-Control', 'no-store, no-cache, must-revalidate, max-age=0')
        self.send_header('Pragma', 'no-cache')
        self.send_header('Expires', '0')
        super().end_headers()

    def guess_type(self, path):
        basename = os.path.basename(path)
        # Binary files
        if basename in ('gasak',):
            return 'application/octet-stream'
        # Shell scripts
        if basename.endswith('.sh'):
            return 'text/plain; charset=utf-8'
        # Python scripts
        if basename.endswith('.py'):
            return 'text/plain; charset=utf-8'
        return super().guess_type(path)

    def log_message(self, format, *args):
        # Custom log format with timestamp
        timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
        client_ip = self.client_address[0]
        msg = format % args
        print(f"[{timestamp}] {client_ip} - {msg}", flush=True)

# ─── START SERVER ─────────────────────────────────────────────
PORT = 9001

socketserver.TCPServer.allow_reuse_address = True

try:
    with socketserver.TCPServer(('', PORT), GasakDistHandler) as httpd:
        print(f"[OK] Server listening on port {PORT}", flush=True)
        print(f"[OK] Client install command:", flush=True)
        print(f"     curl -fsSL http://10.70.0.110:{PORT}/install.sh | bash", flush=True)
        print("", flush=True)
        httpd.serve_forever()
except KeyboardInterrupt:
    print("\n[!] Server dihentikan.")
    sys.exit(0)
except OSError as e:
    if e.errno == 98:  # Address already in use
        print(f"[ERROR] Port {PORT} sudah dipakai proses lain!")
        print(f"        Kill dulu: sudo kill -9 $(sudo lsof -t -i:{PORT})")
        sys.exit(1)
    raise
PYEOF
