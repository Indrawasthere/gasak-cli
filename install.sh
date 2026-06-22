#!/bin/bash

# ─────────────────────────────────────────────────────────────
# GASAK ENGINE TOOLCHAIN — SYSTEM INSTALLER v2.1
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

REAL_USER="${SUDO_USER:-$(logname 2>/dev/null || echo "$USER")}"
REAL_HOME=$(eval echo "~$REAL_USER")

INSTALL_DIR="${REAL_HOME}/gasak-dist"
ENV_PATH="${INSTALL_DIR}/.env"
CONFIG_DIR="${REAL_HOME}/.config/gasak"
AGENT_DIR="/opt/app/agent/parkee-agent"

# Download timeouts (forgiving for slow internet)
CURL_TIMEOUT_CONNECT=30
CURL_TIMEOUT_MAX=300
CURL_TIMEOUT_BINARY=600
CURL_RETRIES=3
CURL_RETRY_DELAY=2

# ─── COLORS & STYLES ────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
DIM='\033[2m'
BOLD='\033[1m'
RESET='\033[0m'

# ─── UTILITY FUNCTIONS ───────────────────────────────────────
progress_bar() {
    local current=$1
    local total=$2
    local width=40
    local percentage=$((current * 100 / total))
    local filled=$((current * width / total))
    local empty=$((width - filled))

    printf "\r  ${CYAN}[${GREEN}"
    printf '█%.0s' $(seq 1 $filled 2>/dev/null) || true
    printf "${DIM}"
    printf '░%.0s' $(seq 1 $empty 2>/dev/null) || true
    printf "${RESET}${CYAN}] ${WHITE}%3d%%${RESET}" "$percentage"
}

spinner_animation() {
    local pid=$1
    local message=$2
    local spinstr='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local i=0

    while kill -0 "$pid" 2>/dev/null; do
        printf "\r  ${CYAN}│${RESET}  ${MAGENTA}${spinstr:$((i % 9)):1}${RESET} ${message}"
        i=$((i + 1))
        sleep 0.1
    done
}

animated_apt_install() {
    local pkg=$1
    local idx=$2
    local total=$3

    sudo apt install -y "$pkg" &>/dev/null &
    local pid=$!

    spinner_animation $pid "Installing ${pkg}..."
    wait $pid
    local status=$?

    if [ $status -eq 0 ]; then
        printf "\r  ${CYAN}│${RESET}  ${GREEN}✔${RESET}  ${pkg} ${GREEN}installed${RESET}                          \n"
    else
        printf "\r  ${CYAN}│${RESET}  ${YELLOW}!${RESET}  ${pkg} ${YELLOW}failed (non-critical)${RESET}           \n"
    fi
}

# ─── HEADER ─────────────────────────────────────────────────
clear

echo ""
echo -e "${MAGENTA}  ██████╗  █████╗ ███████╗ █████╗ ██╗  ██╗${RESET}"
echo -e "${MAGENTA}  ██╔════╝ ██╔══██╗██╔════╝██╔══██╗██║ ██╔╝${RESET}"
echo -e "${MAGENTA}  ██║   ███╗███████║███████╗███████║█████╔╝${RESET}"
echo -e "${MAGENTA}  ██║   ██║██╔══██║╚════██║██╔══██║██╔═██╗${RESET}"
echo -e "${MAGENTA}  ╚██████╔╝██║  ██║███████║██║  ██║██║  ██╗${RESET}"
echo -e "${MAGENTA}   ╚═════╝ ╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝${RESET}"
echo ""
echo -e "${BOLD}${WHITE}  ╔═══════════════════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}${WHITE}  ║${RESET}  ${CYAN}GASAK SYSTEM TOOLCHAIN INSTALLER${RESET}  ${DIM}v2.1${RESET}                  ${BOLD}${WHITE}║${RESET}"
echo -e "${BOLD}${WHITE}  ╚═══════════════════════════════════════════════════════════╝${RESET}"
echo ""
echo -e "  ${DIM}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo ""

echo -e "${BOLD}${CYAN}  ┌─ PREFLIGHT: Validating sudo access${RESET}"
echo -e "  ${CYAN}│${RESET}"
echo -e "  ${CYAN}│${RESET}  ${DIM}Masukkan password sudo kamu sekarang:${RESET}"
if sudo -v 2>/dev/null; then
    echo -e "\r  ${CYAN}│${RESET}  ${GREEN}✔${RESET}  Sudo access validated                          "
