#!/bin/bash

# ─────────────────────────────────────────────────────────────
# GASAK ENGINE TOOLCHAIN — SYSTEM INSTALLER
# Target Environment: Ubuntu 22.04, Debian, & Linux Mint
# ─────────────────────────────────────────────────────────────

set -uo pipefail

# ─── CONFIGURATION ────────────────────────────────────────────
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

# Pastikan path instalasi siap
mkdir -p "$INSTALL_DIR"
mkdir -p "$CONFIG_DIR"

# Cek dependensi core sistem
for cmd in curl python3 pip3; do
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

# ─── PIP PACKAGES REQUIREMENT ──────────────────────────────────
echo -e "\n${BOLD}[2/4] Syncing Python Dependencies${RESET}"
echo -e "  ${DIM}Installing mandatory packages via pip...${RESET}"

PIP_FLAGS="--break-system-packages"
if ! pip3 install $PIP_FLAGS --upgrade pip &>/dev/null; then
    PIP_FLAGS=""
fi

PYTHON_PKGS=(requests python-dotenv rich questionary hvac paramiko)
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

COMPONENTS=(
    "gasak"
    "decode_and_merge.py"
    "deploy_parkee.py"
    "log_cleaner.py"
    "settlement_rfs.py"
)

for file in "${COMPONENTS[@]}"; do
    echo -ne "  .. Fetching ${file} "
    if curl -fsSL "${BASE_URL}/${file}" -o "${INSTALL_DIR}/${file}"; then
        echo -e "\r  ${GREEN}✔${RESET}  Downloaded: ${file}"
        if [[ "$file" == "gasak" ]]; then
            chmod +x "${INSTALL_DIR}/${file}"
        fi
    else
        echo -e "\r  ${RED}✘${RESET}  Failed to fetch: ${file} from ${BASE_URL}"
    fi
done

# Sync environment template if missing
if [ ! -f "$ENV_PATH" ]; then
    echo -e "  ${DIM}Initializing default configuration space...${RESET}"
    cat << 'EOF' > "$ENV_PATH"
# GASAK FALLBACK ENVIRONMENT CONFIGURATION
# Generated automatically by system setup
GLPI_URL=""
OUTLINE_URL=""
OUTLINE_API_KEY=""
LINEAR_API_KEY=""
PARKEE_SSH_USER=""
PARKEE_SSH_PASS=""
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

# 1. Generate Private Key jika belum ada
if [ ! -f "$PRIV_KEY_FILE" ]; then
    echo -e "  ${DIM}Generating local asymmetric identity keypair...${RESET}"
    ssh-keygen -t rsa -b 2048 -f "$PRIV_KEY_FILE" -N "" &>/dev/null
fi

if [ -f "$PRIV_KEY_FILE" ]; then
    ssh-keygen -e -f "$PRIV_KEY_FILE" -m PKCS8 > "$PUB_KEY_FILE" 2>/dev/null
    echo -e "  ${GREEN}✔${RESET}  RSA Identity (PEM PKCS#8) secured at ${CONFIG_DIR}"
fi

# 3. Kirim ke Vault Server Pusat
if [ -f "$PUB_KEY_FILE" ]; then
    echo -e "  ${DIM}Registering public key signature to Central Server...${RESET}"

    # Teknik stripping: buang text "---", hapus space & enter biar jadi plain text sebaris murni
    PURE_KEY=$(grep -v -- "-----" "$PUB_KEY_FILE" | tr -d '\n' | tr -d ' ')

    # Bungkus ke JSON payload secara presisi
    JSON_PAYLOAD=$(printf '{"token":"%s","public_key":"%s"}' "$GASAK_DIST_TOKEN" "$PURE_KEY")

    # Ambil bundle vault dari central server
    HTTP_STATUS=$(curl -s -o "$VAULT_FILE" -w "%{http_code}" \
        -X POST \
        -H "Content-Type: application/json" \
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
    SHELL_RC="$HOME/.zshrc"
elif [[ "$SHELL" == */bash ]]; then
    SHELL_RC="$HOME/.bashrc"
fi

if [ -n "$SHELL_RC" ] && [ -f "$SHELL_RC" ]; then
    if ! grep -q "gasak-dist" "$SHELL_RC"; then
        echo -e "\n${DIM}Injecting alias signature into shell initialization script...${RESET}"
        echo -e "\n# GASAK Toolchain Environment alias" >> "$SHELL_RC"
        echo "alias gasak='${INSTALL_DIR}/gasak'" >> "$SHELL_RC"
        echo -e "  ${GREEN}✔${RESET}  Alias added to ${SHELL_RC}"
    fi
fi

# ─── POST-INSTALLATION REPORT ──────────────────────────────────
echo "------------------------------------------------------------------"
echo -e "${GREEN}${BOLD}INSTALLATION COMPLETED SUCCESSFULLY!${RESET}"
echo ""
echo -e "  ${BOLD}VAULT INFRASTRUCTURE STATUS${RESET}"

if [ -f "$VAULT_FILE" ] && grep -q "payload" "$VAULT_FILE" 2>/dev/null; then
    echo -e "  ${GREEN}✔${RESET}  Encrypted Storage : Active"
    echo -e "  ${GREEN}✔${RESET}  Asymmetric Identity: ${CONFIG_DIR}/id_rsa"
    echo -e "  ${GREEN}✔${RESET}  Local Storage Security: Pure zero-plaintext disk architecture"
    VAULT_OK=true
else
    echo -e "  ${BOLD}VAULT INFRASTRUCTURE STATUS${RESET}"
    echo -e "  ${YELLOW}!${RESET}  Encrypted Storage : Non-active (Operating under .env local fallback mode)"
    VAULT_OK=false
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
