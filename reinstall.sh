#!/bin/bash

# ─────────────────────────────────────────────────────────────
# GASAK FULL NUKE & REINSTALL
# Bersihin SEMUA sisa instalasi lama, lalu fresh install total
# ─────────────────────────────────────────────────────────────

set -euo pipefail

SERVER_IP="10.70.0.110"
SERVER_PORT="9001"
BASE_URL="http://${SERVER_IP}:${SERVER_PORT}"
INSTALL_DIR="$HOME/gasak-dist"
LOCAL_BIN="/usr/local/bin"
AGENT_DIR="/opt/app/agent/parkee-agent"

GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
PURPLE='\033[0;35m'
RESET='\033[0m'

ok()   { echo -e "   ${GREEN}✔ $1${RESET}"; }
err()  { echo -e "   ${RED}✘ $1${RESET}"; }
info() { echo -e "   ${CYAN}-> $1${RESET}"; }
warn() { echo -e "   ${YELLOW}⚠ $1${RESET}"; }

clear
echo -e "${RED}────────────────────────────────────────────────────────────${RESET}"
echo -e "${RED}  GASAK FULL NUKE & REINSTALL                               ${RESET}"
echo -e "${RED}  Semua file lama akan dihapus total. Fresh install baru.   ${RESET}"
echo -e "${RED}────────────────────────────────────────────────────────────${RESET}"
echo ""
echo -e "${YELLOW}  Script ini akan:${RESET}"
echo -e "  1. Hapus total ${INSTALL_DIR}"
echo -e "  2. Hapus semua symlink GASAK di ${LOCAL_BIN}"
echo -e "  3. Hapus wrapper commands lama"
echo -e "  4. Hapus .env lama"
echo -e "  5. Fresh install dari server supeng"
echo ""
echo -ne "${YELLOW}  Yakin mau lanjut? (y/N): ${RESET}"
read -r CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo -e "\n  ${CYAN}Dibatalin. Gas install manual aja kalau mau.${RESET}\n"
    exit 0
fi

echo ""

# ─── ZEROTIER CHECK DULU ──────────────────────────────────────
echo -e "${YELLOW}[Pre-flight] Cek koneksi ZeroTier ke server supeng...${RESET}"

ZT_IFACE=$(ip link show 2>/dev/null | grep -oE 'zt[0-9a-z]+' | head -1 || echo "")
if [ -z "$ZT_IFACE" ]; then
    err "ZeroTier interface tidak ditemukan!"
    echo -e "   Jalanin dulu: ${CYAN}sudo systemctl start zerotier-one${RESET}"
    exit 1
fi
ok "ZeroTier interface: ${ZT_IFACE}"

if ! ping -c 1 -W 3 "$SERVER_IP" > /dev/null 2>&1; then
    err "Server supeng (${SERVER_IP}) tidak bisa direachable. Cek ZeroTier."
    exit 1
fi
ok "Server supeng: REACHABLE"

# ─── NUKE PHASE ───────────────────────────────────────────────
echo -e "\n${RED}[NUKE] Membabat semua sisa instalasi lama...${RESET}"

# 1. Hapus symlinks global
info "Hapus symlink di ${LOCAL_BIN}..."
sudo rm -f \
    "${LOCAL_BIN}/gasak" \
    "${LOCAL_BIN}/tembak-agent" \
    "${LOCAL_BIN}/settlement-rfs" \
    "${LOCAL_BIN}/settlement-decode" \
    2>/dev/null || true
ok "Symlinks dihapus."

# 2. Hapus wrapper scripts yang mungkin tersisa
info "Hapus wrapper scripts..."
for wrapper in tembak-agent settlement-rfs settlement-decode; do
    sudo rm -f "${LOCAL_BIN}/${wrapper}" 2>/dev/null || true
done
ok "Wrapper scripts dihapus."

# 3. Hapus install directory total — TERMASUK .env dan venv
info "Hapus total direktori ${INSTALL_DIR}..."
if [ -d "$INSTALL_DIR" ]; then
    rm -rf "$INSTALL_DIR"
    ok "${INSTALL_DIR} dihapus total."
else
    ok "${INSTALL_DIR} memang belum ada."
fi

# 4. Hapus token cache Python tools
info "Hapus token cache (.parkee_token.json)..."
rm -f "$HOME/.parkee_token.json" 2>/dev/null || true
ok "Token cache dihapus."

# 5. Hapus location cache GASAK
info "Hapus location cache..."
rm -f "$HOME/.cache/parkee/master_loc.csv" 2>/dev/null || true
ok "Location cache dihapus."

# 6. Hapus binary gasak lama yang mungkin ada di tempat lain
for old_path in "$HOME/gasak" "$HOME/.local/bin/gasak" "/usr/bin/gasak"; do
    if [ -f "$old_path" ] || [ -L "$old_path" ]; then
        sudo rm -f "$old_path" 2>/dev/null || true
        ok "Hapus binary lama: ${old_path}"
    fi
done

echo -e "\n${GREEN}  NUKE selesai. Semua bersih.${RESET}"

# ─── REINSTALL PHASE ──────────────────────────────────────────
echo -e "\n${CYAN}[REINSTALL] Mulai fresh install dari server supeng...${RESET}"
echo -e "${CYAN}────────────────────────────────────────────────────────────${RESET}"
echo ""

# Pull install.sh terbaru dari server dan langsung eksekusi
# Pakai exec biar PID kegganti dan output langsung ke terminal
if ! curl -sSfL --retry 3 --retry-delay 2 \
          --connect-timeout 10 --max-time 30 \
          "${BASE_URL}/install.sh" -o /tmp/gasak_install.sh; then
    err "Gagal download install.sh dari server!"
    err "Cek: curl http://${SERVER_IP}:${SERVER_PORT}/install.sh"
    exit 1
fi

chmod +x /tmp/gasak_install.sh
bash /tmp/gasak_install.sh
rm -f /tmp/gasak_install.sh
