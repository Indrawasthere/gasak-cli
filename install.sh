#!/bin/bash

# ─────────────────────────────────────────────────────────────
# GASAK ENGINE TOOLCHAIN — SYSTEM INSTALLER
# Target Environment: Ubuntu 22.04, Debian, & Linux Mint (Baru itu sii)
# ─────────────────────────────────────────────────────────────

set -uo pipefail

# ─── CONFIGURATION ────────────────────────────────────────────
SERVER_IP="10.70.0.110"
SERVER_PORT="9001"
VAULT_PORT="9002"
GASAK_DIST_TOKEN="gsk_dist_9f2k7x"
BASE_URL="http://${SERVER_IP}:${SERVER_PORT}"
VAULT_URL="http://${SERVER_IP}:${VAULT_PORT}"

# AUTO-DETECT REAL USER HOME PATH (Menghindari conflict beda session user)
REAL_USER="${SUDO_USER:-$(logname 2>/dev/null || echo "$USER")}"
REAL_HOME=$(eval echo "~$REAL_USER")

INSTALL_DIR="${REAL_HOME}/gasak-dist"
ENV_PATH="${INSTALL_DIR}/.env"
CONFIG_DIR="${REAL_HOME}/.config/gasak"

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
  ██║   ███╗███████║███████╗███████║█████╔╝
  ██║   ██║██╔══██║╚════██║██╔══██║██╔═██╗
  ╚██████╔╝██║  ██║███████║██║  ██║██║  ██╗
   ╚═════╝ ╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝
BANNER
echo -e "${RESET}"
echo -e "${BOLD}GASAK SYSTEM TOOLCHAIN AUTOMATIC INSTALLER${RESET}"
echo -e "${DIM}Preparing binary setup and internal workspace environment...${RESET}"
echo "------------------------------------------------------------------"

# ─── PRE-FLIGHT CHECK ──────────────────────────────────────────
echo -e "\n${BOLD}[1/4] Pre-flight Check${RESET}"

# Deteksi OS
if [ -f /etc/os-release ]; then
    . /etc/os-release
    echo -e "  ${GREEN}✔${RESET}  OS Detected: ${NAME} ${VERSION_ID}"
else
    echo -e "  ${YELLOW}!${RESET}  Unknown Linux Distribution"
fi

mkdir -p "$INSTALL_DIR"
mkdir -p "$CONFIG_DIR"

for cmd in curl python3 pip3 openssl; do
    if command -v "$cmd" &>/dev/null; then
        echo -e "  ${GREEN}✔${RESET}  Command '${cmd}' ready"
    else
        if [ "$cmd" = "pip3" ]; then
            echo -e "  ${YELLOW}!${RESET}  'pip3' not found, attempting apt install..."
            sudo apt update && sudo apt install -y python3-pip
        else
            echo -e "  ${RED}✘${RESET}  Required command '${cmd}' is missing. Please install it first."
            exit 1
        fi
    fi
done

# System libraries required for Python packages + toolchain deps
echo -e "  ${DIM}Checking system libraries...${RESET}"
for lib in build-essential libpq-dev fzf sshpass rsync; do
    if dpkg -l 2>/dev/null | grep -q "^ii  $lib"; then
        echo -e "  ${GREEN}✔${RESET}  Library '${lib}' ready"
    else
        echo -e "  ${YELLOW}!${RESET}  Library '${lib}' not found, installing..."
        sudo apt update -qq && sudo apt install -y "$lib" 2>/dev/null || \
            echo -e "  ${RED}✘${RESET}  Failed to install '${lib}' — install manual: sudo apt install ${lib}"
    fi
done

# ─── PIP PACKAGES REQUIREMENT ──────────────────────────────────
echo -e "\n${BOLD}[2/4] Syncing Python Dependencies${RESET}"
echo -e "  ${DIM}Installing mandatory packages via pip...${RESET}"

PIP_FLAGS="--break-system-packages"
if ! pip3 install $PIP_FLAGS --upgrade pip &>/dev/null; then
    PIP_FLAGS=""
fi

