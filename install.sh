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
VAULT_URL="http://${SERVER_IP}:${VAULT_PORT}"
INSTALL_DIR="$HOME/gasak-dist"
ENV_PATH="${INSTALL_DIR}/.env"
CONFIG_DIR="$HOME/.config/gasak"

# ─── COLORS ───────────────────────────────────────────────────
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

clear

# ─── BANNER ───────────────────────────────────────────────────
echo -e "${CYAN}"
cat << 'BANNER'
  ██████╗  █████╗ ███████╗ █████╗ ██╗  ██╗
  ██╔════╝ ██╔══██╗██╔════╝██╔══██╗██║ ██╔╝
  ██║  ███╗███████║███████╗███████║█████╔╝
  ██║   ██║██╔══██║╚════██║██╔══██║██╔═██╗
  ╚██████╔╝██║  ██║███████║██║  ██║██║  ██╗
   ╚═════╝ ╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝
BANNER
echo -e "${RESET}"
echo -e "${DIM}  Parkee Internal Toolchain — Engine Installer${RESET}"
echo -e "${DIM}  ─────────────────────────────────────────────${RESET}"
echo ""

# ─── HELPERS ──────────────────────────────────────────────────
ok()      { echo -e "  ${GREEN}✔${RESET}  $1"; }
err()     { echo -e "  ${RED}✘${RESET}  $1"; }
info()    { echo -e "  ${CYAN}→${RESET}  $1"; }
warn()    { echo -e "  ${YELLOW}!${RESET}  $1"; }
step()    {
    echo ""
    echo -e "  ${BOLD}${CYAN}[$1]${RESET}  ${BOLD}$2${RESET}"
    echo -e "  ${DIM}$(printf '%.0s─' {1..52})${RESET}"
}
done_step() { echo -e "  ${DIM}$(printf '%.0s─' {1..52})${RESET}"; }

command_exists() { command -v "$1" >/dev/null 2>&1; }

spinner_wait() {
    local pid=$1
    local msg="${2:-tunggu...}"
    local sp='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local i=0
    while kill -0 "$pid" 2>/dev/null; do
        i=$(( (i+1) % 10 ))
        printf "\r  ${CYAN}${sp:$i:1}${RESET}  ${DIM}%s${RESET}" "$msg"
        sleep 0.1
    done
    printf "\r"
}

# ══════════════════════════════════════════════════════════════
# STEP 1 — PREFLIGHT
# ══════════════════════════════════════════════════════════════
step "1/8" "PREFLIGHT CHECK"

if [ -f /etc/os-release ]; then
    . /etc/os-release
    ok "Distro terdeteksi: ${PRETTY_NAME:-Unknown}"
else
    warn "Gak bisa deteksi distro — asumsi Debian-based"
fi

info "Ngecek koneksi ke distribution server..."
if curl -fsSL --max-time 10 --connect-timeout 5 \
    "${BASE_URL}/version.txt" -o /dev/null 2>/dev/null; then
    GASAK_VERSION=$(curl -fsSL --max-time 5 "${BASE_URL}/version.txt" 2>/dev/null | tr -d '[:space:]' || echo "unknown")
    ok "Server online — GASAK v${GASAK_VERSION} tersedia"
else
    err "Gak bisa konek ke distribution server ${SERVER_IP}:${SERVER_PORT}"
    echo ""
    echo -e "  ${DIM}Kemungkinan penyebab:${RESET}"
    echo -e "  ${DIM}  · Belum connect ke ZeroTier / VPN internal${RESET}"
    echo -e "  ${DIM}  · Server supeng (${SERVER_IP}) lagi down${RESET}"
    echo -e "  ${DIM}  · Coba: ping -c 3 ${SERVER_IP}${RESET}"
    echo ""
    exit 1
fi
done_step

# ══════════════════════════════════════════════════════════════
# STEP 2 — SYSTEM DEPENDENCIES (APT, BEST EFFORT)
# ══════════════════════════════════════════════════════════════
step "2/8" "SYSTEM DEPENDENCIES"
warn "Non-blocking — APT error tidak menghentikan instalasi"

