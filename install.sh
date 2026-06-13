#!/bin/bash

# ─────────────────────────────────────────────────────────────
# GASAK ENGINE TOOLCHAIN - BULLETPROOF COMPLETE INSTALLER
# Target OS: Debian, Ubuntu, Linux Mint, dan semua turunannya
# ─────────────────────────────────────────────────────────────

# NOTE: Intentionally NO set -e disini.
# APT failure di device lapangan = hal biasa (broken repo, expired key, dll).
# Script harus tetap lanjut selama Python dan pip tersedia.
set -uo pipefail

# ─── CONFIGURATION ───────────────────────────────────────────
SERVER_IP="10.70.0.110"
SERVER_PORT="9001"
BASE_URL="http://${SERVER_IP}:${SERVER_PORT}"
INSTALL_DIR="$HOME/gasak-dist"
ENV_PATH="${INSTALL_DIR}/.env"

# ANSI Colors
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
PURPLE='\033[0;35m'
BOLD='\033[1m'
RESET='\033[0m'

clear
echo -e "${CYAN}════════════════════════════════════════════════════════════${RESET}"
echo -e "${CYAN}${BOLD}  GASAK ENGINE TOOLCHAIN — BULLETPROOF COMPLETE INSTALLER   ${RESET}"
echo -e "${CYAN}════════════════════════════════════════════════════════════${RESET}"
echo ""