else
    echo -e "\r  ${CYAN}│${RESET}  ${RED}✘${RESET}  ${RED}Sudo access denied${RESET}                           "
    echo -e "  ${CYAN}└─${RESET}"
    exit 1
fi
echo -e "  ${CYAN}└─${RESET}"
echo ""

# ─── STEP 1: PRE-FLIGHT CHECK ───────────────────────────────
echo -e "${BOLD}${CYAN}  ┌─ STEP 1/5: System Compatibility Check${RESET}"
echo -e "  ${CYAN}│${RESET}"

echo -ne "  ${CYAN}│${RESET}  ${DIM}Checking network connectivity...${RESET}"
if curl -s --connect-timeout 5 "http://${SERVER_IP}:${SERVER_PORT}" >/dev/null 2>&1; then
    echo -e "\r  ${CYAN}│${RESET}  ${GREEN}✔${RESET}  Network: ${GREEN}Connected${RESET}                    "
else
    echo -e "\r  ${CYAN}│${RESET}  ${RED}✘${RESET}  Network: ${RED}Cannot reach ${SERVER_IP}:${SERVER_PORT}${RESET}"
    echo -e "  ${CYAN}│${RESET}"
    echo -e "  ${CYAN}└─${RESET} ${RED}${BOLD}Installation aborted — check your network${RESET}"
    exit 1
fi

echo -ne "  ${CYAN}│${RESET}  ${DIM}Detecting operating system...${RESET}"
if [ -f /etc/os-release ]; then
    . /etc/os-release
    echo -e "\r  ${CYAN}│${RESET}  ${GREEN}✔${RESET}  OS: ${WHITE}${NAME} ${VERSION_ID}${RESET}                     "
else
    echo -e "\r  ${CYAN}│${RESET}  ${YELLOW}!${RESET}  OS: ${YELLOW}Unknown Linux Distribution${RESET}              "
fi

echo -ne "  ${CYAN}│${RESET}  ${DIM}Checking disk space...${RESET}"
AVAIL_MB=$(df -m "$REAL_HOME" 2>/dev/null | awk 'NR==2{print $4}' || echo "0")
if [ "$AVAIL_MB" -gt 100 ]; then
    echo -e "\r  ${CYAN}│${RESET}  ${GREEN}✔${RESET}  Disk: ${GREEN}${AVAIL_MB}MB available${RESET}                        "
else
    echo -e "\r  ${CYAN}│${RESET}  ${YELLOW}!${RESET}  Disk: ${YELLOW}Low space (${AVAIL_MB}MB)${RESET}                        "
fi

echo -ne "  ${CYAN}│${RESET}  ${DIM}Preparing workspace...${RESET}"
mkdir -p "$INSTALL_DIR" "$CONFIG_DIR" "$AGENT_DIR" 2>/dev/null
echo -e "\r  ${CYAN}│${RESET}  ${GREEN}✔${RESET}  Workspace ready                                   "

echo -e "  ${CYAN}└─${RESET}"
echo ""

# ─── STEP 2: DEPENDENCY INSTALLATION ────────────────────────
echo -e "${BOLD}${CYAN}  ┌─ STEP 2/5: Dependency Installation${RESET}"
echo -e "  ${CYAN}│${RESET}"

DEPS_CMD=(curl python3 pip3 openssl ssh-keygen)
for cmd in "${DEPS_CMD[@]}"; do
    echo -ne "  ${CYAN}│${RESET}  ${DIM}Checking ${cmd}...${RESET}"
    if command -v "$cmd" &>/dev/null; then
        echo -e "\r  ${CYAN}│${RESET}  ${GREEN}✔${RESET}  ${cmd}                                     "
    else
        if [ "$cmd" = "pip3" ]; then
            echo -e "\r  ${CYAN}│${RESET}  ${YELLOW}→${RESET}  Installing python3-pip...                    "
            sudo apt update -qq && sudo apt install -y python3-pip >/dev/null 2>&1
        elif [ "$cmd" = "ssh-keygen" ]; then
            echo -e "\r  ${CYAN}│${RESET}  ${YELLOW}→${RESET}  Installing openssh-client...                  "
            sudo apt install -y openssh-client >/dev/null 2>&1
        else
            echo -e "\r  ${CYAN}│${RESET}  ${RED}✘${RESET}  ${cmd}: ${RED}MISSING${RESET}                           "
        fi
    fi
done

