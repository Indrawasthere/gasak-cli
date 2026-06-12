#!/bin/bash

# ─────────────────────────────────────────────────────────────
# GASAK DIST SERVER — BULLETPROOF PRODUCTION EDITION
# Melayani file distribusi toolchain via HTTP port 9001
# ─────────────────────────────────────────────────────────────

set -euo pipefail

DIST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIST_DIR" || exit 1

# ─── FIX PERMISSIONS SEMUA FILE SEBELUM DI-SERVE ─────────────
chmod 755 gasak          2>/dev/null || true
chmod 755 install.sh     2>/dev/null || true
chmod 755 serve.sh       2>/dev/null || true
chmod 644 ./*.py         2>/dev/null || true
chmod 644 version.txt    2>/dev/null || true
chmod 644 server.properties 2>/dev/null || true
# .env di server TIDAK di-serve ke client (keamanan)

echo "═══════════════════════════════════════════════════════════"
echo "  GASAK Distribution Server — Port 9001"
echo "  Serving from: ${DIST_DIR}"
echo "  Started at: $(date '+%Y-%m-%d %H:%M:%S')"
echo "═══════════════════════════════════════════════════════════"
echo ""
echo "  Status file yang tersedia untuk distribusi:"
echo ""

ALL_FILES=(
    "gasak"
    "install.sh"
    "decode_and_merge.py"
    "deploy_parkee.py"
    "log_cleaner.py"
    "settlement_rfs.py"
    "version.txt"
    "server.properties"
)

ALL_OK=true
for f in "${ALL_FILES[@]}"; do
    if [ -f "$DIST_DIR/$f" ]; then
        SIZE=$(du -sh "$DIST_DIR/$f" 2>/dev/null | cut -f1)
        printf "  [✔] %-30s (%s)\n" "$f" "$SIZE"
    else
        printf "  [✘] %-30s MISSING!\n" "$f"
        ALL_OK=false
    fi
done

echo ""
echo "═══════════════════════════════════════════════════════════"

if [ "$ALL_OK" = false ]; then
    echo "  [!] WARNING: Ada file yang hilang! Client mungkin gagal install."
fi

echo ""

# ─── JALANKAN HTTP SERVER VIA PYTHON ─────────────────────────
python3 << 'PYEOF'
import http.server
import socketserver
import os
import sys
import json
from datetime import datetime

PORT = 9001
LOG_FILE = "dist_server.log"

class GasakDistHandler(http.server.SimpleHTTPRequestHandler):
    # Whitelist ketat: hanya file ini yang boleh diakses client
    # .env TIDAK masuk whitelist (keamanan — .env digenerate di sisi client)
    WHITELIST = [
        'gasak',
        'install.sh',
        'serve.sh',
        'decode_and_merge.py',
        'deploy_parkee.py',
        'log_cleaner.py',
        'settlement_rfs.py',
        'version.txt',
        'server.properties',
    ]

    def do_GET(self):
        # Ambil filename bersih dari path
        filename = os.path.basename(self.path.split('?')[0])

        # Default ke install.sh kalau akses root
        if not filename or filename in ('', '/'):
            filename = 'install.sh'

        # Security: tolak akses file di luar whitelist
        if filename not in self.WHITELIST:
            self.log_request_detail(403, filename, "DENIED (not whitelisted)")
            self.send_error(403, f"Access Denied: '{filename}' is not in GASAK distribution whitelist.")
            return

        # Cek file fisik ada
        filepath = os.path.join(os.getcwd(), filename)
        if not os.path.isfile(filepath):
            self.log_request_detail(404, filename, "NOT FOUND")
            self.send_error(404, f"File Not Found: '{filename}' does not exist on server.")
            return

        # Kirim file ke client
        try:
            file_size = os.path.getsize(filepath)
            content_type = self.detect_content_type(filename)

            self.send_response(200)
            self.send_header('Content-Type', content_type)
            self.send_header('Content-Length', str(file_size))
            self.send_header('Cache-Control', 'no-cache, no-store, must-revalidate')
            self.send_header('X-GASAK-Server', 'ParkeeDistServer/1.0')
            self.end_headers()

            with open(filepath, 'rb') as f:
                # Stream dalam chunk biar aman untuk file besar (binary gasak)
                while True:
                    chunk = f.read(65536)
                    if not chunk:
                        break
                    self.wfile.write(chunk)

            self.log_request_detail(200, filename, f"OK ({file_size} bytes)")

        except BrokenPipeError:
            # Client disconnect di tengah jalan — normal, jangan crash
            self.log_request_detail(0, filename, "CLIENT DISCONNECTED")
        except Exception as e:
            self.log_request_detail(500, filename, f"ERROR: {e}")

    def detect_content_type(self, filename):
        """Deteksi content-type yang tepat untuk tiap file"""
        if filename == 'gasak':
            return 'application/octet-stream'
        if filename.endswith('.sh'):
            return 'text/plain; charset=utf-8'
        if filename.endswith('.py'):
            return 'text/plain; charset=utf-8'
        if filename.endswith(('.txt', '.properties', '.env')):
            return 'text/plain; charset=utf-8'
        return 'application/octet-stream'

    def log_request_detail(self, code, filename, status):
        """Log dengan format yang bersih dan informatif"""
        timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
        client_ip = self.client_address[0]
        msg = f"[{timestamp}] {client_ip:15s} | {code} | {filename:35s} | {status}"
        print(msg, flush=True)
        # Tulis juga ke log file
        try:
            with open(LOG_FILE, 'a') as lf:
                lf.write(msg + '\n')
        except Exception:
            pass

    def log_message(self, format, *args):
        # Override default log supaya ga noise di stdout
        # Semua logging sudah ditangani log_request_detail
        pass

# ─── STARTUP ─────────────────────────────────────────────────
socketserver.TCPServer.allow_reuse_address = True

try:
    with socketserver.TCPServer(('', PORT), GasakDistHandler) as httpd:
        print(f"[OK] Server listening on 0.0.0.0:{PORT}", flush=True)
        print(f"[OK] Client install command:", flush=True)
        print(f"     curl -fsSL http://10.70.0.110:{PORT}/install.sh | bash", flush=True)
        print(f"[OK] Log: {os.path.join(os.getcwd(), LOG_FILE)}", flush=True)
        print("", flush=True)
        httpd.serve_forever()
except KeyboardInterrupt:
    print("\n[!] Server dihentikan (Ctrl+C).", flush=True)
    sys.exit(0)
except OSError as e:
    print(f"\n[!] Gagal start server: {e}", flush=True)
    print(f"    Kemungkinan port {PORT} masih dipakai. Cek: sudo lsof -i:{PORT}", flush=True)
    sys.exit(1)
PYEOF
SCRIPT_EOF
echo "DONE"