SUDO_OK=false
if sudo -v 2>/dev/null; then SUDO_OK=true; fi

APT_UPDATE_OK=true
if [ "$SUDO_OK" = true ] && command_exists apt-get; then
    info "Update package index..."
    if ! timeout 15 sudo apt-get update -y -q 2>/dev/null; then
        warn "apt-get update gagal — pakai local cache"
        APT_UPDATE_OK=false
    fi
fi

if [ "$APT_UPDATE_OK" = true ] && [ "$SUDO_OK" = true ]; then
    timeout 30 sudo dpkg --configure -a 2>/dev/null || true
    timeout 30 sudo apt-get install -f -y 2>/dev/null || true
fi

APT_DEPS=(
    "python3" "python3-pip" "python3-tk" "python3-venv"
    "python-is-python3" "sshpass" "rsync" "unzip" "curl"
    "wget" "iputils-ping" "fzf" "lsof" "net-tools" "git"
)

FAILED_APT=()
APT_AVAILABLE=false
[ "$SUDO_OK" = true ] && command_exists apt-get && APT_AVAILABLE=true

for pkg in "${APT_DEPS[@]}"; do
    if dpkg -s "$pkg" >/dev/null 2>&1; then
        ok "Sudah ada: ${pkg}"
    elif [ "$APT_AVAILABLE" = true ]; then
        printf "  ${CYAN}→${RESET}  Install %-25s" "${pkg}..."
        if DEBIAN_FRONTEND=noninteractive timeout 60 sudo apt-get install -y -q "$pkg" 2>/dev/null; then
            echo -e " ${GREEN}✔${RESET}"
        else
            echo -e " ${YELLOW}skip${RESET}"
            FAILED_APT+=("$pkg")
        fi
    else
        FAILED_APT+=("$pkg")
    fi
done

