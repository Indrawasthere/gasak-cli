#!/bin/bash

# ─────────────────────────────────────────────────────────────
# GASAK AUTO-DEPLOYER
# Pipeline: compile → SCP semua aset → restart dist server
# Jalanin dari laptop dev setiap abis update kode / skrip
# ─────────────────────────────────────────────────────────────

set -euo pipefail

# ─── CONFIG ──────────────────────────────────────────────────

LOCAL_PROJECT_DIR="$HOME/Documents/Project/gasak"
LOCAL_DIST_DIR="$HOME/gasak-dist"

SUPENG_USER="parkee"
SUPENG_IP="10.70.0.110"
SUPENG_DIR="/home/parkee/gasak-dist"
SSH_KEY="$HOME/.ssh/id_rsa"

GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
RESET='\033[0m'

# ─── HELPER ──────────────────────────────────────────────────

step() { echo -e "\n${YELLOW}[$1] $2${RESET}"; }
ok()   { echo -e "${GREEN}✔ $1${RESET}"; }
err()  { echo -e "${RED}✘ $1${RESET}" >&2; }
info() { echo -e "   ${CYAN}-> $1${RESET}"; }

# ─── PRE-FLIGHT ──────────────────────────────────────────────

clear
echo -e "${CYAN}────────────────────────────────────────────────────────────${RESET}"
echo -e "${CYAN}  GASAK DEPLOYER${RESET}"
echo -e "${CYAN}  Project : ${GREEN}${LOCAL_PROJECT_DIR}${RESET}"
echo -e "${CYAN}  Dist    : ${GREEN}${LOCAL_DIST_DIR}${RESET}"
echo -e "${CYAN}  Target  : ${GREEN}${SUPENG_USER}@${SUPENG_IP}:${SUPENG_DIR}${RESET}"
echo -e "${CYAN}────────────────────────────────────────────────────────────${RESET}"

# Cek SSH key ada dulu sebelum mubazir compile
if [ ! -f "$SSH_KEY" ]; then
    err "SSH key tidak ditemukan: ${SSH_KEY}"
    err "Generate dulu: ssh-keygen -t rsa -b 4096"
    exit 1
fi

# Cek koneksi ke server supeng via ZeroTier sebelum mulai compile
info "Cek koneksi ke server supeng..."
if ! ping -c 1 -W 3 "$SUPENG_IP" > /dev/null 2>&1; then
    err "Tidak bisa reach ${SUPENG_IP}. Pastikan ZeroTier aktif."
    exit 1
fi
ok "Server supeng reachable"

# ─── STEP 1: COMPILE ─────────────────────────────────────────

step "1/4" "Compile GASAK binary (linux/amd64)..."

cd "$LOCAL_PROJECT_DIR"

# Build ke temp file dulu, baru rename — hindari SCP partial binary
GOOS=linux GOARCH=amd64 go build -ldflags="-s -w" -o ./gasak_linux .

ok "Kompilasi selesai: $(du -sh ./gasak_linux | cut -f1)"

# ─── STEP 2: SCP BINARY ──────────────────────────────────────

step "2/4" "Upload binary ke server supeng..."

info "Uploading gasak binary..."
scp -i "$SSH_KEY" -q ./gasak_linux "${SUPENG_USER}@${SUPENG_IP}:${SUPENG_DIR}/gasak"

# Hapus temp binary, yang di server udah renamed jadi gasak
rm -f ./gasak_linux
ok "Binary gasak terupload"

# ─── STEP 3: SCP SEMUA ASET DIST ─────────────────────────────

step "3/4" "Upload semua aset dari local dist dir..."

# Daftar semua aset yang harus selalu ada di server supeng
# Binary lain (datetime, socketserver, crush) diambil dari gasak-dist lokal
# karena itu compiled terpisah, bukan dari main.go
DIST_FILES=(
    "datetime"
    "socketserver"
    "crush"
    "install.sh"
    "serve.sh"
    "log_cleaner.py"
    "deploy_parkee_gum.sh"
    "log_cleaner_gum.sh"
    "log_cleaner_enhanced.sh"
    "version.txt"
)

MISSING_FILES=()
UPLOAD_LIST=()

