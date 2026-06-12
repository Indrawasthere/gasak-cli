#!/bin/bash

# ─────────────────────────────────────────────────────────────
# GASAK INSTALLER - Client Side (Single Directory Architecture)
# ─────────────────────────────────────────────────────────────

set -euo pipefail

SERVER_IP="10.70.0.110"
SERVER_PORT="9001"
BASE_URL="http://${SERVER_IP}:${SERVER_PORT}"
INSTALL_DIR="$HOME/gasak-dist"
AGENT_DIR="/opt/app/agent/parkee-agent"
LOCAL_BIN="/usr/local/bin"

# ─── 1. ZEROTIER CHECK ───────────────────────────────────────

echo "[*] Checking ZeroTier Network Connection..."
ZT_IFACE=$(ip link show 2>/dev/null | grep -oE 'zt[0-9a-z]+' | head -1)

if [ -z "$ZT_IFACE" ]; then
    echo "ERROR: Jaringan ZeroTier kagak kebaca nih men."
    echo "Pastiin ZT udah running dan udah join network overlay Parkee."
    exit 1
fi

if ! ping -c 1 -W 3 "$SERVER_IP" > /dev/null 2>&1; then
    echo "ERROR: Waduh, server supeng di ${SERVER_IP} kagak respon (Request Timeout)."
    echo "Cek IP lo apakah udah diapprove di dashboard central ZT atau belom."
    exit 1
fi

echo "   -> Koneksi ke server distribusi OK"

# ─── 2. SYSTEM DEPENDENCIES CHECK ───────────────────────────

echo "[*] Checking System Dependencies..."
if ! command -v python3 &> /dev/null; then
    sudo apt-get update && sudo apt-get install -y python3
fi
if ! command -v pip3 &> /dev/null; then
    sudo apt-get update && sudo apt-get install -y python3-pip
fi

# ─── 3. PREPARE DIRECTORIES ─────────────────────────────────

mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR" || exit 1

# ─── 4. DOWNLOAD MODULES FROM SERVER ────────────────────────

MODULES=(
    "gasak"
    "log_cleaner.py"
    "deploy_parkee.py"
    "settlement_rfs.py"
    "decode_and_merge.py"
)

echo "[*] Downloading GASAK Toolchain dari server..."
for module in "${MODULES[@]}"; do
    printf "  Fetching %-25s" "${module}..."
    if curl -fsSL -o "${module}" "${BASE_URL}/${module}"; then
        echo "OK"
    else
        echo "FAILED"
    fi
done

# ─── 5. SET PERMISSIONS & SYMLINKS ──────────────────────────

echo "[*] Configuring permissions and symlinks..."
chmod +x gasak

# Registrasi biner utama ke global bin
sudo ln -sf "${INSTALL_DIR}/gasak" "${LOCAL_BIN}/gasak"

# Wrapper untuk script deployment dan Python utilitas lainnya
if [ -f "deploy_parkee.py" ]; then
    echo -e '#!/bin/bash\npython3 '"${INSTALL_DIR}"'/deploy_parkee.py "$@"' | sudo tee "${LOCAL_BIN}/tembak-agent" > /dev/null
    sudo chmod +x "${LOCAL_BIN}/tembak-agent"
fi

if [ -f "settlement_rfs.py" ]; then
    echo -e '#!/bin/bash\npython3 '"${INSTALL_DIR}"'/settlement_rfs.py "$@"' | sudo tee "${LOCAL_BIN}/settlement-rfs" > /dev/null
    sudo chmod +x "${LOCAL_BIN}/settlement-rfs"
fi

if [ -f "decode_and_merge.py" ]; then
    echo -e '#!/bin/bash\npython3 '"${INSTALL_DIR}"'/decode_and_merge.py "$@"' | sudo tee "${LOCAL_BIN}/settlement-decode" > /dev/null
    sudo chmod +x "${LOCAL_BIN}/settlement-decode"
fi

# ─── 6. SETUP AGENT ENVIRONMENT ─────────────────────────────

if [ ! -d "$AGENT_DIR" ]; then
    sudo mkdir -p "$AGENT_DIR"
fi
sudo chmod 777 "$AGENT_DIR"

# Pre-install Python libraries yang dibutuhkan TUI
pip3 install --user rich questionary iterfzf requests 2>/dev/null || \
pip3 install --user rich questionary iterfzf requests --break-system-packages 2>/dev/null

echo "────────────────────────────────────────────────────────────"
echo "  GASAK TOOLCHAIN BERHASIL TERPASANG, MEN!"
echo "  Workspace user berada di: ${INSTALL_DIR}"
echo "  Silakan jalankan perintah: gasak"
echo "────────────────────────────────────────────────────────────"
