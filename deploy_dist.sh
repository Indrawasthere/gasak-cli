#!/bin/bash

# ─────────────────────────────────────────────────────────────
# GASAK AUTO-DEPLOYER (v1.0.9 - Dual-Directory Cross Matrix)
# ─────────────────────────────────────────────────────────────

# Path Lokal Laptop Lu (Udah disesuaiin sama info dari lu cok!)
LOCAL_PROJECT_DIR="$HOME/Documents/Project/gasak"
LOCAL_DIST_DIR="$HOME/gasak-dist"

# Target Server Supeng Dedicated
SUPENG_USER="parkee"
SUPENG_IP="10.70.0.110"
SUPENG_DIR="/home/parkee/gasak-dist"
SSH_KEY="$HOME/.ssh/id_rsa"

GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RESET='\033[0m'

clear
echo -e "${CYAN}🚀 Memulai pipeline deployment otomatis via ZeroTier 70...${RESET}"
echo -e "${CYAN}───────────────────────────────────────────────────────────────${RESET}"
echo -e "${CYAN}ℹ Folder Ngoding :${RESET} ${GREEN}${LOCAL_PROJECT_DIR}${RESET}"
echo -e "${CYAN}ℹ Folder Aset Dist:${RESET} ${GREEN}${LOCAL_DIST_DIR}${RESET}"
echo -e "${CYAN}───────────────────────────────────────────────────────────────${RESET}"

# 1. Masuk ke folder project buat compile main.go
cd "$LOCAL_PROJECT_DIR"
echo -e "${YELLOW}[1/3] Mengompilasi binary GASAK (Linux amd64) dari core repo...${RESET}"
GOOS=linux GOARCH=amd64 go build -ldflags="-s -w" -o ./gasak_linux .
echo -e "${GREEN}✔ Kompilasi lokal berhasil!${RESET}"

# 2. Kirim file gabungan ke Server Supeng
echo -e "\n${YELLOW}[2/3] Mengirimkan toolchain file ke server supeng...${RESET}"

echo -e "-> Uploading fresh binary..."
scp -i "$SSH_KEY" ./gasak_linux ${SUPENG_USER}@${SUPENG_IP}:${SUPENG_DIR}/gasak
rm -f ./gasak_linux # Bersihin temp binary di folder ngoding

# Nah, bagian ini kita paksa ambil dari folder ~/gasak-dist lokal lu bre!
echo -e "-> Uploading scripts and assets dari folder local dist..."
scp -i "$SSH_KEY" \
    "$LOCAL_DIST_DIR/install.sh" \
    "$LOCAL_DIST_DIR/serve.sh" \
    "$LOCAL_DIST_DIR/log_cleaner.py" \
    "$LOCAL_DIST_DIR/version.txt" \
    ${SUPENG_USER}@${SUPENG_IP}:${SUPENG_DIR}/

echo -e "${GREEN}✔ Semua file rilis lintas direktori berhasil ditransfer!${RESET}"

# 3. Eksekusi remote daemon di Supeng
echo -e "\n${YELLOW}[3/3] Merestart HTTP Dist Server di background supeng...${RESET}"
ssh -i "$SSH_KEY" ${SUPENG_USER}@${SUPENG_IP} "
    chmod +x ${SUPENG_DIR}/gasak ${SUPENG_DIR}/serve.sh ${SUPENG_DIR}/log_cleaner.py
    
    echo '-> Mematikan proses server lama...'
    pkill -f 'python3 - 9001' 2>/dev/null || true
    pkill -f 'serve.sh' 2>/dev/null || true
    
    echo '-> Menyalakan serve.sh baru di background...'
    cd ${SUPENG_DIR}
    nohup ./serve.sh > dist_server.log 2>&1 &
    
    sleep 1.5
    echo '-> Verifikasi proses server supeng:'
    ps aux | grep 'python3' | grep '9001' | grep -v grep || echo '⚠️ Gagal memuat daemon!'
"

echo -e "\n${GREEN}───────────────────────────────────────────────────────────────${RESET}"
echo -e "${GREEN}🎉 STATUS: DEPLOYMENT SELESAI & LIVE DI SERVER SUPENG!${RESET}"
echo -e "Tim lu bisa install via:${YELLOW} curl -fsSL http://${SUPENG_IP}:9001/install.sh | bash ${RESET}"
echo -e "${GREEN}───────────────────────────────────────────────────────────────${RESET}"
