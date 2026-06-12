#!/bin/bash

# ─────────────────────────────────────────────────────────────
# GASAK TOOLCHAIN INSTALLER - ULTIMATE AUTO-REMEDIAL VERSION
# Dirancang untuk Fresh Install, Perbaikan Environment, dan Auto .env
# ─────────────────────────────────────────────────────────────

set -euo pipefail

# ─── CONFIGURATION ───────────────────────────────────────────
SERVER_IP="10.70.0.110"
SERVER_PORT="9001"
BASE_URL="http://${SERVER_IP}:${SERVER_PORT}"
INSTALL_DIR="$HOME/gasak-dist"
AGENT_DIR="/opt/app/agent/parkee-agent"
LOCAL_BIN="/usr/local/bin"

# ANSI Terminal Colors
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
PURPLE='\033[0;35m'
RESET='\033[0m'

clear
echo -e "${CYAN}────────────────────────────────────────────────────────────${RESET}"
echo -e "${CYAN}  GASAK ENGINE TOOLCHAIN - AUTOMATED DEPLOYER INITIALIZER   ${RESET}"
echo -e "${CYAN}────────────────────────────────────────────────────────────${RESET}"

# ─── 1. WIPE OUT / PRE-FLIGHT CLEANING ───────────────────────
echo -e "\n${YELLOW}[Step 1] Membabat Sisa-Sisa File Lama (Fresh Wipe)...${RESET}"

# Hapus symlink lama jika ada bentrok permission
sudo rm -f "${LOCAL_BIN}/gasak" "${LOCAL_BIN}/tembak-agent" "${LOCAL_BIN}/settlement-rfs" "${LOCAL_BIN}/settlement-decode" 2>/dev/null || true

echo -e "   -> Membersihkan direktori kerja lama..."
mkdir -p "$INSTALL_DIR"
# Bersihkan file lama agar tidak bentrok, kita timpa semuanya fresh
find "$INSTALL_DIR" -maxdepth 1 -type f -delete 2>/dev/null || true

# ─── 2. JARINGAN ZEROTIER PRE-FLIGHT CHECK ───────────────────
echo -e "\n${YELLOW}[Step 2] Validasi Jaringan Overlay ZeroTier...${RESET}"
ZT_IFACE=$(ip link show 2>/dev/null | grep -oE 'zt[0-9a-z]+' | head -1 || echo "")

if [ -z "$ZT_IFACE" ]; then
    echo -e "${RED}ERROR: Jaringan ZeroTier kagak kebaca nih men.${RESET}"
    echo "Pastiin service ZT udah running dan udah join network overlay Parkee."
    exit 1
fi
echo -e "   -> Interface ZeroTier Terdeteksi: ${GREEN}${ZT_IFACE}${RESET}"

if ! ping -c 1 -W 3 "$SERVER_IP" > /dev/null 2>&1; then
    echo -e "${RED}ERROR: Server Distribusi Supeng (${SERVER_IP}) RTO / Gak Respon!${RESET}"
    echo "Cek IP lo apakah udah di-approve/authorize di dashboard central ZT atau belom."
    exit 1
fi
echo -e "   -> Koneksi ke Server Supeng: ${GREEN}CONNECTED (OK)${RESET}"

# ─── 3. SYSTEM DEPENDENCIES & COMPILER UTILITIES ─────────────
echo -e "\n${YELLOW}[Step 3] Sinkronisasi Paket Dependensi OS Linux...${RESET}"
echo "   -> Menjalankan update package manager (apt-get)..."
sudo apt-get update -y > /dev/null 2>&1 || true

REQUIRED_SYS_PKGS=(fzf python3-pip python3-dev python3-venv libpq-dev build-essential)
for pkg in "${REQUIRED_SYS_PKGS[@]}"; do
    if ! dpkg -s "$pkg" >/dev/null 2>&1; then
        echo -e "   -> Menginstal paket sistem: ${CYAN}$pkg${RESET}..."
        sudo apt-get install -y "$pkg" > /dev/null 2>&1
    else
        echo -e "   -> Paket sistem ${GREEN}$pkg${RESET} sudah terpasang."
    fi
done

# ─── 4. PYTHON ISOLATED VIRTUAL ENVIRONMENT SETUP ───────────
echo -e "\n${YELLOW}[Step 4] Setup Sandbox Python Virtual Environment (VENV)...${RESET}"
cd "$INSTALL_DIR"

if [ ! -d "venv" ]; then
    echo "   -> Membuat environment python baru agar package tidak bentrok..."
    python3 -m venv venv
fi

# Aktivasi VENV untuk proses instalasi PIP
echo "   -> Mengaktifkan Virtual Environment..."
source venv/bin/activate

echo "   -> Meng-upgrade pip internal venv..."
pip install --upgrade pip > /dev/null 2>&1

echo "   -> Menginstal bundle library Python (Rich, Questionary, Iterfzf, Postgres Client)..."
pip install wheel > /dev/null 2>&1 || true
pip install rich questionary iterfzf requests psycopg2-binary > /dev/null 2>&1
echo -e "   -> Status Package Python: ${GREEN}SUCCESSFULLY INSTALLED${RESET}"