# ─── HELPER FUNCTIONS ─────────────────────────────────────────
ok()   { echo -e "   ${GREEN}[✔] $1${RESET}"; }
err()  { echo -e "   ${RED}[✘] $1${RESET}"; }
info() { echo -e "   ${CYAN}[→] $1${RESET}"; }
warn() { echo -e "   ${YELLOW}[!] $1${RESET}"; }
section() {
    echo ""
    echo -e "${CYAN}────────────────────────────────────────────────────────────${RESET}"
    echo -e "${BOLD}  $1${RESET}"
    echo -e "${CYAN}────────────────────────────────────────────────────────────${RESET}"
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# ─── STEP 1: PREFLIGHT CHECK ──────────────────────────────────
section "STEP 1/8 — PREFLIGHT CHECK"

# Deteksi distro
if [ -f /etc/os-release ]; then
    . /etc/os-release
    info "Distro terdeteksi: ${PRETTY_NAME:-Unknown}"
else
    warn "Tidak bisa deteksi distro. Melanjutkan dengan asumsi Debian-based."
fi

# Verifikasi koneksi ke server distribusi dulu sebelum apapun
info "Verifikasi koneksi ke server distribusi ${SERVER_IP}:${SERVER_PORT}..."
if curl -fsSL --max-time 10 --connect-timeout 5 \
    "http://${SERVER_IP}:${SERVER_PORT}/version.txt" -o /dev/null 2>/dev/null; then
    GASAK_VERSION=$(curl -fsSL --max-time 5 "http://${SERVER_IP}:${SERVER_PORT}/version.txt" 2>/dev/null | tr -d '[:space:]' || echo "unknown")
    ok "Server distribusi ONLINE. Versi GASAK yang tersedia: ${GASAK_VERSION}"
else
    err "TIDAK BISA KONEK ke server distribusi ${SERVER_IP}:${SERVER_PORT}!"
    err "Pastikan:"
    err "  1. Kamu terhubung ke jaringan internal / VPN ZeroTier"
    err "  2. Server distribusi parkee@${SERVER_IP} menyala"
    err "  3. Coba ping: ping -c 3 ${SERVER_IP}"
    exit 1
fi

# ─── STEP 2: INSTALL DEPENDENSI SISTEM VIA APT ───────────────
section "STEP 2/8 — INSTALL SYSTEM DEPENDENCIES (NON-BLOCKING)"
info "Step ini NON-BLOCKING — APT error tidak akan menghentikan installer."
info "Mencoba sudo untuk install dependensi sistem (opsional)..."
# sudo -v gagal juga tidak apa-apa, kita lanjut
sudo -v 2>/dev/null || warn "sudo tidak tersedia / gagal. APT install akan di-skip."

info "Auto-repair APT package manager (jika ada broken packages)..."
sudo dpkg --configure -a 2>/dev/null || true
sudo apt-get install -f -y 2>/dev/null || true

info "Update daftar repositori APT (non-blocking — gagal = lanjut)..."
# apt-get update sengaja dibungkus || true.
# Banyak device lapangan punya repo broken / expired GPG key / mirror lambat.
# Yang penting Python & pip tersedia — APT update bukan blocker.
if ! sudo apt-get update -y -q 2>/dev/null; then
    warn "apt-get update gagal (broken repo / GPG / network issue)."
    warn "Installer akan tetap lanjut — install package satu per satu."
    warn "Kalau ada package yang skip, cek 'sudo apt-get update' manual."
fi

# Semua APT dependencies yang dibutuhkan seluruh toolchain:
# - python3, python3-pip, python3-tk     → runtime python + tkinter (log_cleaner.py)
# - python-is-python3                    → pastiin command 'python' ngepoint ke python3
# - sshpass                              → SSH automation (deploy_parkee.py)
# - rsync, unzip, curl, iputils-ping    → utility dasar
# - fzf                                  → iterfzf dependency (deploy_parkee.py)
# - lsof                                 → dibutuhkan debug port
APT_DEPS=(
    "python3"
    "python3-pip"
    "python3-tk"
    "python3-venv"
    "python-is-python3"
    "sshpass"
    "rsync"
    "unzip"
    "curl"
    "wget"
    "iputils-ping"
    "fzf"
    "lsof"
    "net-tools"
    "git"
)

INSTALLED_NEW=()
ALREADY_INSTALLED=()
FAILED_APT=()

APT_AVAILABLE=true
if ! command_exists apt-get; then
    warn "apt-get tidak tersedia di sistem ini. Skip APT install, lanjut ke pip."
    APT_AVAILABLE=false
fi

for pkg in "${APT_DEPS[@]}"; do
    if dpkg -s "$pkg" >/dev/null 2>&1; then
        ALREADY_INSTALLED+=("$pkg")
        ok "Sudah ada: ${pkg}"
    elif [ "$APT_AVAILABLE" = true ]; then
        info "Menginstall: ${pkg}..."
        # Paksa non-interactive, bungkus || true biar satu package gagal != abort
        if DEBIAN_FRONTEND=noninteractive sudo apt-get install -y -q "$pkg" 2>/dev/null || \
           DEBIAN_FRONTEND=noninteractive sudo apt-get install -y "$pkg" 2>/dev/null; then
            INSTALLED_NEW+=("$pkg")
            ok "Berhasil install: ${pkg}"
        else
            warn "Gagal install via APT: ${pkg} — akan dicoba alternatif / skip"
            FAILED_APT+=("$pkg")
        fi
    else
        warn "Skip APT untuk: ${pkg} (apt-get tidak tersedia)"
        FAILED_APT+=("$pkg")
    fi
done

# Summary APT — non-fatal, cuma informasi
if [ ${#FAILED_APT[@]} -ne 0 ]; then
    warn "Package APT berikut gagal install (NON-FATAL — installer tetap lanjut):"
    for p in "${FAILED_APT[@]}"; do
        warn "  - $p"
    done
    warn "Kalau butuh package ini, coba manual: sudo apt-get install ${FAILED_APT[*]}"
    warn "Installer lanjut ke step berikutnya..."
fi

# Khusus: python-is-python3 kadang tidak ada di semua distro/versi
# Fallback: buat symlink manual
if ! command_exists python && command_exists python3; then
    warn "Command 'python' tidak ada. Membuat symlink ke python3..."
    PYTHON3_PATH=$(command -v python3)
    if sudo ln -sf "$PYTHON3_PATH" /usr/local/bin/python 2>/dev/null; then
        ok "Symlink python → python3 berhasil dibuat di /usr/local/bin/python"
    else
        warn "Gagal buat symlink. 'python' command mungkin tidak tersedia, tapi 'python3' tetap jalan."
    fi
fi

# ─── STEP 3: DETEKSI & VERIFIKASI PYTHON RUNTIME ─────────────
section "STEP 3/8 — VERIFIKASI PYTHON RUNTIME"

PYTHON_CMD=""
PIP_CMD=""

# Cari python command yang valid (prioritas: python3 > python)
for cmd in python3 python; do
    if command_exists "$cmd"; then
        PY_VERSION=$("$cmd" --version 2>&1 | grep -oP '\d+\.\d+' | head -1)
        PY_MAJOR=$(echo "$PY_VERSION" | cut -d. -f1)
        PY_MINOR=$(echo "$PY_VERSION" | cut -d. -f2)
        if [ "$PY_MAJOR" -ge 3 ] && [ "$PY_MINOR" -ge 8 ]; then
            PYTHON_CMD="$cmd"
            ok "Python runtime valid: $("$cmd" --version 2>&1) [command: $cmd]"
            break
        else
            warn "Python versi terlalu lama: $("$cmd" --version 2>&1) — minimal Python 3.8"
        fi
    fi
done

if [ -z "$PYTHON_CMD" ]; then
    err "Python 3.8+ tidak ditemukan! Install manual: sudo apt-get install python3"
    exit 1
fi

# Cari pip command yang valid (prioritas: pip3 > pip)
for cmd in pip3 pip; do
    if command_exists "$cmd"; then
        PIP_CMD="$cmd"
        ok "PIP runtime: $("$cmd" --version 2>&1 | head -1) [command: $cmd]"
        break
    fi
done

if [ -z "$PIP_CMD" ]; then
    warn "pip tidak ditemukan via PATH. Mencoba via python -m pip..."
    if $PYTHON_CMD -m pip --version >/dev/null 2>&1; then
        PIP_CMD="$PYTHON_CMD -m pip"
        ok "PIP tersedia via: $PYTHON_CMD -m pip"
    else
        err "pip sama sekali tidak ditemukan! Coba: sudo apt-get install python3-pip"
        exit 1
    fi
fi

# ─── STEP 4: INISIALISASI FOLDER DISTRIBUSI ───────────────────
section "STEP 4/8 — SETUP INSTALL DIRECTORY"
info "Menyiapkan direktori instalasi: ${INSTALL_DIR}"
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR" || { err "Gagal masuk ke ${INSTALL_DIR}!"; exit 1; }
ok "Direktori siap: ${INSTALL_DIR}"

# ─── STEP 5: DOWNLOAD SEMUA KOMPONEN ─────────────────────────
section "STEP 5/8 — DOWNLOAD GASAK TOOLCHAIN COMPONENTS"
info "Mengunduh seluruh komponen dari server distribusi..."

FILES_TO_DOWNLOAD=(
    "gasak"
    "decode_and_merge.py"
    "deploy_parkee.py"
    "log_cleaner.py"
    "settlement_rfs.py"
    "version.txt"
    "server.properties"
)

DOWNLOAD_FAILED=()

for file in "${FILES_TO_DOWNLOAD[@]}"; do
    printf "   → Mengunduh %-30s " "${file}..."
    if curl -fsSL --max-time 60 --connect-timeout 10 \
        "${BASE_URL}/${file}" -o "${INSTALL_DIR}/${file}" 2>/dev/null; then
        FILESIZE=$(du -sh "${INSTALL_DIR}/${file}" 2>/dev/null | cut -f1 || echo "?")
        echo -e "${GREEN}OK (${FILESIZE})${RESET}"
    else
        echo -e "${RED}GAGAL!${RESET}"
        DOWNLOAD_FAILED+=("$file")
    fi
done

if [ ${#DOWNLOAD_FAILED[@]} -ne 0 ]; then
    err "File-file berikut gagal diunduh:"
    for f in "${DOWNLOAD_FAILED[@]}"; do
        err "  - $f"
    done
    err "Pastikan server distribusi ${SERVER_IP}:${SERVER_PORT} menyala dan bisa diakses!"
    exit 1
fi

ok "Semua komponen berhasil diunduh."

# ─── STEP 6: GENERATE/UPDATE .env ─────────────────────────────
section "STEP 6/8 — KONFIGURASI .ENV (CREDENTIALS)"

# Kalau .env sudah ada, backup dulu baru timpa
if [ -f "$ENV_PATH" ]; then
    cp "$ENV_PATH" "${ENV_PATH}.bak"
    warn ".env lama dibackup ke: ${ENV_PATH}.bak"
fi

info "Menulis konfigurasi .env lengkap..."

cat > "$ENV_PATH" << 'ENV_EOF'
# ─────────────────────────────────────────────────────────────
# GASAK CONFIGURATION — AUTO-GENERATED BY INSTALLER
# (HARDCODED CREDENTIALS FOR INTERNAL TEAM USE ONLY)
# DO NOT SHARE / COMMIT KE GIT
# ─────────────────────────────────────────────────────────────

# ── URLs ──────────────────────────────────────────────────────
GLPI_URL=https://parkee-ticket.nusa.technology/
OUTLINE_URL=https://docs.sistemparkiran.com/home

# ── API Keys ──────────────────────────────────────────────────
OUTLINE_API_KEY=REMOVED_OUTLINE_KEY
LINEAR_API_KEY=REMOVED_LINEAR_KEY

# ── SSH Credentials ───────────────────────────────────────────
PARKEE_SSH_USER=support
PARKEE_SSH_PASS=REMOVED_PASSWORD

# ── CMS Database (PostgreSQL) ─────────────────────────────────
CMS_DB_HOST=newdbparkeeproduction.cmxwbzwcs2rw.ap-southeast-1.rds.amazonaws.com
CMS_DB_PORT=5432
CMS_DB_USER=product
CMS_DB_PASS=Parkee545115
CMS_DB_NAME=parkee
ENV_EOF

chmod 600 "$ENV_PATH"
ok ".env berhasil ditulis & dikunci permission 600: ${ENV_PATH}"

# Verifikasi semua key ada di .env
REQUIRED_KEYS=(
    "GLPI_URL"
    "OUTLINE_URL"
    "OUTLINE_API_KEY"
    "LINEAR_API_KEY"
    "PARKEE_SSH_USER"
    "PARKEE_SSH_PASS"
    "CMS_DB_HOST"
    "CMS_DB_PORT"
    "CMS_DB_USER"
    "CMS_DB_PASS"
    "CMS_DB_NAME"
)

ENV_OK=true
for key in "${REQUIRED_KEYS[@]}"; do
    if grep -q "^${key}=" "$ENV_PATH"; then
        ok ".env key ada: ${key}"
    else
        err ".env MISSING KEY: ${key}"
        ENV_OK=false
    fi
done

if [ "$ENV_OK" = false ]; then
    err "Ada key yang hilang di .env! Tolong cek file: ${ENV_PATH}"
    exit 1
fi

# ─── STEP 7: INSTALL PYTHON MODULES ───────────────────────────
section "STEP 7/8 — INSTALL PYTHON MODULES"
info "Menginstall semua modul Python yang dibutuhkan seluruh toolchain..."
info "Python: $($PYTHON_CMD --version 2>&1)"
info "PIP: $($PIP_CMD --version 2>&1 | head -1)"

# Semua pip packages dari seluruh script:
# deploy_parkee.py   → requests, questionary, iterfzf, rich
# settlement_rfs.py  → psycopg2-binary, requests
# decode_and_merge.py → (stdlib only: json, argparse, urllib, pathlib, time)
# log_cleaner.py     → (stdlib: tkinter via apt, os, re, shutil, threading)
PIP_PACKAGES=(
    "psycopg2-binary"
    "requests"
    "questionary"
    "iterfzf"
    "rich"
)

# Strategi install berlapis:
# 1. pip install --user --break-system-packages  (Ubuntu 22+, Debian 12+)
# 2. pip install --break-system-packages          (fallback tanpa --user)
# 3. pip install --user                           (fallback tanpa break-system)
# 4. pip install                                  (last resort)

pip_install_with_fallback() {
    local package="$1"
    local strategies=(
        "--user --break-system-packages"
        "--break-system-packages"
        "--user"
        ""
    )

    for strategy in "${strategies[@]}"; do
        if $PIP_CMD install $strategy "$package" --quiet 2>/dev/null; then
            return 0
        fi
    done
    return 1
}

PIP_FAILED=()
for pkg in "${PIP_PACKAGES[@]}"; do
    printf "   → Installing Python module: %-25s " "${pkg}..."
    if pip_install_with_fallback "$pkg"; then
        INSTALLED_VER=$($PYTHON_CMD -c "import importlib.metadata; print(importlib.metadata.version('${pkg}'))" 2>/dev/null || echo "ok")
        echo -e "${GREEN}OK (${INSTALLED_VER})${RESET}"
    else
        echo -e "${RED}GAGAL!${RESET}"
        PIP_FAILED+=("$pkg")
    fi
done

if [ ${#PIP_FAILED[@]} -ne 0 ]; then
    warn "Beberapa modul gagal install:"
    for p in "${PIP_FAILED[@]}"; do
        warn "  - $p"
    done
    warn "Coba install manual: sudo pip3 install ${PIP_FAILED[*]}"
fi

# Pastikan ~/.local/bin ada di PATH (penting untuk --user install)
LOCAL_BIN="$HOME/.local/bin"
if [ -d "$LOCAL_BIN" ] && [[ ":$PATH:" != *":$LOCAL_BIN:"* ]]; then
    warn "~/.local/bin belum ada di PATH sesi ini. Akan ditambahkan ke profile."
    export PATH="$LOCAL_BIN:$PATH"
fi

# Verifikasi semua module bisa di-import oleh Python
info "Verifikasi semua module bisa di-import..."
IMPORT_FAILED=()
MODULES_TO_CHECK=("psycopg2" "requests" "questionary" "iterfzf" "rich" "tkinter")

for mod in "${MODULES_TO_CHECK[@]}"; do
    if $PYTHON_CMD -c "import $mod" 2>/dev/null; then
        ok "Import OK: ${mod}"
    else
        err "Import GAGAL: ${mod}"
        IMPORT_FAILED+=("$mod")
    fi
done

if [ ${#IMPORT_FAILED[@]} -ne 0 ]; then
    warn "Module berikut tidak bisa di-import:"
    for m in "${IMPORT_FAILED[@]}"; do
        warn "  - $m"
    done
    warn "Kemungkinan besar karena --user install tapi PATH belum di-reload."
    warn "Setelah installer selesai, restart terminal dan cek ulang."
fi

# ─── STEP 8: FIX PERMISSIONS & REGISTRASI ALIAS ───────────────
section "STEP 8/8 — PERMISSIONS, ALIAS & PATH SETUP"

info "Mengatur permission semua file..."
chmod 755 "${INSTALL_DIR}/gasak"
chmod 644 "${INSTALL_DIR}/"*.py 2>/dev/null || true
chmod 644 "${INSTALL_DIR}/version.txt" 2>/dev/null || true
chmod 644 "${INSTALL_DIR}/server.properties" 2>/dev/null || true
chmod 600 "${INSTALL_DIR}/.env"
ok "Permissions OK"

# Daftarkan alias ke semua shell profile yang ada
info "Mendaftarkan alias 'gasak' dan PATH setup ke shell profiles..."

ALIAS_LINE="alias gasak='${INSTALL_DIR}/gasak'"
PATH_LINE="export PATH=\"\$HOME/.local/bin:\$PATH\""
ENV_LOADER_LINE="set -a; source ${ENV_PATH}; set +a"

# Cek file profile mana yang ada
SHELL_PROFILES=()
[ -f "$HOME/.bashrc" ]        && SHELL_PROFILES+=("$HOME/.bashrc")
[ -f "$HOME/.bash_profile" ]  && SHELL_PROFILES+=("$HOME/.bash_profile")
[ -f "$HOME/.zshrc" ]         && SHELL_PROFILES+=("$HOME/.zshrc")
[ -f "$HOME/.profile" ]       && SHELL_PROFILES+=("$HOME/.profile")

for profile in "${SHELL_PROFILES[@]}"; do
    PROFILE_CHANGED=false

    # 1. PATH ~/.local/bin
    if ! grep -q "\.local/bin" "$profile" 2>/dev/null; then
        echo "" >> "$profile"
        echo "# GASAK: tambahkan ~/.local/bin ke PATH (untuk pip --user packages)" >> "$profile"
        echo "$PATH_LINE" >> "$profile"
        PROFILE_CHANGED=true
    fi

    # 2. Alias gasak
    if ! grep -q "alias gasak=" "$profile" 2>/dev/null; then
        echo "" >> "$profile"
        echo "# GASAK Toolchain Automation Engine" >> "$profile"
        echo "$ALIAS_LINE" >> "$profile"
        PROFILE_CHANGED=true
    else
        # Update alias kalau path-nya beda
        sed -i "s|alias gasak=.*|${ALIAS_LINE}|g" "$profile"
    fi

    # 3. Auto-load .env saat shell startup
    if ! grep -q "gasak-dist/.env" "$profile" 2>/dev/null; then
        echo "" >> "$profile"
        echo "# GASAK: Auto-load environment variables dari .env" >> "$profile"
        echo "[ -f \"${ENV_PATH}\" ] && set -a && source \"${ENV_PATH}\" && set +a" >> "$profile"
        PROFILE_CHANGED=true
    fi

    if [ "$PROFILE_CHANGED" = true ]; then
        ok "Profile diupdate: ${profile}"
    else
        info "Sudah lengkap, skip: ${profile}"
    fi
done

# Khusus Fish shell: syntax berbeda
FISH_CONFIG="$HOME/.config/fish/config.fish"
if command_exists fish && [ -f "$FISH_CONFIG" ]; then
    info "Fish shell terdeteksi! Setup Fish config..."
    if ! grep -q "alias gasak" "$FISH_CONFIG" 2>/dev/null; then
        echo "" >> "$FISH_CONFIG"
        echo "# GASAK Toolchain" >> "$FISH_CONFIG"
        echo "alias gasak='${INSTALL_DIR}/gasak'" >> "$FISH_CONFIG"
        echo "fish_add_path \$HOME/.local/bin" >> "$FISH_CONFIG"
        ok "Alias Fish shell didaftarkan di ${FISH_CONFIG}"
    fi
fi

# Source alias langsung di sesi ini biar langsung bisa dipake
eval "$ALIAS_LINE" 2>/dev/null || true
export PATH="$HOME/.local/bin:$PATH"

# ─── FINAL VERIFICATION SUMMARY ─────────────────────────────
echo ""
echo -e "${CYAN}════════════════════════════════════════════════════════════${RESET}"
echo -e "${GREEN}${BOLD}  GASAK TOOLCHAIN INSTALLATION COMPLETE!                    ${RESET}"
echo -e "${CYAN}════════════════════════════════════════════════════════════${RESET}"
echo ""
echo -e "  ${BOLD}[ INSTALL SUMMARY ]${RESET}"
echo -e "  ├─ Lokasi Install  : ${CYAN}${INSTALL_DIR}${RESET}"

# Tampilkan versi gasak binary
GASAK_VER=$(cat "${INSTALL_DIR}/version.txt" 2>/dev/null | tr -d '[:space:]' || echo "unknown")
echo -e "  ├─ Versi GASAK     : ${GREEN}${GASAK_VER}${RESET}"

echo ""
echo -e "  ${BOLD}[ DEPENDENCY STATUS ]${RESET}"

# Python
PY_VER=$($PYTHON_CMD --version 2>&1)
echo -e "  ├─ Python          : ${GREEN}${PY_VER}${RESET}"

# pip
PIP_VER=$($PIP_CMD --version 2>&1 | head -1)
echo -e "  ├─ PIP             : ${GREEN}${PIP_VER}${RESET}"

# System tools
for tool in sshpass fzf rsync curl; do
    if command_exists "$tool"; then
        echo -e "  ├─ ${tool}           : ${GREEN}READY${RESET}"
    else
        echo -e "  ├─ ${tool}           : ${RED}MISSING!${RESET}"
    fi
done

echo ""
echo -e "  ${BOLD}[ PYTHON MODULES ]${RESET}"
for mod in psycopg2 requests questionary iterfzf rich tkinter; do
    if $PYTHON_CMD -c "import $mod" 2>/dev/null; then
        echo -e "  ├─ ${mod}        : ${GREEN}OK${RESET}"
    else
        echo -e "  ├─ ${mod}        : ${RED}MISSING — cek manual!${RESET}"
    fi
done

echo ""
echo -e "  ${BOLD}[ .ENV STATUS ]${RESET}"
for key in GLPI_URL OUTLINE_URL OUTLINE_API_KEY LINEAR_API_KEY \
           PARKEE_SSH_USER PARKEE_SSH_PASS \
           CMS_DB_HOST CMS_DB_PORT CMS_DB_USER CMS_DB_PASS CMS_DB_NAME; do
    if grep -q "^${key}=" "$ENV_PATH" 2>/dev/null; then
        echo -e "  ├─ ${key}     : ${GREEN}✔${RESET}"
    else
        echo -e "  ├─ ${key}     : ${RED}MISSING!${RESET}"
    fi
done

echo ""
echo -e "${CYAN}════════════════════════════════════════════════════════════${RESET}"
echo -e "  ${YELLOW}${BOLD}PENTING: Reload terminal lu biar semua aktif!${RESET}"
echo ""
echo -e "  Ketik salah satu:"
echo -e "  ${CYAN}source ~/.bashrc${RESET}   (bash)"
echo -e "  ${CYAN}source ~/.zshrc${RESET}    (zsh)"
echo -e "  ${CYAN}exec fish${RESET}          (fish)"
echo ""
echo -e "  Atau langsung close & buka terminal baru."
echo ""
echo -e "  Setelah itu, jalankan GASAK:"
echo -e "  ${GREEN}${BOLD}gasak${RESET}"
echo ""
echo -e "${CYAN}════════════════════════════════════════════════════════════${RESET}"
SCRIPT_EOF
echo "DONE"
