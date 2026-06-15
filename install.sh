#!/bin/bash

# ─────────────────────────────────────────────────────────────
# GASAK ENGINE TOOLCHAIN — INSTALLER
# Target: Ubuntu 22.04, Debian, Linux Mint dan turunannya
# ─────────────────────────────────────────────────────────────

# Sengaja gak pake set -e — biar APT yang error gak langsung
# ngebunuh seluruh proses install. Python & pip = blocker,
# APT = best effort.
set -uo pipefail

# ─── CONFIG ───────────────────────────────────────────────────
SERVER_IP="10.70.0.110"
SERVER_PORT="9001"
BASE_URL="http://${SERVER_IP}:${SERVER_PORT}"
INSTALL_DIR="$HOME/gasak-dist"
ENV_PATH="${INSTALL_DIR}/.env"

# ─── COLORS ───────────────────────────────────────────────────
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
RESET='\033[0m'

clear
echo -e "${CYAN}════════════════════════════════════════════════════════════${RESET}"
echo -e "${CYAN}${BOLD}        GASAK ENGINE TOOLCHAIN — INSTALLER                  ${RESET}"
echo -e "${CYAN}════════════════════════════════════════════════════════════${RESET}"
echo ""

# ─── HELPERS ──────────────────────────────────────────────────
ok()      { echo -e "   ${GREEN}[✔] $1${RESET}"; }
err()     { echo -e "   ${RED}[✘] $1${RESET}"; }
info()    { echo -e "   ${CYAN}[→] $1${RESET}"; }
warn()    { echo -e "   ${YELLOW}[!] $1${RESET}"; }
section() {
    echo ""
    echo -e "${CYAN}────────────────────────────────────────────────────────────${RESET}"
    echo -e "${BOLD}  $1${RESET}"
    echo -e "${CYAN}────────────────────────────────────────────────────────────${RESET}"
}

command_exists() { command -v "$1" >/dev/null 2>&1; }

# ══════════════════════════════════════════════════════════════
# STEP 1 — CEK KONEKSI KE SERVER
# ══════════════════════════════════════════════════════════════
section "STEP 1/8 — PREFLIGHT CHECK"

# Deteksi distro
if [ -f /etc/os-release ]; then
    . /etc/os-release
    info "Distro: ${PRETTY_NAME:-Unknown}"
else
    warn "Gak bisa deteksi distro, lanjut aja dengan asumsi Debian-based."
fi

# Cek koneksi ke server distribusi — ini blocker, kalau ga bisa konek ya
# percuma download apapun
info "Ngecek koneksi ke server distribusi ${SERVER_IP}:${SERVER_PORT}..."
if curl -fsSL --max-time 10 --connect-timeout 5 \
    "${BASE_URL}/version.txt" -o /dev/null 2>/dev/null; then
    GASAK_VERSION=$(curl -fsSL --max-time 5 "${BASE_URL}/version.txt" 2>/dev/null \
        | tr -d '[:space:]' || echo "unknown")
    ok "Server online! Versi GASAK tersedia: ${GASAK_VERSION}"
else
    err "Gak bisa konek ke server distribusi ${SERVER_IP}:${SERVER_PORT}!"
    err "Kemungkinan penyebab:"
    err "  1. Belum connect ke ZeroTier / VPN internal"
    err "  2. Server supeng (${SERVER_IP}) lagi mati"
    err "  3. Coba ping dulu: ping -c 3 ${SERVER_IP}"
    exit 1
fi

# ══════════════════════════════════════════════════════════════
# STEP 2 — APT SYSTEM DEPENDENCIES (NON-BLOCKING)
# ══════════════════════════════════════════════════════════════
section "STEP 2/8 — SYSTEM DEPENDENCIES VIA APT (BEST EFFORT)"
warn "Step ini NON-BLOCKING. APT gagal = lanjut, bukan abort."
warn "Kalau ada yang miss, nanti dikasih tau di summary bawah ya men."
echo ""

# Coba sudo dulu — kalau gagal juga gapapa, APT emang skip
SUDO_OK=false
if sudo -v 2>/dev/null; then
    SUDO_OK=true
else
    warn "sudo gak available. APT install di-skip semua."
fi