# ─── 5. DOWNLOAD WORKSPACE TOOLS FROM SERVER WHITELIST ──────
echo -e "\n${YELLOW}[Step 5] Menarik File Utama dari Server Distribusi...${RESET}"

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
    echo -e "   -> Mengunduh berkas: ${PURPLE}${file}${RESET}..."
    if ! curl -sSfL "${BASE_URL}/${file}" -o "${file}"; then
        echo -e "${RED}ERROR: Gagal mengunduh file ${file} dari server!${RESET}"
        exit 1
    fi
done

# Pastikan binary gasak bisa dieksekusi
chmod +x gasak

# ─── 6. AUTOMATED .ENV INJECTOR UTILITY ──────────────────────
echo -e "\n${YELLOW}[Step 6] Membangun File Konfigurasi Environment Berisi Kredensial (.env)...${RESET}"

# Menulis langsung kredensial asli ke laptop user secara otomatis
cat << 'EOF' > "${INSTALL_DIR}/.env"
# ─────────────────────────────────────────────────────────────
# GASAK CONFIGURATION ENVIRONMENT VARIABLE (AUTO-GENERATED)
# ─────────────────────────────────────────────────────────────

# GLPI & Knowledge Base Config
GLPI_URL=https://parkee-ticket.nusa.technology/
OUTLINE_URL=https://docs.sistemparkiran.com/home
OUTLINE_API_KEY=REMOVED_OUTLINE_KEY
LINEAR_API_KEY=REMOVED_LINEAR_KEY

# SSH
PARKEE_SSH_USER=support
PARKEE_SSH_PASS=REMOVED_PASSWORD

# CMS Database (Settlement Tools)
CMS_DB_HOST=newdbparkeeproduction.cmxwbzwcs2rw.ap-southeast-1.rds.amazonaws.com
CMS_DB_PORT=5432
CMS_DB_USER=product
CMS_DB_PASS=Parkee545115
CMS_DB_NAME=parkee
EOF

echo -e "   -> ${GREEN}File .env berhasil dibuat dan diisi kredensial resmi Parkee!${RESET}"
# Kunci hak akses .env agar aman (Read/Write hanya untuk user aktif)
chmod 600 "${INSTALL_DIR}/.env"

# ─── 7. AGENT DEPLOYMENT RUNTIME DIRECTORY SANITIZER ────────
echo -e "\n${YELLOW}[Step 7] Validasi Direktori Runtime Agen Lapangan...${RESET}"
if [ ! -d "$AGENT_DIR" ]; then
    echo "   -> Membuat folder deployment /opt/app/agent..."
    sudo mkdir -p "$AGENT_DIR"
fi
sudo chmod 777 "$AGENT_DIR"
echo -e "   -> Status Folder Agen: ${GREEN}READY & WRITABLE${RESET}"

# ─── 8. REGISTRASI SYMLINKS GLOBAL & WRAPPER RUNNER ──────────
echo -e "\n${YELLOW}[Step 8] Mendaftarkan System Execution Wrapper & Symlinks...${RESET}"

# Mendaftarkan biner utama gasak ke global execution path
sudo ln -sf "${INSTALL_DIR}/gasak" "${LOCAL_BIN}/gasak"

# Membuat Wrapper Pintar yang otomatis manggil VENV Python internal kita
create_python_wrapper() {
    local script_name=$1
    local bin_name=$2

    if [ -f "${INSTALL_DIR}/${script_name}" ]; then
        echo -e "#!/bin/bash\nsource ${INSTALL_DIR}/venv/bin/activate\npython3 ${INSTALL_DIR}/${script_name} \"\$@\"" | sudo tee "${LOCAL_BIN}/${bin_name}" > /dev/null
        sudo chmod +x "${LOCAL_BIN}/${bin_name}"
        echo -e "   + Wrapper Terdaftar: ${GREEN}${bin_name}${RESET} -> ${script_name}"
    fi
}

create_python_wrapper "deploy_parkee.py" "tembak-agent"
create_python_wrapper "settlement_rfs.py" "settlement-rfs"
create_python_wrapper "decode_and_merge.py" "settlement-decode"

# ─── 9. SUMMARY WRAP-UP ──────────────────────────────────────
GASAK_VERSION=$(cat "${INSTALL_DIR}/version.txt" 2>/dev/null | tr -d '[:space:]' || echo "1.1.12")

echo -e "\n${GREEN}────────────────────────────────────────────────────────────${RESET}"
echo -e "${GREEN}      GASAK CLI TOOLCHAIN BERHASIL TERPASANG 100% MEN!      ${RESET}"
echo -e "${GREEN}────────────────────────────────────────────────────────────${RESET}"
echo -e "  • Aplikasi Versi  : ${PURPLE}${GASAK_VERSION}${RESET}"
echo -e "  • Lokasi Instalasi : ${CYAN}${INSTALL_DIR}${RESET}"
echo -e "  • Status Kredensial: ${GREEN}TERISI OTOMATIS & SECURE${RESET}"
echo -e "${GREEN}────────────────────────────────────────────────────────────${RESET}"
echo -e "   Sekarang tinggal ketik global command: ${CYAN}gasak${RESET}"
echo ""
