#!/bin/bash

# ─────────────────────────────────────────────────────────────
# GASAK TOOLCHAIN INSTALLER - BULLETPROOF EDITION
# Handles: fresh install, repair, missing deps, missing .env
# ─────────────────────────────────────────────────────────────

set -euo pipefail

# ─── CONFIGURATION ───────────────────────────────────────────
SERVER_IP="10.70.0.110"
SERVER_PORT="9001"
BASE_URL="http://${SERVER_IP}:${SERVER_PORT}"
INSTALL_DIR="$HOME/gasak-dist"
AGENT_DIR="/opt/app/agent/parkee-agent"
LOCAL_BIN="/usr/local/bin"

# ANSI Colors
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
PURPLE='\033[0;35m'
RESET='\033[0m'

clear
echo -e "${CYAN}────────────────────────────────────────────────────────────${RESET}"
echo -e "${CYAN}  GASAK ENGINE TOOLCHAIN - BULLETPROOF INSTALLER            ${RESET}"
echo -e "${CYAN}────────────────────────────────────────────────────────────${RESET}"

# ─── HELPER FUNCTIONS ─────────────────────────────────────────
ok()   { echo -e "   ${GREEN}✔ $1${RESET}"; }
err()  { echo -e "   ${RED}✘ $1${RESET}"; }
info() { echo -e "   ${CYAN}-> $1${RESET}"; }
warn() { echo -e "   ${YELLOW}⚠ $1${RESET}"; }

# ─── STEP 1: PRE-FLIGHT CLEANING ──────────────────────────────
echo -e "\n${YELLOW}[Step 1] Pre-flight Cleaning...${RESET}"

# Hapus symlink lama
sudo rm -f "${LOCAL_BIN}/gasak" "${LOCAL_BIN}/tembak-agent" \
           "${LOCAL_BIN}/settlement-rfs" "${LOCAL_BIN}/settlement-decode" 2>/dev/null || true

# Buat direktori tanpa hapus .env yang mungkin udah ada
mkdir -p "$INSTALL_DIR"

# Hapus semua file KECUALI .env dan venv (biar ga perlu install ulang deps)
find "$INSTALL_DIR" -maxdepth 1 -type f \
    ! -name ".env" \
    -delete 2>/dev/null || true

ok "Direktori kerja bersih, .env dan venv dipertahankan jika ada."

# ─── STEP 2: ZEROTIER NETWORK CHECK ───────────────────────────
echo -e "\n${YELLOW}[Step 2] Validasi Jaringan ZeroTier...${RESET}"

ZT_IFACE=$(ip link show 2>/dev/null | grep -oE 'zt[0-9a-z]+' | head -1 || echo "")

if [ -z "$ZT_IFACE" ]; then
    err "Interface ZeroTier tidak ditemukan!"
    echo -e "   Pastiin ZeroTier udah running: ${CYAN}sudo systemctl start zerotier-one${RESET}"
    echo -e "   Dan sudah join network Parkee: ${CYAN}sudo zerotier-cli join <NETWORK_ID>${RESET}"
    exit 1
fi
ok "Interface ZeroTier: ${ZT_IFACE}"

if ! ping -c 1 -W 3 "$SERVER_IP" > /dev/null 2>&1; then
    err "Server Supeng (${SERVER_IP}) tidak bisa direachable!"
    echo -e "   Kemungkinan penyebab:"
    echo -e "   1. IP lu belum di-authorize di ZeroTier Central"
    echo -e "   2. Server supeng lagi down"
    echo -e "   3. ZeroTier network ID salah"
    exit 1
fi
ok "Server Supeng ${SERVER_IP}: CONNECTED"

# ─── STEP 3: DETECT OS & PACKAGE MANAGER ──────────────────────
echo -e "\n${YELLOW}[Step 3] Deteksi OS dan Install Dependensi Sistem...${RESET}"