# Detect APT status — kalau update gagal, tetap coba install (package mungkin di local cache)
APT_UPDATE_OK=true
if [ "$SUDO_OK" = true ] && command_exists apt-get; then
    info "Ngecek status APT..."
    if ! timeout 15 sudo apt-get update -y -q 2>/dev/null; then
        warn "apt-get update gagal — tapi tetap coba install dari local cache."
        APT_UPDATE_OK=false
    fi
fi

# Repair dulu kalau APT OK (biar gak hang di sistem broken)
if [ "$APT_UPDATE_OK" = true ] && [ "$SUDO_OK" = true ]; then
    info "Nyoba repair broken packages dulu (kalau ada)..."
    timeout 30 sudo dpkg --configure -a 2>/dev/null || warn "dpkg configure timeout/failed, skip"
    timeout 30 sudo apt-get install -f -y 2>/dev/null || warn "apt-get -f timeout/failed, skip"
fi

# Package yang dibutuhin:
# python3, python3-pip, python3-tk  → Python runtime + tkinter (log_cleaner.py)
# python-is-python3                 → biar 'python' ngepoint ke python3
# sshpass                           → SSH automation (deploy_parkee.py) — APT ONLY
# fzf                               → iterfzf dependency — APT ONLY
# sisanya                           → utility dasar
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

# APT_AVAILABLE: true kalau sudo + apt-get ada (tetap coba walau update gagal)
APT_AVAILABLE=false
if [ "$SUDO_OK" = true ] && command_exists apt-get; then
    APT_AVAILABLE=true
fi

if [ "$APT_AVAILABLE" = false ]; then
    warn "apt-get gak ada / sudo gak available. Skip semua APT install."
fi

for pkg in "${APT_DEPS[@]}"; do
    if dpkg -s "$pkg" >/dev/null 2>&1; then
        ALREADY_INSTALLED+=("$pkg")
        ok "Udah ada: ${pkg}"
    elif [ "$APT_AVAILABLE" = true ]; then
        info "Install: ${pkg}..."
        if DEBIAN_FRONTEND=noninteractive timeout 60 sudo apt-get install -y -q "$pkg" 2>/dev/null; then
            INSTALLED_NEW+=("$pkg")
            ok "Keinstall: ${pkg}"
        else
            warn "Gagal install ${pkg} via APT — skip, lanjut"
            FAILED_APT+=("$pkg")
        fi
    else
        FAILED_APT+=("$pkg")
    fi
done

