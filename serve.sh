#!/bin/bash

# ─────────────────────────────────────────────────────────────
# GASAK DIST SERVER — ULTIMATE EDITION v2.0
# Melayani file distribusi toolchain via HTTP port 9001
# Features: Client Tracking, Live Dashboard, Checksums, Status API
# ─────────────────────────────────────────────────────────────

set -euo pipefail

DIST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIST_DIR" || exit 1

chmod 755 gasak          2>/dev/null || true
chmod 755 install.sh     2>/dev/null || true
chmod 755 serve.sh       2>/dev/null || true
chmod 755 gasak.exe      2>/dev/null || true
chmod 644 ./*.py         2>/dev/null || true
chmod 644 ./*.zip        2>/dev/null || true
chmod 644 version.txt    2>/dev/null || true
chmod 644 server.properties 2>/dev/null || true
chmod 755 reinstall-vault.sh 2>/dev/null || true

echo ""
echo -e "\033[0;35m  ██████╗  █████╗ ███████╗ █████╗ ██╗  ██╗\033[0m"
echo -e "\033[0;35m  ██╔════╝ ██╔══██╗██╔════╝██╔══██╗██║ ██╔╝\033[0m"
echo -e "\033[0;35m  ██║   ███╗███████║███████╗███████║█████╔╝\033[0m"
echo -e "\033[0;35m  ██║   ██║██╔══██║╚════██║██╔══██║██╔═██╗\033[0m"
echo -e "\033[0;35m  ╚██████╔╝██║  ██║███████║██║  ██║██║  ██╗\033[0m"
echo -e "\033[0;35m   ╚═════╝ ╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝\033[0m"
echo ""
echo -e "\033[1;37m  ╔═══════════════════════════════════════════════════════════╗\033[0m"
echo -e "\033[1;37m  ║\033[0m  \033[0;36mGASAK DISTRIBUTION SERVER\033[0m  \033[2mv2.0 — Ultimate Edition\033[0m       \033[1;37m║\033[0m"
echo -e "\033[1;37m  ╚═══════════════════════════════════════════════════════════╝\033[0m"
echo ""

ALL_FILES=(
    "gasak"
    "gasak.exe"
    "install.sh"
    "install.ps1"
    "decode_and_merge.py"
    "deploy_parkee.py"
    "deploy_parkee_win.py"
    "log_cleaner.py"
    "settlement_rfs.py"
    "version.txt"
    "server.properties"
    "reinstall-vault.sh"
    "reader_script.sh"
    "update_reader.sh"
    "jellies_scripts.zip"
    "parque-fw-14.zip"
    "parque-fw-17.zip"
    "parque-fw-19.zip"
    "parque-v1.00.17-905e5f60e.zip"
    "parque-v1.00.19-625929d22.zip"
    "v1.00.14-f577de6e5.zip"
)

echo -e "  \033[1;36mChecking distribution files...\033[0m"
ALL_OK=true
for f in "${ALL_FILES[@]}"; do
    if [ -f "$DIST_DIR/$f" ]; then
        SIZE=$(du -sh "$DIST_DIR/$f" 2>/dev/null | cut -f1)
        printf "  \033[0;32m✔\033[0m %-30s %s\n" "$f" "($SIZE)"
    else
        printf "  \033[0;31m✘\033[0m %-30s \033[0;31mMISSING!\033[0m\n" "$f"
        ALL_OK=false
    fi
done

if [ "$ALL_OK" = false ]; then
    echo ""
    echo -e "  \033[1;33m⚠ WARNING: Some files missing! Clients may fail to install.\033[0m"
fi

echo ""
echo -e "  \033[2m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
echo ""

python3 << 'PYEOF'
import http.server
import socketserver
import os
import sys
import json
import hmac
import hashlib
import time
from datetime import datetime
from urllib.parse import urlparse, parse_qs
from collections import defaultdict

PORT = 9001
LOG_FILE = "dist_server.log"
CLIENTS_FILE = "clients.json"
START_TIME = time.time()

DIST_TOKEN = os.environ.get("GASAK_DIST_TOKEN", "")

stats = {
    "total_downloads": 0,
    "downloads_today": 0,
    "last_reset_date": datetime.now().strftime("%Y-%m-%d"),
    "file_downloads": defaultdict(int),
}

clients = {}

def load_clients():
    global clients
    if os.path.exists(CLIENTS_FILE):
        try:
            with open(CLIENTS_FILE, 'r') as f:
                clients = json.load(f)
        except:
            clients = {}

def save_clients():
    try:
        with open(CLIENTS_FILE, 'w') as f:
            json.dump(clients, f, indent=2)
    except:
        pass

def track_client(ip, hostname, version, user, filename):
    today = datetime.now().strftime("%Y-%m-%d")
    if stats["last_reset_date"] != today:
        stats["downloads_today"] = 0
        stats["last_reset_date"] = today

    stats["total_downloads"] += 1
    stats["downloads_today"] += 1
    stats["file_downloads"][filename] += 1

    if ip not in clients:
        clients[ip] = {
            "hostname": hostname,
            "version": version,
            "user": user,
            "first_seen": datetime.now().isoformat(),
            "downloads": []
        }

    clients[ip]["hostname"] = hostname
    clients[ip]["version"] = version
    clients[ip]["user"] = user
    clients[ip]["last_seen"] = datetime.now().isoformat()
    if filename not in clients[ip]["downloads"]:
        clients[ip]["downloads"].append(filename)
    if len(clients[ip]["downloads"]) > 20:
        clients[ip]["downloads"] = clients[ip]["downloads"][-20:]

    save_clients()

def get_uptime():
    seconds = int(time.time() - START_TIME)
    hours = seconds // 3600
    minutes = (seconds % 3600) // 60
    if hours > 0:
        return f"{hours}h {minutes}m"
    return f"{minutes}m"

def get_latest_version():
    try:
        with open("version.txt", "r") as f:
            return f.read().strip()
    except:
        return "unknown"

def generate_checksums():
    checksums = {}
    files = [
        "gasak", "gasak.exe", "install.sh", "install.ps1","decode_and_merge.py", "deploy_parkee.py", "deploy_parkee_win.py", "settlement_rfs_win.py", "decode_and_merge_win.py", "log_cleaner.py", "settlement_rfs.py", "server.properties", "reader_script.sh"
    ]
    for f in files:
        if os.path.exists(f):
            with open(f, 'rb') as fh:
                checksums[f] = hashlib.sha256(fh.read()).hexdigest()
    return checksums

class GasakDistHandler(http.server.SimpleHTTPRequestHandler):
    WHITELIST = [
        'gasak', 'gasak.exe', 'install.sh', 'install.ps1', 'serve.sh',
        'decode_and_merge.py', 'decode_and_merge_win.py', 'deploy_parkee.py',
        'deploy_parkee_win.py', 'settlement_rfs_win.py', 'log_cleaner.py',
        'settlement_rfs.py', 'version.txt', 'server.properties',
        'reinstall-vault.sh', 'reader_script.sh', 'update_reader.sh',
        'jellies_scripts.zip', 'parque-fw-14.zip', 'parque-fw-17.zip', 'parque-fw-19.zip',
        'parque-v1.00.17-905e5f60e.zip', 'parque-v1.00.19-625929d22.zip', 'v1.00.14-f577de6e5.zip',
    ]

    def do_GET(self):
        parsed = urlparse(self.path)
        filename = os.path.basename(parsed.path.split('?')[0])

        if parsed.path == '/status':
            self.handle_status()
            return

        if parsed.path == '/clients':
            self.handle_clients()
            return

        if parsed.path == '/checksums.sha256':
            self.handle_checksums()
            return

        if parsed.path == '/logs':
            self.handle_logs(parsed)
            return

        if parsed.path.startswith('/getenv'):
            self.handle_getenv(parsed)
            return

        if not filename or filename in ('', '/'):
            filename = 'install.sh'

        if filename not in self.WHITELIST:
            self.log_request_detail(403, filename, "DENIED (not whitelisted)")
            self.send_error(403, f"Access Denied: '{filename}' is not in GASAK distribution whitelist.")
            return

        filepath = os.path.join(os.getcwd(), filename)
        if not os.path.isfile(filepath):
            self.log_request_detail(404, filename, "NOT FOUND")
            self.send_error(404, f"File Not Found: '{filename}' does not exist on server.")
            return

        client_ip = self.client_address[0]
        hostname = self.headers.get('X-Gasak-Host', 'unknown-device')
        version = self.headers.get('X-Gasak-Version', 'unknown')
        user = self.headers.get('X-Gasak-User', 'unknown')

        track_client(client_ip, hostname, version, user, filename)

        try:
            file_size = os.path.getsize(filepath)
            content_type = self.detect_content_type(filename)

            self.send_response(200)
            self.send_header('Content-Type', content_type)
            self.send_header('Content-Length', str(file_size))
            self.send_header('Cache-Control', 'no-cache, no-store, must-revalidate')
            self.send_header('X-GASAK-Server', 'ParkeeDistServer/2.0')
            self.end_headers()

            with open(filepath, 'rb') as f:
                while True:
                    chunk = f.read(1048576)
                    if not chunk:
                        break
                    self.wfile.write(chunk)

            self.log_request_detail(200, filename, f"OK ({file_size} bytes) — {user}@{hostname} v{version}")

        except BrokenPipeError:
            self.log_request_detail(0, filename, "CLIENT DISCONNECTED")
        except Exception as e:
            self.log_request_detail(500, filename, f"ERROR: {e}")

    def handle_status(self):
        data = {
            "server": "GASAK Distribution Server",
            "version": "2.0",
            "uptime": get_uptime(),
            "started_at": datetime.fromtimestamp(START_TIME).isoformat(),
            "latest_version": get_latest_version(),
            "files_available": len([f for f in self.WHITELIST if os.path.exists(f)]),
            "clients_tracked": len(clients),
            "total_downloads": stats["total_downloads"],
            "downloads_today": stats["downloads_today"],
        }

        response = json.dumps(data, indent=2)
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(response)))
        self.end_headers()
        self.wfile.write(response.encode())

        self.log_request_detail(200, '/status', f"OK — {len(clients)} clients tracked")

    def handle_clients(self):
        client_list = []
        for ip, info in sorted(clients.items(), key=lambda x: x[1].get('last_seen', ''), reverse=True):
            client_list.append({
                "ip": ip,
                "hostname": info.get("hostname", "unknown"),
                "version": info.get("version", "unknown"),
                "user": info.get("user", "unknown"),
                "last_seen": info.get("last_seen", "never"),
                "total_downloads": len(info.get("downloads", [])),
            })

        data = {
            "total_clients": len(client_list),
            "clients": client_list[:50]
        }

        response = json.dumps(data, indent=2)
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(response)))
        self.end_headers()
        self.wfile.write(response.encode())

        self.log_request_detail(200, '/clients', f"OK — {len(client_list)} clients")

    def handle_checksums(self):
        checksums = generate_checksums()
        lines = [f"{hash}  {filename}" for filename, hash in checksums.items()]
        response = "\n".join(lines) + "\n"

        self.send_response(200)
        self.send_header('Content-Type', 'text/plain; charset=utf-8')
        self.send_header('Content-Length', str(len(response)))
        self.end_headers()
        self.wfile.write(response.encode())

        self.log_request_detail(200, '/checksums.sha256', f"OK — {len(checksums)} checksums")

    def handle_logs(self, parsed):
        params = parse_qs(parsed.query)
        try:
            num_lines = int(params.get('lines', ['20'])[0])
        except:
            num_lines = 20

        try:
            if os.path.exists(LOG_FILE):
                with open(LOG_FILE, 'r', errors='replace') as f:
                    all_lines = f.readlines()
                    recent = all_lines[-num_lines:]
                    response = "".join(recent)
            else:
                response = "No logs available\n"
        except Exception as e:
            response = f"Error reading logs: {e}\n"

        self.send_response(200)
        self.send_header('Content-Type', 'text/plain; charset=utf-8')
        self.send_header('Content-Length', str(len(response)))
        self.send_header('Cache-Control', 'no-cache, no-store, must-revalidate')
        self.end_headers()
        self.wfile.write(response.encode())

        self.log_request_detail(200, '/logs', f"OK — {num_lines} lines")

    def handle_getenv(self, parsed):
        params = parse_qs(parsed.query)
        token = params.get('token', [''])[0]
        client_ip = self.client_address[0]

        if not DIST_TOKEN:
            self.log_request_detail(503, 'getenv', "SERVER MISCONFIGURED — GASAK_DIST_TOKEN not set")
            self.send_error(503, "Server misconfigured: GASAK_DIST_TOKEN not set.")
            return

        if not hmac.compare_digest(token, DIST_TOKEN):
            self.log_request_detail(403, 'getenv', f"DENIED — invalid token from {client_ip}")
            self.send_error(403, "Access Denied: invalid distribution token.")
            return

        env_path = os.path.join(os.getcwd(), '.env')
        if not os.path.isfile(env_path):
            self.log_request_detail(404, 'getenv', ".env NOT FOUND on server")
            self.send_error(404, ".env not found on server — hubungi Fadlan.")
            return

        try:
            file_size = os.path.getsize(env_path)
            self.send_response(200)
            self.send_header('Content-Type', 'text/plain; charset=utf-8')
            self.send_header('Content-Length', str(file_size))
            self.send_header('Cache-Control', 'no-cache, no-store, must-revalidate')
            self.send_header('X-GASAK-Server', 'ParkeeDistServer/2.0')
            self.end_headers()

            with open(env_path, 'rb') as f:
                self.wfile.write(f.read())

            self.log_request_detail(200, 'getenv', f"OK — .env served ({file_size} bytes) to {client_ip}")

        except BrokenPipeError:
            self.log_request_detail(0, 'getenv', "CLIENT DISCONNECTED")
        except Exception as e:
            self.log_request_detail(500, 'getenv', f"ERROR: {e}")

    def detect_content_type(self, filename):
        if filename == 'gasak':
            return 'application/octet-stream'
        if filename.endswith(('.sh', '.ps1')):
            return 'text/plain; charset=utf-8'
        if filename.endswith('.py'):
            return 'text/plain; charset=utf-8'
        if filename.endswith(('.txt', '.properties', '.env')):
            return 'text/plain; charset=utf-8'
        return 'application/octet-stream'

    def log_request_detail(self, code, filename, status):
        timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
        client_ip = self.client_address[0]

        if code == 200:
            code_color = f"\033[32m{code}\033[0m"
        elif code in (403, 404):
            code_color = f"\033[33m{code}\033[0m"
        elif code >= 500 or code == 0:
            code_color = f"\033[31m{code}\033[0m"
        else:
            code_color = str(code)

        msg_plain = f"[{timestamp}] {client_ip:15s} | {code} | {filename:35s} | {status}"
        msg_color = f"[{timestamp}] {client_ip:15s} | {code_color} | {filename:35s} | {status}"

        print(msg_color, flush=True)
        try:
            with open(LOG_FILE, 'a') as lf:
                lf.write(msg_plain + '\n')
        except Exception:
            pass

    def log_message(self, format, *args):
        pass

def print_dashboard():
    print("\033[2J\033[H", end="")
    print("\033[0;35m  ██████╗  █████╗ ███████╗ █████╗ ██╗  ██╗\033[0m")
    print("\033[0;35m  ██╔════╝ ██╔══██╗██╔════╝██╔══██╗██║ ██╔╝\033[0m")
    print("\033[0;35m  ██║   ███╗███████║███████╗███████║█████╔╝\033[0m")
    print("\033[0;35m  ██║   ██║██╔══██║╚════██║██╔══██║██╔═██╗\033[0m")
    print("\033[0;35m  ╚██████╔╝██║  ██║███████║██║  ██║██║  ██╗\033[0m")
    print("\033[0;35m   ╚═════╝ ╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝\033[0m")
    print()
    print("\033[1;37m  ╔═══════════════════════════════════════════════════════════╗\033[0m")
    print("\033[1;37m  ║\033[0m  \033[0;36mGASAK DISTRIBUTION SERVER\033[0m  \033[2mv2.0 — Ultimate Edition\033[0m       \033[1;37m║\033[0m")
    print("\033[1;37m  ╚═══════════════════════════════════════════════════════════╝\033[0m")
    print()
    print(f"  \033[1;36mStatus:\033[0m Running on port {PORT}")
    print(f"  \033[1;36mStarted:\033[0m {datetime.fromtimestamp(START_TIME).strftime('%Y-%m-%d %H:%M:%S')}")
    print(f"  \033[1;36mUptime:\033[0m  {get_uptime()}")
    print(f"  \033[1;36mVersion:\033[0m {get_latest_version()}")
    print()
    print(f"  \033[1;33m[STATS]\033[0m Downloads Today: \033[1;32m{stats['downloads_today']}\033[0m | Total: \033[1;32m{stats['total_downloads']}\033[0m | Clients: \033[1;32m{len(clients)}\033[0m")
    print()
    print("  \033[1;36m[RECENT CLIENTS]\033[0m")
    if clients:
        sorted_clients = sorted(clients.items(), key=lambda x: x[1].get('last_seen', ''), reverse=True)[:10]
        for ip, info in sorted_clients:
            hostname = info.get('hostname', 'unknown')[:12]
            version = info.get('version', '?')
            user = info.get('user', '?')[:8]
            last_seen = info.get('last_seen', 'never')
            try:
                last_dt = datetime.fromisoformat(last_seen)
                diff = datetime.now() - last_dt
                if diff.days > 0:
                    ago = f"{diff.days}d ago"
                elif diff.seconds > 3600:
                    ago = f"{diff.seconds // 3600}h ago"
                elif diff.seconds > 60:
                    ago = f"{diff.seconds // 60}m ago"
                else:
                    ago = "just now"
            except:
                ago = "?"
            print(f"  {ip:15s} | {hostname:12s} | v{version:6s} | {user:8s} | {ago}")
    else:
        print("  \033[2mNo clients connected yet\033[0m")
    print()
    print("  \033[1;36m[ENDPOINTS]\033[0m")
    print(f"  \033[2m/                  — Install script\033[0m")
    print(f"  \033[2m/status            — Server status (JSON)\033[0m")
    print(f"  \033[2m/clients           — Client list (JSON)\033[0m")
    print(f"  \033[2m/checksums.sha256  — File checksums\033[0m")
    print(f"  \033[2m/getenv?token=xxx  — Get .env (auth required)\033[0m")
    print()
    print("\033[2m  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m")
    print(f"  \033[2mLog: {os.path.join(os.getcwd(), LOG_FILE)}\033[0m")
    print(f"  \033[2mClients: {os.path.join(os.getcwd(), CLIENTS_FILE)}\033[0m")
    print()
    print("  \033[1;33mPress Ctrl+C to stop server\033[0m")
    print()

load_clients()

socketserver.TCPServer.allow_reuse_address = True

class ReusableTCPServer(socketserver.TCPServer):
    def serve_forever(self):
        while True:
            self.handle_request()

try:
    print_dashboard()

    with socketserver.TCPServer(('', PORT), GasakDistHandler) as httpd:
        print(f"\033[0;32m[OK]\033[0m Server listening on 0.0.0.0:{PORT}", flush=True)
        print(f"\033[0;32m[OK]\033[0m Install: curl -fsSL http://10.70.0.110:{PORT}/install.sh | bash", flush=True)
        print(f"\033[0;32m[OK]\033[0m Status: http://10.70.0.110:{PORT}/status", flush=True)
        print(f"\033[0;32m[OK]\033[0m Clients: http://10.70.0.110:{PORT}/clients", flush=True)
        print("", flush=True)
        httpd.serve_forever()
except KeyboardInterrupt:
    print("\n\033[1;33m[!] Server dihentikan (Ctrl+C).\033[0m", flush=True)
    save_clients()
    sys.exit(0)
except OSError as e:
    print(f"\n\033[0;31m[!] Gagal start server: {e}\033[0m", flush=True)
    print(f"    Port {PORT} mungkin masih dipakai. Cek: sudo lsof -i:{PORT}", flush=True)
    sys.exit(1)
PYEOF