install_sys_deps_apt() {
    info "Menggunakan apt-get (Debian/Ubuntu)..."
    sudo apt-get update -y > /dev/null 2>&1 || warn "apt update gagal, lanjut dulu..."

    local pkgs=(fzf sshpass python3 python3-pip python3-dev python3-venv \
                libpq-dev build-essential curl wget openssh-client)

    for pkg in "${pkgs[@]}"; do
        if dpkg -s "$pkg" >/dev/null 2>&1; then
            ok "Paket ${pkg} sudah ada."
        else
            info "Menginstall ${pkg}..."
            if sudo apt-get install -y "$pkg" > /dev/null 2>&1; then
                ok "${pkg} berhasil diinstall."
            else
                warn "Gagal install ${pkg} — skip, mungkin ga kritis."
            fi
        fi
    done
}

install_sys_deps_pacman() {
    info "Menggunakan pacman (Arch Linux)..."
    sudo pacman -Sy --noconfirm > /dev/null 2>&1 || warn "pacman sync gagal, lanjut dulu..."

    local pkgs=(fzf sshpass python python-pip python-virtualenv \
                postgresql-libs base-devel curl wget openssh)

    for pkg in "${pkgs[@]}"; do
        if pacman -Qi "$pkg" >/dev/null 2>&1; then
            ok "Paket ${pkg} sudah ada."
        else
            info "Menginstall ${pkg}..."
            if sudo pacman -S --noconfirm "$pkg" > /dev/null 2>&1; then
                ok "${pkg} berhasil diinstall."
            else
                warn "Gagal install ${pkg} via pacman."
            fi
        fi
    done
}

# Deteksi OS
if command -v apt-get >/dev/null 2>&1; then
    install_sys_deps_apt
elif command -v pacman >/dev/null 2>&1; then
    install_sys_deps_pacman
else
    warn "Package manager tidak dikenal. Skip install dependensi sistem."
    warn "Pastiin lu udah punya: sshpass, python3, python3-pip, python3-venv, curl"
fi

# Verifikasi sshpass — ini KRITIS banget
if ! command -v sshpass >/dev/null 2>&1; then
    err "sshpass TIDAK DITEMUKAN setelah install! Ini WAJIB ada buat SSH ke lokasi."
    echo -e "   Install manual: ${CYAN}sudo apt-get install sshpass${RESET} atau ${CYAN}sudo pacman -S sshpass${RESET}"
    exit 1
fi
ok "sshpass: $(command -v sshpass)"

# Verifikasi python3
if ! command -v python3 >/dev/null 2>&1; then
    err "python3 TIDAK DITEMUKAN! Settlement tools butuh Python 3."
    exit 1
fi
ok "python3: $(python3 --version)"

# ─── STEP 4: PYTHON VENV SETUP ────────────────────────────────
echo -e "\n${YELLOW}[Step 4] Setup Python Virtual Environment...${RESET}"

cd "$INSTALL_DIR"

# Cek apakah venv masih valid (bisa aja python versi berubah)
VENV_VALID=false
if [ -d "venv" ] && [ -f "venv/bin/activate" ] && [ -f "venv/bin/python3" ]; then
    if venv/bin/python3 --version >/dev/null 2>&1; then
        VENV_VALID=true
        ok "venv existing masih valid, skip recreate."
    else
        warn "venv ada tapi corrupt, recreate..."
        rm -rf venv
    fi
fi

if [ "$VENV_VALID" = false ]; then
    info "Membuat Python venv baru..."
    python3 -m venv venv
    ok "venv berhasil dibuat."
fi

# Aktivasi venv
source venv/bin/activate
info "venv aktif: $(which python3)"

# Upgrade pip dulu tanpa exit on fail
info "Upgrade pip..."
pip install --upgrade pip > /dev/null 2>&1 || warn "pip upgrade gagal, lanjut pakai pip lama."

# Install semua Python deps — satu per satu biar kalau satu gagal, yang lain tetap jalan
PY_PACKAGES=(wheel rich questionary iterfzf requests psycopg2-binary)

