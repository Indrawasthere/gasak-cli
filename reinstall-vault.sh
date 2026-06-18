#!/bin/bash

SERVER_IP="10.70.0.110"
VAULT_PORT="9002"
GASAK_DIST_TOKEN="gsk_dist_9f2k7x"
VAULT_URL="http://${SERVER_IP}:${VAULT_PORT}"

REAL_USER="${SUDO_USER:-$(logname 2>/dev/null || echo "$USER")}"
REAL_HOME=$(eval echo "~$REAL_USER")

CONFIG_DIR="${REAL_HOME}/.config/gasak"
PUB_KEY_FILE="${CONFIG_DIR}/id_rsa.pub"
PRIV_KEY_FILE="${CONFIG_DIR}/id_rsa"
VAULT_FILE="${CONFIG_DIR}/vault"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

echo -e "${BOLD}GASAK VAULT SYNC — Re-registration Tool${RESET}"
echo "--------------------------------------------------"

rm -f "$PRIV_KEY_FILE" "$PUB_KEY_FILE" "$VAULT_FILE"

echo -e "${DIM}Generating fresh keypair...${RESET}"
ssh-keygen -t rsa -b 2048 -m PEM -f "$PRIV_KEY_FILE" -N "" &>/dev/null
openssl rsa -in "$PRIV_KEY_FILE" -pubout -out "$PUB_KEY_FILE" &>/dev/null
echo -e "  ${GREEN}✔${RESET}  Keypair generated"

PURE_KEY=$(grep -v -- "-----" "$PUB_KEY_FILE" | tr -d '\n' | tr -d '\r' | tr -d ' ')
JSON_PAYLOAD=$(printf '{"token":"%s","public_key":"%s"}' "$GASAK_DIST_TOKEN" "$PURE_KEY")

HTTP_STATUS=$(curl -s -o "$VAULT_FILE" -w "%{http_code}" \
    -X POST \
    -H "Content-Type: application/json" \
    -d "$JSON_PAYLOAD" \
    "${VAULT_URL}/getenv")

if [ "$HTTP_STATUS" -eq 200 ]; then
    echo -e "  ${GREEN}✔${RESET}  Vault synchronized — jalanin ulang gasak sekarang"
else
    echo -e "  ${RED}✘${RESET}  Sync gagal (HTTP ${HTTP_STATUS}) — cek koneksi ZeroTier lo"
    rm -f "$VAULT_FILE"
    exit 1
fi

chown -R "${REAL_USER}:${REAL_USER}" "$CONFIG_DIR" 2>/dev/null
echo "--------------------------------------------------"
