#!/bin/bash

# ─────────────────────────────────────────────────────────────
# GASAK DIST SERVER - BULLETPROOF PRODUCTION EDITION
# Melayani file distribusi toolchain via HTTP port 9001
# ─────────────────────────────────────────────────────────────

set -euo pipefail

DIST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIST_DIR" || exit 1

# Pastikan permission file dasar di server sudah benar sebelum di-serve
chmod +x gasak       2>/dev/null || true
chmod +x install.sh  2>/dev/null || true
chmod 644 *.py       2>/dev/null || true
chmod 644 version.txt server.properties 2>/dev/null || true

echo "========================================================="
echo "-> GASAK Distribution Server starting on port :9001"
echo "-> Serving from: ${DIST_DIR}"
echo "-> Checking available components to distribute:"
echo "========================================================="

ALL_FILES=(
    "gasak" "install.sh" "decode_and_merge.py" "deploy_parkee.py"
    "log_cleaner.py" "settlement_rfs.py" "version.txt" "server.properties"
)

for f in "${ALL_FILES[@]}"; do
    if [ -f "$DIST_DIR/$f" ]; then
        SIZE=$(du -sh "$DIST_DIR/$f" 2>/dev/null | cut -f1)
        echo "   [✔] ${f} (${SIZE}) ready to serve."
    else
        echo "   [✘] ${f} — MISSING! (Tim bakal gagal download file ini)"
    fi
done
echo "========================================================="
echo ""

# Jalankan HTTP server Python dengan pengaman Whitelist & Custom Header
python3 << 'PYEOF'
import http.server
import socketserver
import os
import sys
from datetime import datetime

PORT = 9001

class GasakDistHandler(http.server.SimpleHTTPRequestHandler):
    # Pengaman utama: Hanya file yang terdaftar di sini yang boleh diunduh client
    WHITELIST = [
        'gasak', 'install.sh', 'serve.sh',
        'decode_and_merge.py', 'deploy_parkee.py',
        'log_cleaner.py', 'settlement_rfs.py',
        'version.txt', 'server.properties'
    ]

    def do_GET(self):
        # Ambil nama file murni dari path request
        filename = os.path.basename(self.path.split('?')[0])

        # Jika akses root atau kosong, default arahkan ke install.sh
        if not filename or filename == '':
            filename = 'install.sh'

        # Proteksi Keamanan Whitelist
        if filename not in self.WHITELIST:
            self.send_error(403, f"Akses Ditolak: File '{filename}' tidak di-whitelist oleh system GASAK!")
            return

        # Cek ketersediaan file fisik
        if not os.path.exists(filename):
            self.send_error(404, f"File Tidak Ditemukan: Ekstensi/File '{filename}' tidak ada di server!")
            return

        # Mengirimkan file ke client secara aman
        try:
            self.send_response(200)
            self.send_header('Content-Type', self.guess_type(filename))
            stat = os.stat(filename)
            self.send_header('Content-Length', str(stat.st_size))
            self.send_header('Cache-Control', 'no-cache, no-store, must-revalidate')
            self.end_headers()

            with open(filename, 'rb') as f:
                self.wfile.write(f.read())
        except Exception as e:
            self.log_message(f"Error serving {filename}: {str(e)}")

    def guess_type(self, path):
        basename = os.path.basename(path)
        # Deteksi tipe file agar browser/curl mengunduh biner secara tepat
        if basename == 'gasak':
            return 'application/octet-stream'
        if basename.endswith('.sh'):
            return 'text/plain; charset=utf-8'
        if basename.endswith('.py'):
            return 'text/plain; charset=utf-8'
        if basename.endswith('.txt') or basename.endswith('.properties'):
            return 'text/plain; charset=utf-8'
        return 'application/octet-stream'

    def log_message(self, format, *args):
        # Format log agar rapi terpantau di dist_server.log
        timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
        client_ip = self.client_address[0]
        msg = format % args
        print(f"[{timestamp}] {client_ip} - {msg}", flush=True)

socketserver.TCPServer.allow_reuse_address = True

try:
    with socketserver.TCPServer(('', PORT), GasakDistHandler) as httpd:
        print(f"[OK] Server listening on port {PORT}", flush=True)
        print(f"[OK] Client install command:", flush=True)
        print(f"     curl -fsSL http://10.70.0.110:{PORT}/install.sh | bash", flush=True)
        print("", flush=True)
        httpd.serve_forever()
except KeyboardInterrupt:
    print("\n[!] Server dihentikan secara manual.")
    sys.exit(0)
except OSError as e:
    print(f"\n[!] Gagal menjalankan server: {e}")
    sys.exit(1)
PYEOF
