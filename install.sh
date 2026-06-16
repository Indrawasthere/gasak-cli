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
VAULT_PORT="9002"
GASAK_DIST_TOKEN="gsk_dist_9f2k7x"
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

# Cek koneksi ke server distribusi
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

# Coba sudo dulu
SUDO_OK=false
if sudo -v 2>/dev/null; then
    SUDO_OK=true
else
    warn "sudo gak available. APT install di-skip semua."
fi

# Detect APT status
APT_UPDATE_OK=true
if [ "$SUDO_OK" = true ] && command_exists apt-get; then
    info "Ngecek status APT..."
    if ! timeout 15 sudo apt-get update -y -q 2>/dev/null; then
        warn "apt-get update gagal — tapi tetap coba install dari local cache."
        APT_UPDATE_OK=false
    fi
fi

# Repair dulu kalau APT OK
if [ "$APT_UPDATE_OK" = true ] && [ "$SUDO_OK" = true ]; then
    info "Nyoba repair broken packages dulu (kalau ada)..."
    timeout 30 sudo dpkg --configure -a 2>/dev/null || warn "dpkg configure timeout/failed, skip"
    timeout 30 sudo apt-get install -f -y 2>/dev/null || warn "apt-get -f timeout/failed, skip"
fi

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

if [ ${#FAILED_APT[@]} -ne 0 ]; then
    echo ""
    warn "Package APT berikut gagal / di-skip (NON-FATAL):"
    for p in "${FAILED_APT[@]}"; do
        warn "    - $p"
    done
    warn "Coba manual nanti: sudo apt-get install ${FAILED_APT[*]}"
fi

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
    exit 1
fi

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
    err "File berikut gagal diunduh dari server."
    exit 1
fi

ok "Semua komponen berhasil diunduh."

# ─── STEP 6: ENROLLMENT & VAULT SECURING ──────────────────────
section "STEP 6/8 — SECURING ENCRYPTED LOCAL VAULT"
info "Menyiapkan Kriptografi Asymmetric Lokal..."

mkdir -p "$HOME/.config/gasak"
PRIV_KEY_PATH="$HOME/.config/gasak/id_rsa"
PUB_KEY_PATH="$HOME/.config/gasak/id_rsa.pub"

# Generate RSA Keypair murni via OpenSSL (100% aman dari hang background process)
if [ ! -f "$PRIV_KEY_PATH" ] || [ ! -f "$PUB_KEY_PATH" ]; then
    info "Generating new secure 2048-bit RSA keypair..."
    rm -f "$PRIV_KEY_PATH" "$PUB_KEY_PATH"
    openssl genrsa -out "$PRIV_KEY_PATH" 2048 2>/dev/null
    openssl rsa -in "$PRIV_KEY_PATH" -pubout -out "$PUB_KEY_PATH" 2>/dev/null
    chmod 600 "$PRIV_KEY_PATH"
    chmod 644 "$PUB_KEY_PATH"
fi

if [ ! -f "$PUB_KEY_PATH" ]; then
    err "Gagal generate secure RSA Identity lokal via OpenSSL."
    exit 1
fi

# Escape isi public key agar valid dilempar ke format json body string
PUB_KEY_CONTENT=$(cat "$PUB_KEY_PATH" | tr '\n' ' ' | sed 's/  */ /g')

info "Menghubungi Central Vault Server untuk mengunduh enkripsi secrets..."
VAULT_RESPONSE=$(curl -s -X POST \
  -H "Content-Type: application/json" \
  -d "{\"token\":\"${GASAK_DIST_TOKEN}\", \"public_key\":\"${PUB_KEY_CONTENT}\"}" \
  "http://${SERVER_IP}:${VAULT_PORT}/getenv")

if echo "$VAULT_RESPONSE" | grep -q "encrypted_key"; then
    echo "$VAULT_RESPONSE" > "$HOME/.config/gasak/vault"
    chmod 600 "$HOME/.config/gasak/vault"
    ok "Local secure vault berhasil dikonfigurasi & di-bind ke RSA Keypair mesin ini!"
else
    err "Gagal mengambil konfigurasi secure vault dari server."
    echo -e "${RED}Server Response: ${VAULT_RESPONSE}${RESET}"
    exit 1
fi

# ══════════════════════════════════════════════════════════════
# STEP 7 — INSTALL PYTHON MODULES VIA PIP
# ══════════════════════════════════════════════════════════════
section "STEP 7/8 — INSTALL PYTHON MODULES"
info "Python: $($PYTHON_CMD --version 2>&1)"
info "pip   : $($PIP_CMD --version 2>&1 | head -1)"
echo ""

PIP_PACKAGES=(
    "psycopg2-binary"
    "requests"
    "questionary"
    "iterfzf"
    "rich"
)

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

# Pastiin ~/.local/bin masuk PATH biar pip package kepanggil
LOCAL_BIN="$HOME/.local/bin"
if [ -d "$LOCAL_BIN" ] && [[ ":$PATH:" != *":$LOCAL_BIN:"* ]]; then
    export PATH="$LOCAL_BIN:$PATH"
fi

echo ""
info "Verifikasi import module..."
MODULES_TO_CHECK=("psycopg2" "requests" "questionary" "iterfzf" "rich" "tkinter")

for mod in "${MODULES_TO_CHECK[@]}"; do
    if $PYTHON_CMD -c "import $mod" 2>/dev/null; then
        ok "import ${mod} — OK"
    else
        warn "import ${mod} — GAGAL"
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
[ -f "$ENV_PATH" ] && chmod 600 "$ENV_PATH" || true
ok "Permissions set."

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
    if ! grep -q "\.local/bin" "$profile" 2>/dev/null; then
        echo "" >> "$profile"
        echo "# GASAK: PATH ~/.local/bin" >> "$profile"
        echo "$PATH_LINE" >> "$profile"
        PROFILE_CHANGED=true
    fi
    if ! grep -q "alias gasak=" "$profile" 2>/dev/null; then
        echo "" >> "$profile"
        echo "# GASAK Toolchain" >> "$profile"
        echo "$ALIAS_LINE" >> "$profile"
        PROFILE_CHANGED=true
    fi
    if ! grep -q "gasak-dist/.env" "$profile" 2>/dev/null; then
        echo "" >> "$profile"
        echo "# GASAK: auto-load env vars" >> "$profile"
        echo "[ -f \"${ENV_PATH}\" ] && set -a && source \"${ENV_PATH}\" && set +a" >> "$profile"
        PROFILE_CHANGED=true
    fi
    if [ "$PROFILE_CHANGED" = true ]; then ok "Profile updated: ${profile}"; fi
done

eval "$ALIAS_LINE" 2>/dev/null || true
export PATH="$HOME/.local/bin:$PATH"

# ══════════════════════════════════════════════════════════════
# FINAL — SUMMARY
# ══════════════════════════════════════════════════════════════
echo ""
echo -e "${CYAN}════════════════════════════════════════════════════════════${RESET}"
echo -e "${GREEN}${BOLD}  GASAK BERHASIL DIINSTALL MURNI & AMAN!                     ${RESET}"
echo -e "${CYAN}════════════════════════════════════════════════════════════${RESET}"
echo ""
echo -e "  Silakan reload shell lu men:"
echo -e "  ${CYAN}source ~/.zshrc${RESET} atau ${CYAN}source ~/.bashrc${RESET}"
echo ""
echo -e "  Setelah itu, langsung ketik perintah sakti:"
echo -e "  ${GREEN}${BOLD}  gasak${RESET}"
echo -e "${CYAN}════════════════════════════════════════════════════════════${RESET}"
echo ""