echo -e "  ${CYAN}│${RESET}"
echo -e "  ${CYAN}│${RESET}  ${DIM}Installing system libraries...${RESET}"
LIBS=(build-essential libpq-dev fzf sshpass rsync)
LIB_TOTAL=${#LIBS[@]}

for i in "${!LIBS[@]}"; do
    lib="${LIBS[$i]}"
    if dpkg -l 2>/dev/null | grep -q "^ii  $lib"; then
        progress_bar $((i + 1)) $LIB_TOTAL
    else
        animated_apt_install "$lib" $((i + 1)) $LIB_TOTAL
    fi
done
echo ""

echo -e "  ${CYAN}│${RESET}  ${GREEN}✔${RESET}  System libraries ready                         "
echo -e "  ${CYAN}└─${RESET}"
echo ""

# ─── STEP 3: PYTHON DEPENDENCIES ────────────────────────────
echo -e "${BOLD}${CYAN}  ┌─ STEP 3/5: Python Environment Setup${RESET}"
echo -e "  ${CYAN}│${RESET}"

PIP_FLAGS="--break-system-packages"
if ! pip3 install $PIP_FLAGS --upgrade pip &>/dev/null; then
    PIP_FLAGS=""
fi

PYTHON_PKGS=(requests python-dotenv rich questionary hvac paramiko psycopg2-binary iterfzf)
PKG_TOTAL=${#PYTHON_PKGS[@]}

for i in "${!PYTHON_PKGS[@]}"; do
    pkg="${PYTHON_PKGS[$i]}"
    echo -ne "  ${CYAN}│${RESET}  ${DIM}[$((i + 1))/${PKG_TOTAL}] ${pkg}...${RESET}"

    if python3 -c "import $pkg" &>/dev/null; then
        echo -e "\r  ${CYAN}│${RESET}  ${GREEN}✔${RESET}  ${pkg} ${DIM}(cached)${RESET}                          "
    else
        pip3 install $PIP_FLAGS "$pkg" &>/dev/null &
        pip_pid=$!
        spinner_animation $pip_pid "Installing ${pkg}..."
        wait $pip_pid
        if [ $? -eq 0 ]; then
            echo -e "\r  ${CYAN}│${RESET}  ${GREEN}✔${RESET}  ${pkg} ${GREEN}installed${RESET}                          "
        else
            echo -e "\r  ${CYAN}│${RESET}  ${YELLOW}!${RESET}  ${pkg} ${YELLOW}(optional)${RESET}                        "
        fi
    fi
done

echo -e "  ${CYAN}└─${RESET}"
echo ""

# ─── STEP 4: COMPONENT DOWNLOAD ─────────────────────────────
echo -e "${BOLD}${CYAN}  ┌─ STEP 4/5: Downloading GASAK Components${RESET}"
echo -e "  ${CYAN}│${RESET}"

DEVICE_HOST=$(hostname 2>/dev/null || echo "unknown-device")

COMPONENTS=(
    "gasak"
    "decode_and_merge.py"
    "deploy_parkee.py"
    "log_cleaner.py"
    "settlement_rfs.py"
    "server.properties"
)

COMP_TOTAL=${#COMPONENTS[@]}
DOWNLOADED=0
FAILED=0

for i in "${!COMPONENTS[@]}"; do
    file="${COMPONENTS[$i]}"
    echo -ne "  ${CYAN}│${RESET}  ${DIM}[$((i + 1))/${COMP_TOTAL}] Fetching ${file}...${RESET}"

    if [[ "$file" == "server.properties" ]]; then
        TARGET_DIR="$AGENT_DIR"
    else
        TARGET_DIR="$INSTALL_DIR"
    fi

    # Use longer timeout for binary
    if [[ "$file" == "gasak" ]]; then
        TIMEOUT=$CURL_TIMEOUT_BINARY
    else
        TIMEOUT=$CURL_TIMEOUT_MAX
    fi

    curl -fsSL \
        --connect-timeout $CURL_TIMEOUT_CONNECT \
        --max-time $TIMEOUT \
        --retry $CURL_RETRIES \
        --retry-delay $CURL_RETRY_DELAY \
        -H "X-Gasak-Host: ${DEVICE_HOST}" \
        -H "X-Gasak-Version: $(cat "${TARGET_DIR}/version.txt" 2>/dev/null || echo 'installing')" \
        -H "X-Gasak-User: ${REAL_USER}" \
        "${BASE_URL}/${file}" -o "${TARGET_DIR}/${file}" 2>/dev/null &
    dl_pid=$!

    spinner_animation $dl_pid "Downloading ${file}..."
    wait $dl_pid
    status=$?

    if [ $status -eq 0 ]; then
        fsize=$(du -h "${TARGET_DIR}/${file}" 2>/dev/null | cut -f1 || echo "?")
        printf "\r  ${CYAN}│${RESET}  ${GREEN}✔${RESET}  ${file} ${GREEN}downloaded${RESET} ${DIM}(${fsize})${RESET}              \n"
        DOWNLOADED=$((DOWNLOADED + 1))

        if [[ "$file" == "gasak" ]]; then
            chmod +x "${TARGET_DIR}/${file}"
        fi
        if [[ "$file" == "server.properties" ]]; then
            sudo chown -R "${REAL_USER}:${REAL_USER}" "$AGENT_DIR"
        fi
    else
        printf "\r  ${CYAN}│${RESET}  ${RED}✘${RESET}  ${file} ${RED}failed${RESET} ${DIM}(retry: curl -fsSL ${BASE_URL}/${file})${RESET}\n"
        FAILED=$((FAILED + 1))
    fi
done

echo -e "  ${CYAN}│${RESET}"
echo -e "  ${CYAN}│${RESET}  ${DIM}Downloaded: ${GREEN}${DOWNLOADED}${RESET}/${COMP_TOTAL} components"
if [ $FAILED -gt 0 ]; then
    echo -e "  ${CYAN}│${RESET}  ${DIM}Failed: ${YELLOW}${FAILED}${RESET} (can be pulled during deployment)"
fi

echo -e "  ${CYAN}└─${RESET}"
echo ""

# ─── STEP 5: CONFIGURATION & VAULT SETUP ────────────────────
echo -e "${BOLD}${CYAN}  ┌─ STEP 5/5: Security & Configuration${RESET}"
echo -e "  ${CYAN}│${RESET}"

if [ ! -f "$ENV_PATH" ]; then
    echo -e "  ${CYAN}│${RESET}  ${DIM}Creating environment configuration...${RESET}"
    cat << 'EOF' > "$ENV_PATH"
# GASAK ENVIRONMENT CONFIGURATION
# Generated by GASAK Installer v2.1

# URLs
GLPI_URL=""
OUTLINE_URL=""

# APIs
OUTLINE_API_KEY=""
LINEAR_API_KEY=""

# SSH Credentials
PARKEE_SSH_USER="support"
PARKEE_SSH_PASS=""

# Google Sheets
GSHEET_DEPLOY_ID=""
GSHEET_DEPLOY_GID=""

# CMS Database
CMS_DB_HOST=""
CMS_DB_PORT="5432"
CMS_DB_USER=""
CMS_DB_PASS=""
CMS_DB_NAME=""
EOF
    echo -e "  ${CYAN}│${RESET}  ${GREEN}✔${RESET}  Environment template created                    "
else
    echo -e "  ${CYAN}│${RESET}  ${GREEN}✔${RESET}  Environment file exists (skipped)               "
fi

PUB_KEY_FILE="${CONFIG_DIR}/id_rsa.pub"
PRIV_KEY_FILE="${CONFIG_DIR}/id_rsa"
VAULT_FILE="${CONFIG_DIR}/vault"

rm -f "$PRIV_KEY_FILE" "$PUB_KEY_FILE" "$VAULT_FILE" 2>/dev/null

echo -e "  ${CYAN}│${RESET}  ${DIM}Generating RSA identity keypair...${RESET}"
ssh-keygen -t rsa -b 2048 -m PEM -f "$PRIV_KEY_FILE" -N "" &>/dev/null

if [ -f "$PRIV_KEY_FILE" ]; then
    openssl rsa -in "$PRIV_KEY_FILE" -pubout -out "$PUB_KEY_FILE" &>/dev/null
    echo -e "  ${CYAN}│${RESET}  ${GREEN}✔${RESET}  RSA-2048 identity generated                    "
fi

echo -e "  ${CYAN}│${RESET}  ${DIM}Registering with central vault...${RESET}"
if [ -f "$PUB_KEY_FILE" ]; then
    PURE_KEY=$(grep -v -- "-----" "$PUB_KEY_FILE" | tr -d '\n' | tr -d '\r' | tr -d ' ')
    JSON_PAYLOAD=$(printf '{"token":"%s","public_key":"%s"}' "$GASAK_DIST_TOKEN" "$PURE_KEY")

    HTTP_STATUS=$(curl -s -o "$VAULT_FILE" -w "%{http_code}" \
        --connect-timeout 10 --max-time 15 \
        -X POST \
        -H "Content-Type: application/json" \
        -H "X-Gasak-Host: ${DEVICE_HOST}" \
        -d "$JSON_PAYLOAD" \
        "${VAULT_URL}/getenv")

    if [ "$HTTP_STATUS" -eq 200 ]; then
        echo -e "  ${CYAN}│${RESET}  ${GREEN}✔${RESET}  Vault synchronized & encrypted                 "
    else
        echo -e "  ${CYAN}│${RESET}  ${YELLOW}!${RESET}  Vault offline — using .env fallback mode       "
        rm -f "$VAULT_FILE"
    fi
fi

SHELL_RC=""
if [[ "$SHELL" == */zsh ]]; then
    SHELL_RC="${REAL_HOME}/.zshrc"
elif [[ "$SHELL" == */bash ]]; then
    SHELL_RC="${REAL_HOME}/.bashrc"
fi

if [ -n "$SHELL_RC" ] && [ -f "$SHELL_RC" ]; then
    if ! grep -q "gasak-dist" "$SHELL_RC"; then
        echo -e "  ${CYAN}│${RESET}  ${DIM}Injecting shell alias...${RESET}"
        echo -e "\n# GASAK Toolchain" >> "$SHELL_RC"
        echo "alias gasak='${INSTALL_DIR}/gasak'" >> "$SHELL_RC"
        echo -e "  ${CYAN}│${RESET}  ${GREEN}✔${RESET}  Shell alias configured                         "
    else
        echo -e "  ${CYAN}│${RESET}  ${GREEN}✔${RESET}  Shell alias exists (skipped)                   "
    fi
fi

chown -R "${REAL_USER}:${REAL_USER}" "$INSTALL_DIR" "$CONFIG_DIR" "$AGENT_DIR" 2>/dev/null

echo -e "  ${CYAN}└─${RESET}"
echo ""

# ─── INSTALLATION COMPLETE ──────────────────────────────────
echo -e "  ${DIM}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo ""
echo -e "  ${GREEN}${BOLD}╔═══════════════════════════════════════════════════════════╗${RESET}"
echo -e "  ${GREEN}${BOLD}║${RESET}  ${GREEN}${BOLD}INSTALLATION COMPLETE${RESET}                                   ${GREEN}${BOLD}║${RESET}"
echo -e "  ${GREEN}${BOLD}╚═══════════════════════════════════════════════════════════╝${RESET}"
echo ""

echo -e "  ${BOLD}${CYAN}Security Status:${RESET}"
if [ -f "$VAULT_FILE" ] && grep -q "payload" "$VAULT_FILE" 2>/dev/null; then
    echo -e "    ${GREEN}●${RESET} Encrypted Vault:   ${GREEN}Active${RESET}"
    echo -e "    ${GREEN}●${RESET} Identity Key:      ${GREEN}${CONFIG_DIR}/id_rsa${RESET}"
else
    echo -e "    ${YELLOW}●${RESET} Encrypted Vault:   ${YELLOW}Offline (using .env)${RESET}"
fi
echo ""

echo -e "  ${BOLD}${CYAN}Installed Components:${RESET}"
for f in gasak decode_and_merge.py deploy_parkee.py log_cleaner.py settlement_rfs.py; do
    if [ -f "${INSTALL_DIR}/${f}" ]; then
        SIZE=$(du -sh "${INSTALL_DIR}/${f}" 2>/dev/null | cut -f1 || echo "?")
        echo -e "    ${GREEN}●${RESET} ${f}  ${DIM}(${SIZE})${RESET}"
    else
        echo -e "    ${RED}●${RESET} ${f}  ${RED}(missing)${RESET}"
    fi
done

if [ -f "${AGENT_DIR}/server.properties" ]; then
    echo -e "    ${GREEN}●${RESET} server.properties  ${DIM}(${AGENT_DIR})${RESET}"
fi
echo ""

echo -e "  ${BOLD}${CYAN}Quick Start:${RESET}"
echo -e "    ${DIM}1.${RESET} Reload your shell:"
echo -e "       ${CYAN}source ${SHELL_RC}${RESET}"
echo -e "    ${DIM}2.${RESET} Run GASAK:"
echo -e "       ${CYAN}gasak${RESET}"
echo ""
echo -e "  ${DIM}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "  ${DIM}GASAK Engine • Fadlan's Handmade • github.com/parkee${RESET}"
echo ""