# Summary APT — info doang, bukan abort
if [ ${#FAILED_APT[@]} -ne 0 ]; then
    echo ""
    warn "Package APT berikut gagal / di-skip (NON-FATAL):"
    for p in "${FAILED_APT[@]}"; do
        warn "    - $p"
    done
    warn "Coba manual nanti: sudo apt-get install ${FAILED_APT[*]}"
    warn "Note: sshpass & python3-tk cuma bisa via APT, gak ada pip-nya."
fi

# Fallback: kalau 'python' command gak ada tapi 'python3' ada, bikin symlink
if ! command_exists python && command_exists python3; then
    warn "'python' command gak ada. Bikin symlink ke python3..."
    PYTHON3_PATH=$(command -v python3)
    if sudo ln -sf "$PYTHON3_PATH" /usr/local/bin/python 2>/dev/null; then
        ok "Symlink python → python3 dibuat di /usr/local/bin/"
    else
        warn "Gagal bikin symlink. 'python3' tetap jalan kok, tenang."
    fi
fi

# ══════════════════════════════════════════════════════════════
# STEP 3 — VERIFIKASI PYTHON RUNTIME
# ══════════════════════════════════════════════════════════════
section "STEP 3/8 — CEK PYTHON RUNTIME"

PYTHON_CMD=""
PIP_CMD=""

# Cari python yang valid, minimal 3.8
for cmd in python3 python; do
    if command_exists "$cmd"; then
        PY_VERSION=$("$cmd" --version 2>&1 | grep -oP '\d+\.\d+' | head -1)
        PY_MAJOR=$(echo "$PY_VERSION" | cut -d. -f1)
        PY_MINOR=$(echo "$PY_VERSION" | cut -d. -f2)
        if [ "$PY_MAJOR" -ge 3 ] && [ "$PY_MINOR" -ge 8 ]; then
            PYTHON_CMD="$cmd"
            ok "Python OK: $("$cmd" --version 2>&1) → command: $cmd"
            break
        else
            warn "Python ketemu tapi versinya jadul: $("$cmd" --version 2>&1) — minimal 3.8"
        fi
    fi
done

if [ -z "$PYTHON_CMD" ]; then
    err "Python 3.8+ gak ketemu sama sekali!"
    err "Install manual dulu: sudo apt-get install python3"
    err "Installer berhenti di sini karena tanpa Python gak ada yang bisa jalan."
    exit 1
fi

# Cari pip
for cmd in pip3 pip; do
    if command_exists "$cmd"; then
        PIP_CMD="$cmd"
        ok "pip OK: $("$cmd" --version 2>&1 | head -1) → command: $cmd"
        break
    fi
done

if [ -z "$PIP_CMD" ]; then
    warn "pip gak ketemu via PATH. Nyoba lewat python -m pip..."
    if $PYTHON_CMD -m pip --version >/dev/null 2>&1; then
        PIP_CMD="$PYTHON_CMD -m pip"
        ok "pip jalan via: $PYTHON_CMD -m pip"
    else
        err "pip gak ada sama sekali. Installer berhenti."
        err "Fix: sudo apt-get install python3-pip"
        exit 1
    fi
fi

# ══════════════════════════════════════════════════════════════
# STEP 4 — SETUP DIREKTORI INSTALL
# ══════════════════════════════════════════════════════════════
section "STEP 4/8 — SETUP DIREKTORI INSTALL"
info "Nyiapin direktori: ${INSTALL_DIR}"
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR" || { err "Gagal masuk ke ${INSTALL_DIR}!"; exit 1; }
ok "Direktori siap: ${INSTALL_DIR}"

# ══════════════════════════════════════════════════════════════
# STEP 5 — DOWNLOAD SEMUA KOMPONEN GASAK
# ══════════════════════════════════════════════════════════════
section "STEP 5/8 — DOWNLOAD GASAK TOOLCHAIN"
info "Download semua file dari server distribusi..."

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
    printf "   → %-35s " "${file}..."
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
    err "File berikut gagal diunduh:"
    for f in "${DOWNLOAD_FAILED[@]}"; do
        err "  - $f"
    done
    err "Server ${SERVER_IP}:${SERVER_PORT} bisa direach tapi file-nya bermasalah."
    err "Cek serve.sh di server supeng — mungkin ada file yang missing di gasak-dist."
    exit 1
fi

ok "Semua komponen berhasil diunduh."

# ══════════════════════════════════════════════════════════════
# STEP 6 — FETCH .ENV DARI SERVER DISTRIBUSI
# ══════════════════════════════════════════════════════════════
section "STEP 6/8 — FETCH CREDENTIALS DARI SERVER"

# Token distribusi — bukan credentials, ini cuma kunci buat ambil .env dari server.
# Useless tanpa akses ZeroTier subnet 10.70.x.x (layer 1 security).
DIST_TOKEN="gsk_dist_9f2k7x"

# Backup .env lama kalau ada — jangan langsung timpah
if [ -f "$ENV_PATH" ]; then
    cp "$ENV_PATH" "${ENV_PATH}.bak"
    warn ".env lama dibackup ke: ${ENV_PATH}.bak"
fi

info "Fetching credentials dari server distribusi..."
info "(Credentials tidak ditulis di installer — diambil langsung dari server)"

# Fetch .env dari endpoint /getenv — server validasi token sebelum serve
HTTP_STATUS=$(curl -fsSL \
    --max-time 15 \
    --connect-timeout 5 \
    -w "%{http_code}" \
    "${BASE_URL}/getenv?token=${DIST_TOKEN}" \
    -o "${ENV_PATH}" \
    2>/dev/null)

if [ "$HTTP_STATUS" != "200" ]; then
    # Bersihkan file kalau gagal — jangan simpen response error sebagai .env
    rm -f "${ENV_PATH}"
    # Restore backup kalau ada
    if [ -f "${ENV_PATH}.bak" ]; then
        mv "${ENV_PATH}.bak" "${ENV_PATH}"
        warn ".env lama di-restore dari backup."
    fi
    err "Gagal fetch credentials dari server (HTTP ${HTTP_STATUS})."
    err "Kemungkinan penyebab:"
    err "  1. Server supeng (${SERVER_IP}) belum restart serve.sh setelah update"
    err "  2. Token distribusi tidak valid"
    err "  3. Koneksi ZeroTier putus di tengah jalan"
    exit 1
fi

chmod 600 "${ENV_PATH}"
ok "Credentials berhasil di-fetch & dikunci (permission 600): ${ENV_PATH}"

# Verifikasi semua key ada di .env yang baru di-fetch
REQUIRED_KEYS=(
    "GLPI_URL" "OUTLINE_URL"
    "OUTLINE_API_KEY" "LINEAR_API_KEY"
    "PARKEE_SSH_USER" "PARKEE_SSH_PASS"
    "CMS_DB_HOST" "CMS_DB_PORT" "CMS_DB_USER" "CMS_DB_PASS" "CMS_DB_NAME"
)

ENV_OK=true
for key in "${REQUIRED_KEYS[@]}"; do
    if grep -q "^${key}=" "$ENV_PATH" 2>/dev/null; then
        ok ".env key OK: ${key}"
    else
        err ".env MISSING KEY: ${key} — server mungkin serve .env yang outdated"
        ENV_OK=false
    fi
done

if [ "$ENV_OK" = false ]; then
    err "Ada key yang hilang di .env yang di-fetch!"
    err "Pastiin .env di server supeng (~/gasak-dist/.env) sudah lengkap."
    err "Cek file di server: cat ~/gasak-dist/.env"
    exit 1
fi

# ══════════════════════════════════════════════════════════════
# STEP 7 — INSTALL PYTHON MODULES VIA PIP
# ══════════════════════════════════════════════════════════════
section "STEP 7/8 — INSTALL PYTHON MODULES"
info "Python: $($PYTHON_CMD --version 2>&1)"
info "pip   : $($PIP_CMD --version 2>&1 | head -1)"
echo ""

# Package breakdown per script:
# deploy_parkee.py    → requests, questionary, iterfzf, rich
# settlement_rfs.py   → psycopg2-binary, requests
# decode_and_merge.py → stdlib only (json, argparse, urllib, pathlib, time)
# log_cleaner.py      → stdlib only (tkinter via APT, os, re, shutil, threading)
PIP_PACKAGES=(
    "psycopg2-binary"
    "requests"
    "questionary"
    "iterfzf"
    "rich"
)

# Strategi install berlapis buat handle semua kondisi:
# Ubuntu 22+ / Debian 12+ = butuh --break-system-packages
# Sistem lama = --user doang udah cukup
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
    printf "   → %-30s " "${pkg}..."
    if pip_install_with_fallback "$pkg"; then
        INSTALLED_VER=$($PYTHON_CMD -c \
            "import importlib.metadata; print(importlib.metadata.version('${pkg}'))" \
            2>/dev/null || echo "ok")
        echo -e "${GREEN}OK (${INSTALLED_VER})${RESET}"
    else
        echo -e "${RED}GAGAL${RESET}"
        PIP_FAILED+=("$pkg")
    fi
done

if [ ${#PIP_FAILED[@]} -ne 0 ]; then
    echo ""
    warn "Module pip berikut gagal install:"
    for p in "${PIP_FAILED[@]}"; do
        warn "    - $p"
    done
    warn "Coba install manual: pip3 install ${PIP_FAILED[*]}"
fi

# Pastiin ~/.local/bin ada di PATH buat sesi ini
LOCAL_BIN="$HOME/.local/bin"
if [ -d "$LOCAL_BIN" ] && [[ ":$PATH:" != *":$LOCAL_BIN:"* ]]; then
    export PATH="$LOCAL_BIN:$PATH"
fi

# Verifikasi import — buat ngecek apakah semua module bisa dipake
echo ""
info "Verifikasi import module..."
IMPORT_FAILED=()
MODULES_TO_CHECK=("psycopg2" "requests" "questionary" "iterfzf" "rich" "tkinter")

for mod in "${MODULES_TO_CHECK[@]}"; do
    if $PYTHON_CMD -c "import $mod" 2>/dev/null; then
        ok "import ${mod} — OK"
    else
        warn "import ${mod} — GAGAL (cek summary bawah)"
        IMPORT_FAILED+=("$mod")
    fi
done

# ══════════════════════════════════════════════════════════════
# STEP 8 — PERMISSIONS, ALIAS & SHELL SETUP
# ══════════════════════════════════════════════════════════════
section "STEP 8/8 — PERMISSIONS, ALIAS & SHELL SETUP"

info "Set permission semua file..."
chmod 755 "${INSTALL_DIR}/gasak"
chmod 644 "${INSTALL_DIR}/"*.py  2>/dev/null || true
chmod 644 "${INSTALL_DIR}/version.txt" 2>/dev/null || true
chmod 644 "${INSTALL_DIR}/server.properties" 2>/dev/null || true
chmod 600 "${INSTALL_DIR}/.env"
ok "Permissions set."

# Setup alias, PATH, dan auto-load .env ke semua shell profile yang ada
info "Daftarin alias & PATH ke shell profiles..."

ALIAS_LINE="alias gasak='${INSTALL_DIR}/gasak'"
PATH_LINE="export PATH=\"\$HOME/.local/bin:\$PATH\""

SHELL_PROFILES=()
[ -f "$HOME/.bashrc" ]       && SHELL_PROFILES+=("$HOME/.bashrc")
[ -f "$HOME/.bash_profile" ] && SHELL_PROFILES+=("$HOME/.bash_profile")
[ -f "$HOME/.zshrc" ]        && SHELL_PROFILES+=("$HOME/.zshrc")
[ -f "$HOME/.profile" ]      && SHELL_PROFILES+=("$HOME/.profile")

for profile in "${SHELL_PROFILES[@]}"; do
    PROFILE_CHANGED=false

    # 1. PATH ~/.local/bin
    if ! grep -q "\.local/bin" "$profile" 2>/dev/null; then
        echo "" >> "$profile"
        echo "# GASAK: ~/.local/bin ke PATH (pip --user packages)" >> "$profile"
        echo "$PATH_LINE" >> "$profile"
        PROFILE_CHANGED=true
    fi

    # 2. Alias gasak
    if ! grep -q "alias gasak=" "$profile" 2>/dev/null; then
        echo "" >> "$profile"
        echo "# GASAK Toolchain" >> "$profile"
        echo "$ALIAS_LINE" >> "$profile"
        PROFILE_CHANGED=true
    else
        sed -i "s|alias gasak=.*|${ALIAS_LINE}|g" "$profile"
    fi

    # 3. Auto-load .env waktu shell start
    if ! grep -q "gasak-dist/.env" "$profile" 2>/dev/null; then
        echo "" >> "$profile"
        echo "# GASAK: auto-load env vars" >> "$profile"
        echo "[ -f \"${ENV_PATH}\" ] && set -a && source \"${ENV_PATH}\" && set +a" >> "$profile"
        PROFILE_CHANGED=true
    fi

    if [ "$PROFILE_CHANGED" = true ]; then
        ok "Profile diupdate: ${profile}"
    else
        info "Udah lengkap, skip: ${profile}"
    fi
done

# Fish shell — syntax beda
FISH_CONFIG="$HOME/.config/fish/config.fish"
if command_exists fish && [ -f "$FISH_CONFIG" ]; then
    info "Fish shell ketemu! Setup config.fish..."
    if ! grep -q "alias gasak" "$FISH_CONFIG" 2>/dev/null; then
        echo "" >> "$FISH_CONFIG"
        echo "# GASAK Toolchain" >> "$FISH_CONFIG"
        echo "alias gasak='${INSTALL_DIR}/gasak'" >> "$FISH_CONFIG"
        echo "fish_add_path \$HOME/.local/bin" >> "$FISH_CONFIG"
        ok "Fish alias didaftarkan di ${FISH_CONFIG}"
    fi
fi

# Aktifin alias langsung di sesi ini biar gak perlu reload dulu buat pertama kali
eval "$ALIAS_LINE" 2>/dev/null || true
export PATH="$HOME/.local/bin:$PATH"

# ══════════════════════════════════════════════════════════════
# FINAL — SUMMARY
# ══════════════════════════════════════════════════════════════
echo ""
echo -e "${CYAN}════════════════════════════════════════════════════════════${RESET}"
echo -e "${GREEN}${BOLD}  GASAK BERHASIL DIINSTALL                                  ${RESET}"
echo -e "${CYAN}════════════════════════════════════════════════════════════${RESET}"
echo ""

GASAK_VER=$(cat "${INSTALL_DIR}/version.txt" 2>/dev/null | tr -d '[:space:]' || echo "unknown")

echo -e "  ${BOLD}[ INFO ]${RESET}"
echo -e "  ├─ Lokasi     : ${CYAN}${INSTALL_DIR}${RESET}"
echo -e "  ├─ Versi      : ${GREEN}${GASAK_VER}${RESET}"
echo -e "  ├─ Python     : ${GREEN}$($PYTHON_CMD --version 2>&1)${RESET}"
echo -e "  └─ pip        : ${GREEN}$($PIP_CMD --version 2>&1 | head -1)${RESET}"
echo ""

echo -e "  ${BOLD}[ SYSTEM TOOLS ]${RESET}"
for tool in sshpass fzf rsync curl; do
    if command_exists "$tool"; then
        echo -e "  ├─ ${tool:<10} : ${GREEN}✔ ready${RESET}"
    else
        echo -e "  ├─ ${tool:<10} : ${RED}✘ missing — menu terkait akan error${RESET}"
    fi
done
echo ""

echo -e "  ${BOLD}[ PYTHON MODULES ]${RESET}"
for mod in psycopg2 requests questionary iterfzf rich tkinter; do
    if $PYTHON_CMD -c "import $mod" 2>/dev/null; then
        echo -e "  ├─ ${mod:<15} : ${GREEN}✔ ok${RESET}"
    else
        echo -e "  ├─ ${mod:<15} : ${RED}✘ missing${RESET}"
    fi
done
echo ""

echo -e "  ${BOLD}[ .ENV KEYS ]${RESET}"
for key in GLPI_URL OUTLINE_URL OUTLINE_API_KEY LINEAR_API_KEY \
           PARKEE_SSH_USER PARKEE_SSH_PASS \
           CMS_DB_HOST CMS_DB_PORT CMS_DB_USER CMS_DB_PASS CMS_DB_NAME; do
    if grep -q "^${key}=" "$ENV_PATH" 2>/dev/null; then
        echo -e "  ├─ ${key:<20} : ${GREEN}✔${RESET}"
    else
        echo -e "  ├─ ${key:<20} : ${RED}✘ MISSING!${RESET}"
    fi
done
echo ""

# Kalau ada APT yang miss, remind di sini juga
if [ ${#FAILED_APT[@]} -ne 0 ]; then
    echo -e "  ${BOLD}[ APT YANG GAGAL — PERLU PERHATIAN ]${RESET}"
    for p in "${FAILED_APT[@]}"; do
        echo -e "  ├─ ${RED}${p}${RESET}"
    done
    echo -e "  └─ ${YELLOW}Fix: sudo apt-get install ${FAILED_APT[*]}${RESET}"
    echo ""
fi

# Info kalau APT update gagal tapi tetap jalan
if [ "$APT_UPDATE_OK" = false ]; then
    warn "Note: apt-get update gagal, tapi package tetap dicoba install dari cache."
fi

echo -e "${CYAN}════════════════════════════════════════════════════════════${RESET}"
echo -e "  ${YELLOW}${BOLD}Reload terminal dulu biar alias & env aktif!${RESET}"
echo ""
echo -e "  Pilih salah satu:"
echo -e "    ${CYAN}source ~/.bashrc${RESET}   ← kalau bash"
echo -e "    ${CYAN}source ~/.zshrc${RESET}    ← kalau zsh"
echo -e "    ${CYAN}exec fish${RESET}          ← kalau fish"
echo ""
echo -e "  Atau close & buka terminal baru. Abis itu:"
echo -e "  ${GREEN}${BOLD}  gasak${RESET}"
echo ""
echo -e "${CYAN}════════════════════════════════════════════════════════════${RESET}"
ENDOFFILE
echo "DONE"