if [ ${#FAILED_APT[@]} -ne 0 ]; then
    echo ""
    warn "Package yang gagal (non-fatal): ${FAILED_APT[*]}"
    warn "Install manual: sudo apt-get install ${FAILED_APT[*]}"
fi

if ! command_exists python && command_exists python3; then
    PYTHON3_PATH=$(command -v python3)
    sudo ln -sf "$PYTHON3_PATH" /usr/local/bin/python 2>/dev/null || true
fi
done_step

# ══════════════════════════════════════════════════════════════
# STEP 3 — VERIFIKASI PYTHON RUNTIME
# ══════════════════════════════════════════════════════════════
step "3/8" "PYTHON RUNTIME CHECK"

PYTHON_CMD=""
PIP_CMD=""

for cmd in python3 python; do
    if command_exists "$cmd"; then
        PY_VERSION=$("$cmd" --version 2>&1 | grep -oP '\d+\.\d+' | head -1)
        PY_MAJOR=$(echo "$PY_VERSION" | cut -d. -f1)
        PY_MINOR=$(echo "$PY_VERSION" | cut -d. -f2)
        if [ "$PY_MAJOR" -ge 3 ] && [ "$PY_MINOR" -ge 8 ]; then
            PYTHON_CMD="$cmd"
            ok "Python OK: $("$cmd" --version 2>&1)"
            break
        fi
    fi
done

[ -z "$PYTHON_CMD" ] && { err "Python 3.8+ tidak ditemukan. Installer berhenti."; exit 1; }

for cmd in pip3 pip; do
    if command_exists "$cmd"; then
        PIP_CMD="$cmd"
        ok "pip OK: $("$cmd" --version 2>&1 | head -1)"
        break
    fi
done

if [ -z "$PIP_CMD" ]; then
    if $PYTHON_CMD -m pip --version >/dev/null 2>&1; then
        PIP_CMD="$PYTHON_CMD -m pip"
        ok "pip via: $PYTHON_CMD -m pip"
    else
        err "pip tidak ditemukan. Installer berhenti."
        exit 1
    fi
fi
done_step

# ══════════════════════════════════════════════════════════════
# STEP 4 — SETUP DIREKTORI
# ══════════════════════════════════════════════════════════════
step "4/8" "SETUP DIREKTORI INSTALASI"

info "Menyiapkan: ${INSTALL_DIR}"
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR" || { err "Gagal masuk ke ${INSTALL_DIR}"; exit 1; }
ok "Direktori siap"
done_step

# ══════════════════════════════════════════════════════════════
# STEP 5 — DOWNLOAD KOMPONEN GASAK
# ══════════════════════════════════════════════════════════════
step "5/8" "DOWNLOAD GASAK TOOLCHAIN"
info "Mengunduh komponen dari distribution server..."
echo ""

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
    CURL_TIMEOUT=60
    [ "$file" = "gasak" ] && CURL_TIMEOUT=600

    # Resume-capable download dengan retry
    MAX_RETRIES=3
    RETRY=0
    DOWNLOAD_OK=false

    while [ $RETRY -lt $MAX_RETRIES ]; do
        RETRY=$((RETRY + 1))
        PARTIAL="${INSTALL_DIR}/${file}.partial"

        # -C - = resume dari byte terakhir kalau file partial ada
        if curl -fsSL --max-time "$CURL_TIMEOUT" --connect-timeout 15 \
            -C - \
            "${BASE_URL}/${file}" -o "${PARTIAL}" 2>/dev/null; then

            # Verifikasi file tidak kosong
            if [ -s "${PARTIAL}" ]; then
                mv "${PARTIAL}" "${INSTALL_DIR}/${file}"
                FILESIZE=$(du -sh "${INSTALL_DIR}/${file}" 2>/dev/null | cut -f1 || echo "?")
                printf "  ${GREEN}✔${RESET}  %-30s ${DIM}%s${RESET}\n" "${file}" "(${FILESIZE})"
                DOWNLOAD_OK=true
                break
            else
                warn "File kosong, retry ${RETRY}/${MAX_RETRIES}..."
                rm -f "${PARTIAL}"
            fi
        else
            [ $RETRY -lt $MAX_RETRIES ] && warn "${file} gagal, retry ${RETRY}/${MAX_RETRIES}..." || true
            rm -f "${PARTIAL}"
            sleep 1
        fi
    done

    if [ "$DOWNLOAD_OK" = false ]; then
        printf "  ${RED}✘${RESET}  %-30s ${RED}GAGAL setelah %d retry${RESET}\n" "${file}" "$MAX_RETRIES"
        DOWNLOAD_FAILED+=("$file")
    fi
done

echo ""
if [ ${#DOWNLOAD_FAILED[@]} -ne 0 ]; then
    err "Download gagal untuk: ${DOWNLOAD_FAILED[*]}"
    err "Cek koneksi ZeroTier dan coba ulang."
    exit 1
fi
ok "Semua komponen berhasil diunduh"
done_step

# ══════════════════════════════════════════════════════════════
# STEP 6 — VAULT ENROLLMENT (ASYMMETRIC CRYPTO)
# ══════════════════════════════════════════════════════════════
step "6/8" "SECURING ENCRYPTED LOCAL VAULT"

# Pakai $HOME yang bener — BUKAN hardcoded username
mkdir -p "$CONFIG_DIR"
chmod 700 "$CONFIG_DIR"
rm -f "$CONFIG_DIR/id_rsa" "$CONFIG_DIR/id_rsa.pub"

info "Generating RSA-2048 keypair di ${CONFIG_DIR}..."
openssl genrsa -out "$CONFIG_DIR/id_rsa" 2048 > /dev/null 2>&1
openssl rsa -in "$CONFIG_DIR/id_rsa" -pubout -out "$CONFIG_DIR/id_rsa.pub" > /dev/null 2>&1
chmod 600 "$CONFIG_DIR/id_rsa"
chmod 644 "$CONFIG_DIR/id_rsa.pub"

PUB_KEY_PATH="$CONFIG_DIR/id_rsa.pub"
if [ ! -f "$PUB_KEY_PATH" ]; then
    err "Gagal generate RSA keypair."
    exit 1
fi
ok "RSA keypair di-bind ke: ${CONFIG_DIR}"

# Kirim public key ke vault server, terima secrets terenkripsi
PUB_KEY_CONTENT=$(awk '{printf "%s\\n", $0}' "$PUB_KEY_PATH")

info "Menghubungi GASAK Vault Server (${SERVER_IP}:${VAULT_PORT})..."

VAULT_RESPONSE=$(curl -s --max-time 15 --connect-timeout 10 \
  -X POST \
  -H "Content-Type: application/json" \
  -d "{\"token\":\"${GASAK_DIST_TOKEN}\", \"public_key\":\"${PUB_KEY_CONTENT}\"}" \
  "${VAULT_URL}/getenv")

if echo "$VAULT_RESPONSE" | grep -q "encrypted_key"; then
    echo "$VAULT_RESPONSE" > "$CONFIG_DIR/vault"
    chmod 600 "$CONFIG_DIR/vault"
    ok "Vault berhasil di-bind ke mesin ini"
    ok "Secrets dienkripsi RSA — tidak ada plaintext di disk"
else
    err "Vault enrollment gagal."
    echo -e "  ${DIM}Response: ${VAULT_RESPONSE}${RESET}"
    echo ""
    warn "Installer tetap lanjut — fallback ke .env mode"
    warn "Ping Fadlan kalau ini terus-terusan error"
fi
done_step

# ══════════════════════════════════════════════════════════════
# STEP 7 — PYTHON MODULES
# ══════════════════════════════════════════════════════════════
step "7/8" "PYTHON DEPENDENCIES"
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
    printf "  ${CYAN}→${RESET}  Install %-25s" "${pkg}..."
    if pip_install_with_fallback "$pkg"; then
        VER=$($PYTHON_CMD -c "import importlib.metadata; print(importlib.metadata.version('${pkg}'))" 2>/dev/null || echo "ok")
        echo -e " ${GREEN}✔${RESET} ${DIM}v${VER}${RESET}"
    else
        echo -e " ${RED}✘ GAGAL${RESET}"
        PIP_FAILED+=("$pkg")
    fi
done

LOCAL_BIN="$HOME/.local/bin"
if [ -d "$LOCAL_BIN" ] && [[ ":$PATH:" != *":$LOCAL_BIN:"* ]]; then
    export PATH="$LOCAL_BIN:$PATH"
fi

echo ""
info "Verifikasi import..."
MODULES_TO_CHECK=("psycopg2" "requests" "questionary" "iterfzf" "rich" "tkinter")
for mod in "${MODULES_TO_CHECK[@]}"; do
    if $PYTHON_CMD -c "import $mod" 2>/dev/null; then
        ok "import ${mod}"
    else
        warn "import ${mod} — tidak tersedia"
    fi
done
done_step

# ══════════════════════════════════════════════════════════════
# STEP 8 — PERMISSIONS, ALIAS & SHELL SETUP
# ══════════════════════════════════════════════════════════════
step "8/8" "SHELL SETUP & PERMISSIONS"

chmod 755 "${INSTALL_DIR}/gasak"
chmod 644 "${INSTALL_DIR}/"*.py 2>/dev/null || true
chmod 644 "${INSTALL_DIR}/version.txt" 2>/dev/null || true
chmod 644 "${INSTALL_DIR}/server.properties" 2>/dev/null || true
ok "File permissions set"

ALIAS_LINE="alias gasak='${INSTALL_DIR}/gasak'"
PATH_LINE="export PATH=\"\$HOME/.local/bin:\$PATH\""

SHELL_PROFILES=()
[ -f "$HOME/.bashrc" ]       && SHELL_PROFILES+=("$HOME/.bashrc")
[ -f "$HOME/.bash_profile" ] && SHELL_PROFILES+=("$HOME/.bash_profile")
[ -f "$HOME/.zshrc" ]        && SHELL_PROFILES+=("$HOME/.zshrc")
[ -f "$HOME/.profile" ]      && SHELL_PROFILES+=("$HOME/.profile")

for profile in "${SHELL_PROFILES[@]}"; do
    CHANGED=false
    if ! grep -q "\.local/bin" "$profile" 2>/dev/null; then
        { echo ""; echo "# GASAK: PATH ~/.local/bin"; echo "$PATH_LINE"; } >> "$profile"
        CHANGED=true
    fi
    if ! grep -q "alias gasak=" "$profile" 2>/dev/null; then
        { echo ""; echo "# GASAK Toolchain"; echo "$ALIAS_LINE"; } >> "$profile"
        CHANGED=true
    fi
    [ "$CHANGED" = true ] && ok "Shell profile updated: $(basename "$profile")"
done

eval "$ALIAS_LINE" 2>/dev/null || true
export PATH="$HOME/.local/bin:$PATH"
done_step

# ══════════════════════════════════════════════════════════════
# FINAL SUMMARY
# ══════════════════════════════════════════════════════════════
echo ""
echo ""
echo -e "  ${DIM}$(printf '%.0s═' {1..52})${RESET}"
echo -e "  ${GREEN}${BOLD}  GASAK v${GASAK_VERSION} BERHASIL DIINSTALL${RESET}"
echo -e "  ${DIM}$(printf '%.0s═' {1..52})${RESET}"
echo ""

# ── Status Vault ──────────────────────────────────────────────
VAULT_FILE="$CONFIG_DIR/vault"
if [ -f "$VAULT_FILE" ] && grep -q "encrypted_key" "$VAULT_FILE" 2>/dev/null; then
    echo -e "  ${BOLD}VAULT STATUS${RESET}"
    echo -e "  ${GREEN}✔${RESET}  Vault terenkripsi aktif"
    echo -e "  ${GREEN}✔${RESET}  RSA keypair: ${CONFIG_DIR}/id_rsa"
    echo -e "  ${GREEN}✔${RESET}  Secrets: tidak ada plaintext di disk"
    VAULT_OK=true
else
    echo -e "  ${BOLD}VAULT STATUS${RESET}"
    echo -e "  ${YELLOW}!${RESET}  Vault tidak aktif — mode .env fallback"
    VAULT_OK=false
fi

echo ""
echo -e "  ${BOLD}KOMPONEN${RESET}"
for f in gasak decode_and_merge.py deploy_parkee.py log_cleaner.py settlement_rfs.py; do
    if [ -f "${INSTALL_DIR}/${f}" ]; then
        SIZE=$(du -sh "${INSTALL_DIR}/${f}" 2>/dev/null | cut -f1 || echo "?")
        printf "  ${GREEN}✔${RESET}  %-30s ${DIM}%s${RESET}\n" "$f" "(${SIZE})"
    else
        printf "  ${RED}✘${RESET}  %-30s ${RED}MISSING${RESET}\n" "$f"
    fi
done

echo ""
echo -e "  ${BOLD}CARA PAKAI${RESET}"
echo -e "  ${DIM}Reload shell dulu men:${RESET}"
echo -e "  ${CYAN}  source ~/.zshrc${RESET}  ${DIM}atau${RESET}  ${CYAN}source ~/.bashrc${RESET}"
echo ""
echo -e "  ${DIM}Terus langsung gas:${RESET}"
echo -e "  ${GREEN}${BOLD}  gasak${RESET}"
echo ""

if [ "$VAULT_OK" = false ]; then
    echo -e "  ${DIM}$(printf '%.0s─' {1..52})${RESET}"
    echo -e "  ${YELLOW}NOTE:${RESET} Vault enrollment gagal. Minta Fadlan cek vault-server"
    echo -e "  ${DIM}di supeng (port ${VAULT_PORT}) udah running belum.${RESET}"
    echo ""
fi

echo -e "  ${DIM}$(printf '%.0s═' {1..52})${RESET}"
echo ""