for pypkg in "${PY_PACKAGES[@]}"; do
    if python3 -c "import ${pypkg//-/_}" >/dev/null 2>&1 || \
       python3 -c "import ${pypkg%%[_-]*}" >/dev/null 2>&1; then
        ok "Python pkg ${pypkg} sudah ada."
    else
        info "Install Python pkg: ${pypkg}..."
        if pip install "$pypkg" > /dev/null 2>&1; then
            ok "${pypkg} berhasil diinstall."
        else
            warn "Gagal install ${pypkg}. Settlement tools mungkin error."
        fi
    fi
done

deactivate 2>/dev/null || true

# ─── STEP 5: DOWNLOAD FILES FROM SERVER ───────────────────────
echo -e "\n${YELLOW}[Step 5] Download File Toolchain dari Server Supeng...${RESET}"

cd "$INSTALL_DIR"

FILES_TO_FETCH=(
    "gasak"
    "deploy_parkee.py"
    "settlement_rfs.py"
    "decode_and_merge.py"
    "log_cleaner.py"
    "version.txt"
    "server.properties"
)

DOWNLOAD_FAILED=()

for file in "${FILES_TO_FETCH[@]}"; do
    info "Downloading: ${file}..."
    if curl -sSfL --retry 3 --retry-delay 2 \
            --connect-timeout 10 --max-time 60 \
            "${BASE_URL}/${file}" -o "${file}"; then
        ok "${file} berhasil."
    else
        err "GAGAL download ${file}!"
        DOWNLOAD_FAILED+=("$file")
    fi
done