for f in "${DIST_FILES[@]}"; do
    if [ -f "${LOCAL_DIST_DIR}/${f}" ]; then
        UPLOAD_LIST+=("${LOCAL_DIST_DIR}/${f}")
        info "Queue: ${f}"
    else
        MISSING_FILES+=("$f")
        echo -e "   ${RED}SKIP (tidak ada): ${f}${RESET}"
    fi
done

# server.properties — upload kalau ada, kalau gak ada biarkan serve.sh yang generate template
if [ -f "${LOCAL_DIST_DIR}/server.properties" ]; then
    UPLOAD_LIST+=("${LOCAL_DIST_DIR}/server.properties")
    info "Queue: server.properties"
fi

echo ""

if [ ${#UPLOAD_LIST[@]} -gt 0 ]; then
    scp -i "$SSH_KEY" -q "${UPLOAD_LIST[@]}" "${SUPENG_USER}@${SUPENG_IP}:${SUPENG_DIR}/"
    ok "Upload selesai: ${#UPLOAD_LIST[@]} file"
else
    err "Tidak ada file yang bisa diupload dari ${LOCAL_DIST_DIR}"
    exit 1
fi

if [ ${#MISSING_FILES[@]} -gt 0 ]; then
    echo -e "   ${YELLOW}Warning: File berikut tidak ada di local dist, dilewati:${RESET}"
    for m in "${MISSING_FILES[@]}"; do
        echo -e "   ${YELLOW}- ${m}${RESET}"
    done
fi

# ─── STEP 4: REMOTE RESTART SERVE.SH DI SUPENG ───────────────

step "4/4" "Restart dist server di supeng..."

ssh -i "$SSH_KEY" -q "${SUPENG_USER}@${SUPENG_IP}" bash << REMOTE
set -e

DIST_DIR="${SUPENG_DIR}"

echo "   -> Fixing permissions semua aset..."
chmod +x "\${DIST_DIR}/gasak" 2>/dev/null || true
chmod +x "\${DIST_DIR}/datetime" 2>/dev/null || true
chmod +x "\${DIST_DIR}/socketserver" 2>/dev/null || true
chmod +x "\${DIST_DIR}/crush" 2>/dev/null || true
chmod +x "\${DIST_DIR}/serve.sh" 2>/dev/null || true
find "\${DIST_DIR}" -maxdepth 1 -name "*.sh" -exec chmod +x {} \; 2>/dev/null || true

echo "   -> Kill proses serve lama..."
# Pattern kill yang match sama proses python3 inline dari serve.sh
pkill -f "python3 -.*${SUPENG_DIR}" 2>/dev/null || true
pkill -f "serve.sh" 2>/dev/null || true
sleep 1

echo "   -> Jalanin serve.sh baru di background..."
cd "\${DIST_DIR}"
nohup bash serve.sh > dist_server.log 2>&1 &

# Kasih waktu python naik
sleep 2

echo "   -> Verifikasi proses server:"
if pgrep -f "python3" > /dev/null 2>&1; then
    echo "   OK - Python dist server aktif"
    ss -tlnp 2>/dev/null | grep ":9001" || netstat -tlnp 2>/dev/null | grep ":9001" || echo "   (port check tidak tersedia)"
else
    echo "   WARN - Python process tidak ditemukan, cek dist_server.log"
    tail -5 "\${DIST_DIR}/dist_server.log" 2>/dev/null || true
fi
REMOTE

# ─── DONE ────────────────────────────────────────────────────

GASAK_VERSION=$(cat "${LOCAL_DIST_DIR}/version.txt" 2>/dev/null | tr -d '[:space:]' || echo "unknown")

echo ""
echo -e "${GREEN}────────────────────────────────────────────────────────────${RESET}"
echo -e "${GREEN}  DEPLOYMENT SELESAI${RESET}"
echo -e "${GREEN}  Version : ${GASAK_VERSION}${RESET}"
echo -e "${GREEN}  Gasak hit ini men : curl -fsSL http://${SUPENG_IP}:9001/install.sh | bash${RESET}"
echo -e "${GREEN}────────────────────────────────────────────────────────────${RESET}"