PYTHON_PKGS=(requests python-dotenv rich questionary hvac paramiko psycopg2-binary iterfzf)
for pkg in "${PYTHON_PKGS[@]}"; do
    if python3 -c "import $pkg" &>/dev/null; then
        echo -e "  ${GREEN}✔${RESET}  Python module '${pkg}' already installed"
    else
        echo -ne "  .. Installing '${pkg}' "
        if pip3 install $PIP_FLAGS "$pkg" &>/dev/null; then
            echo -e "\r  ${GREEN}✔${RESET}  Python module '${pkg}' installed successfully"
        else
            echo -e "\r  ${RED}✘${RESET}  Failed to install '${pkg}' via pip"
        fi
    fi
done

# ─── DOWNLOAD BINARY & ENGINES ─────────────────────────────────
echo -e "\n${BOLD}[3/4] Pulling Toolchain Components from Dist Server${RESET}"

DEVICE_HOST=$(hostname 2>/dev/null || echo "unknown-device")

COMPONENTS=(
    "gasak"
    "decode_and_merge.py"
    "deploy_parkee.py"
    "log_cleaner.py"
    "settlement_rfs.py"
)

for file in "${COMPONENTS[@]}"; do
    echo -ne "  .. Fetching ${file} "
    if curl -fsSL \
        -H "X-Gasak-Host: ${DEVICE_HOST}" \
        "${BASE_URL}/${file}" -o "${INSTALL_DIR}/${file}"; then
        echo -e "\r  ${GREEN}✔${RESET}  Downloaded: ${file}"
        if [[ "$file" == "gasak" ]]; then
            chmod +x "${INSTALL_DIR}/${file}"
        fi
    else
        echo -e "\r  ${RED}✘${RESET}  Failed to fetch: ${file} from ${BASE_URL}"
    fi
done

if [ ! -f "$ENV_PATH" ]; then
    echo -e "  ${DIM}Initializing default configuration space...${RESET}"
    cat << 'EOF' > "$ENV_PATH"
# GASAK FALLBACK ENVIRONMENT CONFIGURATION
# Generated automatically by system setup
# Note: Vault takes priority. Set these for fallback or development.

# URLs
GLPI_URL=""
OUTLINE_URL=""

# APIs
OUTLINE_API_KEY=""
LINEAR_API_KEY=""

# SSH Credentials (for deployment & log access)
PARKEE_SSH_USER="support"
PARKEE_SSH_PASS=""

# Google Sheets (for location data)
# Use either GSHEET_DEPLOY_ID or SPREADSHEET_ID (main.go supports both)
GSHEET_DEPLOY_ID=""
GSHEET_DEPLOY_GID=""

# CMS Database (for settlement & log queries)
CMS_DB_HOST=""
CMS_DB_PORT="5432"
CMS_DB_USER=""
CMS_DB_PASS=""
CMS_DB_NAME=""
EOF
    echo -e "  ${GREEN}✔${RESET}  Template .env created at ${ENV_PATH}"
fi

# ─── VAULT REGISTRATION & SINKRONISASI ──────────────────────────
echo -e "\n${BOLD}[4/4] Verifying Security Keypair & Local Vault Encryption${RESET}"

PUB_KEY_FILE="${CONFIG_DIR}/id_rsa.pub"
PRIV_KEY_FILE="${CONFIG_DIR}/id_rsa"
VAULT_FILE="${CONFIG_DIR}/vault"

# 1. Hapus sisa keypair/vault lama biar ga konflik key mismatch pas reinstall
rm -f "$PRIV_KEY_FILE" "$PUB_KEY_FILE" "$VAULT_FILE"

# 2. Generate Private Key dengan FORMAT PEM STANDAR (PKCS#1)
echo -e "  ${DIM}Generating local asymmetric identity keypair...${RESET}"
ssh-keygen -t rsa -b 2048 -m PEM -f "$PRIV_KEY_FILE" -N "" &>/dev/null

# 3. Ekstrak Public Key ke format PKCS#8 murni pake OpenSSL
if [ -f "$PRIV_KEY_FILE" ]; then
    openssl rsa -in "$PRIV_KEY_FILE" -pubout -out "$PUB_KEY_FILE" &>/dev/null
    echo -e "  ${GREEN}✔${RESET}  RSA Identity generated successfully"
fi