if [ ${#DOWNLOAD_FAILED[@]} -gt 0 ]; then
    echo -e "\n${RED}File berikut GAGAL didownload:${RESET}"
    for f in "${DOWNLOAD_FAILED[@]}"; do
        echo -e "  ${RED}- ${f}${RESET}"
    done
    # Gasak kritis kalau gagal
    if [[ " ${DOWNLOAD_FAILED[*]} " == *" gasak "* ]]; then
        err "Binary utama 'gasak' gagal didownload. Abort!"
        exit 1
    fi
fi

# Pastikan binary executable
chmod +x "$INSTALL_DIR/gasak"
ok "Binary gasak: executable"

# ─── STEP 6: WRITE .ENV FILE ──────────────────────────────────
echo -e "\n${YELLOW}[Step 6] Setup File Konfigurasi .env...${RESET}"

ENV_FILE="${INSTALL_DIR}/.env"

# Cek apakah .env udah ada dan valid (ada key wajibnya)
ENV_EXISTS=false
if [ -f "$ENV_FILE" ]; then
    if grep -q "PARKEE_SSH_PASS" "$ENV_FILE" && \
       grep -q "CMS_DB_HOST" "$ENV_FILE"; then
        ENV_EXISTS=true
        ok ".env sudah ada dan valid. Skip overwrite."
    else
        warn ".env ada tapi isinya incomplete. Overwrite..."
    fi
fi

if [ "$ENV_EXISTS" = false ]; then
    info "Menulis .env baru dengan kredensial lengkap..."

    # NOTE: Tulis dengan printf biar escaped characters ga bermasalah
    printf '%s\n' \
        '# ─────────────────────────────────────────────────────────────' \
        '# GASAK CONFIGURATION - AUTO-GENERATED BY INSTALLER' \
        '# ─────────────────────────────────────────────────────────────' \
        '' \
        '# URLs' \
        'GLPI_URL=https://parkee-ticket.nusa.technology/' \
        'OUTLINE_URL=https://docs.sistemparkiran.com/home' \
        '' \
        '# API Keys' \
        'OUTLINE_API_KEY=REMOVED_OUTLINE_KEY' \
        'LINEAR_API_KEY=REMOVED_LINEAR_KEY' \
        '' \
        '# SSH Credentials' \
        'PARKEE_SSH_USER=support' \
        'PARKEE_SSH_PASS=REMOVED_PASSWORD' \
        '' \
        '# CMS Database' \
        'CMS_DB_HOST=newdbparkeeproduction.cmxwbzwcs2rw.ap-southeast-1.rds.amazonaws.com' \
        'CMS_DB_PORT=5432' \
        'CMS_DB_USER=product' \
        'CMS_DB_PASS=Parkee545115' \
        'CMS_DB_NAME=parkee' \
        > "$ENV_FILE"

    ok ".env berhasil ditulis."
fi

# Lock permission .env — cuma owner yang bisa baca/tulis
chmod 600 "$ENV_FILE"
ok ".env permission: 600 (owner only)"

# ─── STEP 7: AGENT RUNTIME DIRECTORY ──────────────────────────
echo -e "\n${YELLOW}[Step 7] Setup Agent Runtime Directory...${RESET}"

if [ ! -d "$AGENT_DIR" ]; then
    info "Membuat direktori agent: $AGENT_DIR"
    sudo mkdir -p "$AGENT_DIR"
fi
sudo chmod 777 "$AGENT_DIR"
ok "Agent dir ${AGENT_DIR}: READY"

# ─── STEP 8: REGISTER GLOBAL COMMANDS ─────────────────────────
echo -e "\n${YELLOW}[Step 8] Registrasi Global Commands & Symlinks...${RESET}"

# Symlink binary utama
sudo ln -sf "${INSTALL_DIR}/gasak" "${LOCAL_BIN}/gasak"
ok "gasak -> ${LOCAL_BIN}/gasak"

# Helper buat bikin wrapper Python yang auto-aktivasi venv
create_python_wrapper() {
    local script_name="$1"
    local bin_name="$2"

    if [ -f "${INSTALL_DIR}/${script_name}" ]; then
        sudo tee "${LOCAL_BIN}/${bin_name}" > /dev/null << WRAPPER
#!/bin/bash
# Auto-generated wrapper by GASAK installer
# Loads .env and activates venv before running Python script
set -a
[ -f "${INSTALL_DIR}/.env" ] && source "${INSTALL_DIR}/.env"
set +a
source "${INSTALL_DIR}/venv/bin/activate"
exec python3 "${INSTALL_DIR}/${script_name}" "\$@"
WRAPPER
        sudo chmod +x "${LOCAL_BIN}/${bin_name}"
        ok "Wrapper: ${bin_name} -> ${script_name}"
    else
        warn "Script ${script_name} tidak ditemukan, wrapper dilewati."
    fi
}

create_python_wrapper "deploy_parkee.py"    "tembak-agent"
create_python_wrapper "settlement_rfs.py"   "settlement-rfs"
create_python_wrapper "decode_and_merge.py" "settlement-decode"

# ─── STEP 9: SHELL PROFILE SETUP ──────────────────────────────
echo -e "\n${YELLOW}[Step 9] Setup Shell PATH...${RESET}"

# Deteksi shell aktif
CURRENT_SHELL=$(basename "$SHELL" 2>/dev/null || echo "bash")
PROFILE_LINE="export PATH=\"${LOCAL_BIN}:\$PATH\""

case "$CURRENT_SHELL" in
    bash)
        PROFILE_FILES=("$HOME/.bashrc" "$HOME/.bash_profile")
        ;;
    zsh)
        PROFILE_FILES=("$HOME/.zshrc")
        ;;
    fish)
        # Fish syntax beda
        FISH_DIR="$HOME/.config/fish"
        mkdir -p "$FISH_DIR"
        if ! grep -q "${LOCAL_BIN}" "$FISH_DIR/config.fish" 2>/dev/null; then
            echo "fish_add_path ${LOCAL_BIN}" >> "$FISH_DIR/config.fish"
            ok "PATH ditambahkan ke fish config."
        else
            ok "PATH sudah ada di fish config."
        fi
        PROFILE_FILES=()
        ;;
    *)
        PROFILE_FILES=("$HOME/.profile")
        ;;
esac

for profile in "${PROFILE_FILES[@]}"; do
    if ! grep -q "${LOCAL_BIN}" "$profile" 2>/dev/null; then
        echo "" >> "$profile"
        echo "# GASAK CLI PATH" >> "$profile"
        echo "$PROFILE_LINE" >> "$profile"
        ok "PATH ditambahkan ke ${profile}."
    else
        ok "PATH sudah ada di ${profile}."
    fi
done

# ─── STEP 10: VERIFICATION ────────────────────────────────────
echo -e "\n${YELLOW}[Step 10] Verifikasi Final...${RESET}"

