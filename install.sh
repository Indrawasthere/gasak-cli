#!/bin/bash

# ─────────────────────────────────────────────────────────────
# GASAK INSTALLER - Client Side (ULTIMATE SECURE EDITION)
# Jalanin ini di PC/Laptop Engineer buat setup toolchain penuh.
# ─────────────────────────────────────────────────────────────

set -euo pipefail

SERVER_IP="10.70.0.110"
SERVER_PORT="9001"
BASE_URL="http://${SERVER_IP}:${SERVER_PORT}"
INSTALL_DIR="$HOME/gasak-dist"
AGENT_DIR="/opt/app/agent/parkee-agent"
LOCAL_BIN="/usr/local/bin"

echo "=== STARTING GASAK TOOLCHAIN INSTALLATION ==="

# ─── 1. ZEROTIER PRE-FLIGHT CHECK ───────────────────────────
echo "[*] Checking ZeroTier Network Connection..."
ZT_IFACE=$(ip link show 2>/dev/null | grep -oE 'zt[0-9a-z]+' | head -1)

if [ -z "$ZT_IFACE" ]; then
    echo "ERROR: Jaringan ZeroTier kagak kebaca nih men."
    echo "Pastiin ZT udah running dan udah join network overlay Parkee."
    exit 1
fi

if ! ping -c 1 -W 3 "$SERVER_IP" > /dev/null 2>&1; then
    echo "ERROR: Waduh, server supeng di ${SERVER_IP} kagak respon."
    echo "Cek IP lo apakah udah diapprove di dashboard central ZT atau belom."
    exit 1
fi
echo "   -> Koneksi ke server distribusi OK!"

# ─── 2. SYSTEM DEPENDENCIES CHECK (FZF & PYTHON) ────────────
echo "[*] Checking Linux System Dependencies..."

# Update package list & install fzf + pip + libpq (untuk postgres python) jika belum ada
sudo apt-get update -y > /dev/null 2>&1 || true
for pkg in fzf python3-pip python3-dev libpq-dev; do
    if ! dpkg -s "$pkg" >/dev/null 2>&1; then
        echo "   -> Installing system package: $pkg..."
        sudo apt-get install -y "$pkg" > /dev/null 2>&1
    fi
done

# ─── 3. PYTHON MODULES CHECK (PIP) ──────────────────────────
echo "[*] Installing Required Python Modules..."
# Pastikan requests dan psycopg2-binary ikut terinstal untuk modul settlement
pip3 install --user --upgrade pip > /dev/null 2>&1 || true
pip3 install --user rich questionary iterfzf requests psycopg2-binary > /dev/null 2>&1

# ─── 4. DIRECTORY & WORKSPACE PREPARATION ───────────────────
echo "[*] Preparing Workspace Directories..."
mkdir -p "$INSTALL_DIR"

if [ ! -d "$AGENT_DIR" ]; then
    sudo mkdir -p "$AGENT_DIR"
fi
sudo chmod 777 "$AGENT_DIR"

# ─── 5. DOWNLOAD ALL WHITELISTED FILES FROM SERVER ──────────
echo "[*] Fetching Toolchain Files from Server Supeng..."
cd "$INSTALL_DIR"

# Daftar seluruh file wajib yang ada di whitelist server supeng
FILES_TO_FETCH=(
    "gasak"
    "deploy_parkee.py"
    "settlement_rfs.py"
    "decode_and_merge.py"
    "log_cleaner.py"
    "version.txt"
    "server.properties"
)

for file in "${FILES_TO_FETCH[@]}"; do
    echo "   -> Downloading ${file}..."
    curl -sSfL "${BASE_URL}/${file}" -o "${file}"
done

# ─── 6. PERMISSIONS & BINARY SYMLINKS ───────────────────────
echo "[*] Adjusting Permissions and Creating Binary Symlinks..."
chmod +x gasak

# Daftarkan biner utama gasak ke global path
sudo ln -sf "${INSTALL_DIR}/gasak" "${LOCAL_BIN}/gasak"

# ─── 7. REGISTER CLI WRAPPERS (BIAR BISA DIPANGGIL GLOBAL) ──
echo "[*] Registering Module Wrappers..."

if [ -f "deploy_parkee.py" ]; then
    echo -e '#!/bin/bash\npython3 '"${INSTALL_DIR}"'/deploy_parkee.py "$@"' | sudo tee "${LOCAL_BIN}/tembak-agent" > /dev/null
    sudo chmod +x "${LOCAL_BIN}/tembak-agent"
    echo "   + Wrapper Registered: tembak-agent"
fi

if [ -f "settlement_rfs.py" ]; then
    echo -e '#!/bin/bash\npython3 '"${INSTALL_DIR}"'/settlement_rfs.py "$@"' | sudo tee "${LOCAL_BIN}/settlement-rfs" > /dev/null
    sudo chmod +x "${LOCAL_BIN}/settlement-rfs"
    echo "   + Wrapper Registered: settlement-rfs"
fi

if [ -f "decode_and_merge.py" ]; then
    echo -e '#!/bin/bash\npython3 '"${INSTALL_DIR}"'/decode_and_merge.py "$@"' | sudo tee "${LOCAL_BIN}/settlement-decode" > /dev/null
    sudo chmod +x "${LOCAL_BIN}/settlement-decode"
    echo "   + Wrapper Registered: settlement-decode"
fi

# ─── 8. WRAP UP ─────────────────────────────────────────────
GASAK_VERSION=$(cat "${INSTALL_DIR}/version.txt" 2>/dev/null | tr -d '[:space:]' || echo "1.1.12")

echo "────────────────────────────────────────────────────────────"
echo "  GASAK TOOLCHAIN BERHASIL TERPASANG 100%, MEN!"
echo "  Version   : ${GASAK_VERSION}"
echo "  Workspace : ${INSTALL_DIR}"
echo "────────────────────────────────────────────────────────────"
echo "  Sekarang user tinggal ketik: gasak"