# 4. Kirim ke Vault Server Pusat
if [ -f "$PUB_KEY_FILE" ]; then
    echo -e "  ${DIM}Registering public key signature to Central Server...${RESET}"

    PURE_KEY=$(grep -v -- "-----" "$PUB_KEY_FILE" | tr -d '\n' | tr -d '\r' | tr -d ' ')

    JSON_PAYLOAD=$(printf '{"token":"%s","public_key":"%s"}' "$GASAK_DIST_TOKEN" "$PURE_KEY")

    HTTP_STATUS=$(curl -s -o "$VAULT_FILE" -w "%{http_code}" \
            -X POST \
            -H "Content-Type: application/json" \
            -H "X-Gasak-Host: ${DEVICE_HOST}" \
            -d "$JSON_PAYLOAD" \
            "${VAULT_URL}/getenv")

    if [ "$HTTP_STATUS" -eq 200 ]; then
        echo -e "  ${GREEN}✔${RESET}  Local vault synchronized and locked successfully"
    else
        echo -e "  ${YELLOW}!${RESET}  Server registration rejected (Code: ${HTTP_STATUS}) — Falling back to .env mode"
        rm -f "$VAULT_FILE"
    fi
fi

# ─── PATH INJECTION ───────────────────────────────────────────
SHELL_RC=""
if [[ "$SHELL" == */zsh ]]; then
    SHELL_RC="${REAL_HOME}/.zshrc"
elif [[ "$SHELL" == */bash ]]; then
    SHELL_RC="${REAL_HOME}/.bashrc"
fi

if [ -n "$SHELL_RC" ] && [ -f "$SHELL_RC" ]; then
    if ! grep -q "gasak-dist" "$SHELL_RC"; then
        echo -e "\n${DIM}Injecting alias signature into shell initialization script...${RESET}"
        echo -e "\n# GASAK Toolchain Environment alias" >> "$SHELL_RC"
        echo "alias gasak='${INSTALL_DIR}/gasak'" >> "$SHELL_RC"
        echo -e "  ${GREEN}✔${RESET}  Alias added to ${SHELL_RC}"
    fi
fi

chown -R "${REAL_USER}:${REAL_USER}" "$INSTALL_DIR" "$CONFIG_DIR" 2>/dev/null

# ─── POST-INSTALLATION REPORT ──────────────────────────────────
echo "------------------------------------------------------------------"
echo -e "${GREEN}${BOLD}INSTALLATION COMPLETED SUCCESSFULLY!${RESET}"
echo ""
echo -e "  ${BOLD}VAULT INFRASTRUCTURE STATUS${RESET}"

if [ -f "$VAULT_FILE" ] && grep -q "payload" "$VAULT_FILE" 2>/dev/null; then
    echo -e "  ${GREEN}✔${RESET}  Encrypted Storage : Active"
    echo -e "  ${GREEN}✔${RESET}  Asymmetric Identity: ${CONFIG_DIR}/id_rsa"
    echo -e "  ${GREEN}✔${RESET}  Local Storage Security: Pure zero-plaintext disk architecture"
else
    echo -e "  ${YELLOW}!${RESET}  Encrypted Storage : Non-active (Operating under .env local fallback mode)"
fi

echo ""
echo -e "  ${BOLD}WORKSPACE COMPONENTS${RESET}"
for f in gasak decode_and_merge.py deploy_parkee.py log_cleaner.py settlement_rfs.py; do
    if [ -f "${INSTALL_DIR}/${f}" ]; then
        SIZE=$(du -sh "${INSTALL_DIR}/${f}" 2>/dev/null | cut -f1 || echo "?")
        printf "  ${GREEN}✔${RESET}  %-28s ${DIM}%s${RESET}\n" "$f" "(${SIZE})"
    else
        printf "  ${RED}✘${RESET}  %-28s ${RED}MISSING${RESET}\n" "$f"
    fi
done

echo ""
echo -e "  ${BOLD}GETTING STARTED${RESET}"
echo -e "  ${DIM}Reload your current shell environment session first:${RESET}"
echo -e "${CYAN}  source ${SHELL_RC}${RESET}"
echo -e "  ${DIM}Then invoke the core engine menu by running:${RESET}"
echo -e "${CYAN}  gasak${RESET}"
echo "------------------------------------------------------------------"