VERIFY_FAILED=()

# Cek binary gasak
if [ -x "${INSTALL_DIR}/gasak" ]; then
    ok "Binary gasak: ✔"
else
    err "Binary gasak: TIDAK EXECUTABLE"
    VERIFY_FAILED+=("gasak binary")
fi

# Cek symlink global
if [ -L "${LOCAL_BIN}/gasak" ]; then
    ok "Symlink /usr/local/bin/gasak: ✔"
else
    err "Symlink /usr/local/bin/gasak: TIDAK ADA"
    VERIFY_FAILED+=("gasak symlink")
fi

# Cek .env
if [ -f "${INSTALL_DIR}/.env" ] && grep -q "PARKEE_SSH_PASS" "${INSTALL_DIR}/.env"; then
    ok ".env file: ✔ (ada PARKEE_SSH_PASS)"
else
    err ".env file: MISSING atau INCOMPLETE"
    VERIFY_FAILED+=(".env")
fi

# Cek sshpass
if command -v sshpass >/dev/null 2>&1; then
    ok "sshpass: ✔"
else
    err "sshpass: TIDAK ADA — SSH ke lokasi TIDAK AKAN BISA!"
    VERIFY_FAILED+=("sshpass")
fi

# Cek venv + psycopg2
if "${INSTALL_DIR}/venv/bin/python3" -c "import psycopg2" >/dev/null 2>&1; then
    ok "Python venv + psycopg2: ✔"
else
    err "psycopg2 tidak ada di venv — Settlement tools TIDAK AKAN JALAN"
    VERIFY_FAILED+=("psycopg2")
fi

# Cek python scripts kritis
for script in deploy_parkee.py settlement_rfs.py decode_and_merge.py log_cleaner.py; do
    if [ -f "${INSTALL_DIR}/${script}" ]; then
        ok "${script}: ✔"
    else
        err "${script}: TIDAK ADA"
        VERIFY_FAILED+=("$script")
    fi
done

GASAK_VERSION=$(cat "${INSTALL_DIR}/version.txt" 2>/dev/null | tr -d '[:space:]' || echo "unknown")

# ─── FINAL SUMMARY ────────────────────────────────────────────
echo ""
echo -e "${CYAN}────────────────────────────────────────────────────────────${RESET}"

if [ ${#VERIFY_FAILED[@]} -eq 0 ]; then
    echo -e "${GREEN}  ✔ GASAK TOOLCHAIN TERPASANG SEMPURNA!                     ${RESET}"
    echo -e "${CYAN}────────────────────────────────────────────────────────────${RESET}"
    echo -e "  • Versi        : ${PURPLE}${GASAK_VERSION}${RESET}"
    echo -e "  • Install Dir  : ${CYAN}${INSTALL_DIR}${RESET}"
    echo -e "  • .env         : ${GREEN}LENGKAP${RESET}"
    echo -e "  • sshpass      : ${GREEN}TERSEDIA${RESET}"
    echo -e "  • Python venv  : ${GREEN}READY${RESET}"
    echo -e "${CYAN}────────────────────────────────────────────────────────────${RESET}"
    echo -e ""
    echo -e "  Jalankan dengan: ${CYAN}gasak${RESET}"
    echo -e ""
    echo -e "  ${YELLOW}NOTE: Kalau gasak command not found, jalankan dulu:${RESET}"
    echo -e "  ${CYAN}source ~/.bashrc${RESET}  atau  ${CYAN}source ~/.zshrc${RESET}"
    echo -e ""
else
    echo -e "${YELLOW}  ⚠ GASAK TERPASANG DENGAN BEBERAPA MASALAH:              ${RESET}"
    echo -e "${CYAN}────────────────────────────────────────────────────────────${RESET}"
    for item in "${VERIFY_FAILED[@]}"; do
        echo -e "  ${RED}✘ ${item}${RESET}"
    done
    echo -e "${CYAN}────────────────────────────────────────────────────────────${RESET}"
    echo -e "  Coba jalankan ulang installer, atau hubungi Fadlan."
    echo -e ""
fi
