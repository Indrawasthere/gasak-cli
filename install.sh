#!/bin/bash

# ─────────────────────────────────────────────────────────────
# GASAK ENGINE TOOLCHAIN — SYSTEM INSTALLER v2.0
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

# ─── PROGRESS BAR FUNCTION ──────────────────────────────────
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

# ─── SPINNER FUNCTION ───────────────────────────────────────
spinner() {
    local pid=$1
    local delay=0.1
    local spinstr='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'

    while kill -0 "$pid" 2>/dev/null; do
        for (( i=0; i<${#spinstr}; i++ )); do
            printf "\r  ${MAGENTA}${spinstr:$i:1}${RESET} Processing..."
            sleep $delay
        done
    done
    printf "\r"
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
echo -e "${BOLD}${WHITE}  ║${RESET}  ${CYAN}GASAK SYSTEM TOOLCHAIN INSTALLER${RESET}  ${DIM}v2.0${RESET}                  ${BOLD}${WHITE}║${RESET}"
echo -e "${BOLD}${WHITE}  ╚═══════════════════════════════════════════════════════════╝${RESET}"
echo ""
echo -e "  ${DIM}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo ""

# ─── STEP 1: PRE-FLIGHT CHECK ───────────────────────────────
echo -e "${BOLD}${CYAN}  ┌─ STEP 1/5: System Compatibility Check${RESET}"
echo -e "  ${CYAN}│${RESET}"

# Check network connectivity
echo -ne "  ${CYAN}│${RESET}  ${DIM}Checking network connectivity...${RESET}"
if curl -s --connect-timeout 3 "http://${SERVER_IP}:${SERVER_PORT}" >/dev/null 2>&1; then
    echo -e "\r  ${CYAN}│${RESET}  ${GREEN}✔${RESET}  Network: ${GREEN}Connected${RESET}                    "
else
    echo -e "\r  ${CYAN}│${RESET}  ${RED}✘${RESET}  Network: ${RED}Cannot reach dist server${RESET}            "
    echo -e "  ${CYAN}│${RESET}"
    echo -e "  ${CYAN}└─${RESET} ${RED}${BOLD}Installation aborted${RESET}"
    exit 1
fi

# Detect OS
echo -ne "  ${CYAN}│${RESET}  ${DIM}Detecting operating system...${RESET}"
if [ -f /etc/os-release ]; then
    . /etc/os-release
    echo -e "\r  ${CYAN}│${RESET}  ${GREEN}✔${RESET}  OS: ${WHITE}${NAME} ${VERSION_ID}${RESET}                     "
else
    echo -e "\r  ${CYAN}│${RESET}  ${YELLOW}!${RESET}  OS: ${YELLOW}Unknown Linux Distribution${RESET}              "
fi

# Check disk space (minimum 100MB)
echo -ne "  ${CYAN}│${RESET}  ${DIM}Checking disk space...${RESET}"
AVAIL_MB=$(df -m "$REAL_HOME" 2>/dev/null | awk 'NR==2{print $4}' || echo "0")
if [ "$AVAIL_MB" -gt 100 ]; then
    echo -e "\r  ${CYAN}│${RESET}  ${GREEN}✔${RESET}  Disk: ${GREEN}${AVAIL_MB}MB available${RESET}                        "
else
    echo -e "\r  ${CYAN}│${RESET}  ${YELLOW}!${RESET}  Disk: ${YELLOW}Low space (${AVAIL_MB}MB)${RESET}                        "
fi

# Create directories
echo -ne "  ${CYAN}│${RESET}  ${DIM}Preparing workspace directories...${RESET}"
mkdir -p "$INSTALL_DIR" "$CONFIG_DIR" "$AGENT_DIR" 2>/dev/null
echo -e "\r  ${CYAN}│${RESET}  ${GREEN}✔${RESET}  Workspace ready                                   "

echo -e "  ${CYAN}└─${RESET}"
echo ""

# ─── STEP 2: DEPENDENCY INSTALLATION ────────────────────────
echo -e "${BOLD}${CYAN}  ┌─ STEP 2/5: Dependency Installation${RESET}"
echo -e "  ${CYAN}│${RESET}"

# Required commands
DEPS_CMD=(curl python3 pip3 openssl ssh-keygen)
DEPS_CMD_NAMES=(curl python3 pip3 openssl ssh-keygen)

for i in "${!DEPS_CMD[@]}"; do
    cmd="${DEPS_CMD[$i]}"
    name="${DEPS_CMD_NAMES[$i]}"
    echo -ne "  ${CYAN}│${RESET}  ${DIM}Checking ${name}...${RESET}"
    if command -v "$cmd" &>/dev/null; then
        echo -e "\r  ${CYAN}│${RESET}  ${GREEN}✔${RESET}  ${name}                                     "
    else
        if [ "$cmd" = "pip3" ]; then
            echo -e "\r  ${CYAN}│${RESET}  ${YELLOW}→${RESET}  Installing python3-pip...                    "
            sudo apt update -qq && sudo apt install -y python3-pip >/dev/null 2>&1
            if command -v pip3 &>/dev/null; then
                echo -e "  ${CYAN}│${RESET}  ${GREEN}✔${RESET}  python3-pip installed                         "
            fi
        elif [ "$cmd" = "ssh-keygen" ]; then
            echo -e "\r  ${CYAN}│${RESET}  ${YELLOW}→${RESET}  Installing openssh-client...                  "
            sudo apt install -y openssh-client >/dev/null 2>&1
        else
            echo -e "\r  ${CYAN}│${RESET}  ${RED}✘${RESET}  ${name}: ${RED}MISSING (required)${RESET}                   "
        fi
    fi
done

# System libraries
echo -e "  ${CYAN}│${RESET}"
echo -e "  ${CYAN}│${RESET}  ${DIM}Installing system libraries...${RESET}"
LIBS=(build-essential libpq-dev fzf sshpass rsync)
LIB_TOTAL=${#LIBS[@]}

for i in "${!LIBS[@]}"; do
    lib="${LIBS[$i]}"
    progress_bar $((i + 1)) $LIB_TOTAL
    if dpkg -l 2>/dev/null | grep -q "^ii  $lib"; then
        continue
    else
        sudo apt update -qq >/dev/null 2>&1 && sudo apt install -y "$lib" >/dev/null 2>&1
    fi
done
echo ""

echo -e "  ${CYAN}│${RESET}  ${GREEN}✔${RESET}  All system libraries ready                     "
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
        if pip3 install $PIP_FLAGS "$pkg" &>/dev/null; then
            echo -e "\r  ${CYAN}│${RESET}  ${GREEN}✔${RESET}  ${pkg} ${GREEN}installed${RESET}                          "
        else
            echo -e "\r  ${CYAN}│${RESET}  ${YELLOW}!${RESET}  ${pkg} ${YELLOW}(optional, skipped)${RESET}                  "
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
    
    if curl -fsSL --connect-timeout 10 --max-time 30 \
        -H "X-Gasak-Host: ${DEVICE_HOST}" \
        "${BASE_URL}/${file}" -o "${TARGET_DIR}/${file}" 2>/dev/null; then
        echo -e "\r  ${CYAN}│${RESET}  ${GREEN}✔${RESET}  ${file} ${GREEN}downloaded${RESET}                          "
        DOWNLOADED=$((DOWNLOADED + 1))
        
        if [[ "$file" == "gasak" ]]; then
            chmod +x "${TARGET_DIR}/${file}"
        fi
        if [[ "$file" == "server.properties" ]]; then
            sudo chown -R "${REAL_USER}:${REAL_USER}" "$AGENT_DIR"
        fi
    else
        echo -e "\r  ${CYAN}│${RESET}  ${RED}✘${RESET}  ${file} ${RED}failed${RESET}                             "
        FAILED=$((FAILED + 1))
    fi
done

echo -e "  ${CYAN}│${RESET}"
echo -e "  ${CYAN}│${RESET}  ${DIM}Downloaded: ${GREEN}${DOWNLOADED}${RESET}/${COMP_TOTAL} components"
if [ $FAILED -gt 0 ]; then
    echo -e "  ${CYAN}│${RESET}  ${DIM}Failed: ${YELLOW}${FAILED}${RESET} (non-critical, can be pulled during deployment)"
fi

echo -e "  ${CYAN}└─${RESET}"
echo ""

# ─── STEP 5: CONFIGURATION & VAULT SETUP ────────────────────
echo -e "${BOLD}${CYAN}  ┌─ STEP 5/5: Security & Configuration${RESET}"
echo -e "  ${CYAN}│${RESET}"

# Create .env template
if [ ! -f "$ENV_PATH" ]; then
    echo -e "  ${CYAN}│${RESET}  ${DIM}Creating environment configuration...${RESET}"
    cat << 'EOF' > "$ENV_PATH"
# GASAK ENVIRONMENT CONFIGURATION
# Generated by GASAK Installer v2.0

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

# Vault setup
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
        --connect-timeout 5 --max-time 10 \
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

# Shell alias injection
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

# Fix permissions
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

# Vault Status
echo -e "  ${BOLD}${CYAN}Security Status:${RESET}"
if [ -f "$VAULT_FILE" ] && grep -q "payload" "$VAULT_FILE" 2>/dev/null; then
    echo -e "    ${GREEN}●${RESET} Encrypted Vault:   ${GREEN}Active${RESET}"
    echo -e "    ${GREEN}●${RESET} Identity Key:      ${GREEN}${CONFIG_DIR}/id_rsa${RESET}"
else
    echo -e "    ${YELLOW}●${RESET} Encrypted Vault:   ${YELLOW}Offline (using .env)${RESET}"
fi
echo ""

# Components Status
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

# Quick Start
echo -e "  ${BOLD}${CYAN}Quick Start:${RESET}"
echo -e "    ${DIM}1.${RESET} Reload your shell:"
echo -e "       ${CYAN}source ${SHELL_RC}${RESET}"
echo -e "    ${DIM}2.${RESET} Run GASAK:"
echo -e "       ${CYAN}gasak${RESET}"
echo ""
echo -e "  ${DIM}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "  ${DIM}GASAK Engine • Fadlan's Handmade • github.com/parkee${RESET}"
echo ""
