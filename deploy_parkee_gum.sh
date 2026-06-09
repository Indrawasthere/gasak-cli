#!/usr/bin/env bash

# ─────────────────────────────────────────────────────────────
# ENVIRONMENT
# ─────────────────────────────────────────────────────────────

export TERM=xterm-256color
unset PROMPT_COMMAND
unset TERMINAL_EMULATOR

set -uo pipefail

# ─────────────────────────────────────────────────────────────
# CONFIG
# ─────────────────────────────────────────────────────────────

SPREADSHEET_ID="1A0ce374Dgw3pS4w05Yw9y1flJK5pZi6D-UUII6PG5VM"
SHEET_GID="463772829"
CSV_URL="https://docs.google.com/spreadsheets/d/${SPREADSHEET_ID}/export?format=csv&gid=${SHEET_GID}"

SSH_USER="${PARKEE_SSH_USER:-support}"
SSH_PASS="${PARKEE_SSH_PASS:-REMOVED_PASSWORD}"

APP_DIR="/opt/app/agent/parkee-agent"
SERVER_PROPERTIES="${APP_DIR}/server.properties"

JAVA_BIN="/usr/lib/jvm/bellsoft-java15-full-amd64/bin/java"
JAR_NAME="parkee-agent-production.jar"
AGENT_JAR_PATH="/mnt/shared/production/parkee-agent-production.jar"

CACHE_DIR="${HOME}/.cache/parkee"
CACHE_FILE="${CACHE_DIR}/master_loc.csv"
CACHE_TTL=3600

LOG_DIR="${HOME}/logs/parkee"
LATEST_LOG=""

SSH_TIMEOUT=10
ACTUATOR_TIMEOUT=5

SENSITIVE_KEYS=("password" "username" "db" "credential.information" "minio.endpoint" "fisherman.host" "kafkaHost" "redisHost" "dbHost")

FILES_TO_SYNC=(
    "/mnt/shared/production/parkee-agent-production.jar"
    "/mnt/shared/sound"
    "/mnt/shared/dependencies"
)

# ─────────────────────────────────────────────────────────────
# COLORS
# ─────────────────────────────────────────────────────────────

PINK="#ff00ff"
CYAN="#00ffff"
GREEN="#00ff87"
RED="#ff005f"
YELLOW="#ffd700"
PURPLE="#a855f7"

# ─────────────────────────────────────────────────────────────
# INIT DIRS
# ─────────────────────────────────────────────────────────────

mkdir -p "$CACHE_DIR" "$LOG_DIR"

# ─────────────────────────────────────────────────────────────
# SSH OPTS
# ─────────────────────────────────────────────────────────────

SSH_OPTS_ARR=(
    -o StrictHostKeyChecking=no
    -o LogLevel=ERROR
    -o "ConnectTimeout=${SSH_TIMEOUT}"
)
SSH_OPTS_STR="-o StrictHostKeyChecking=no -o LogLevel=ERROR -o ConnectTimeout=${SSH_TIMEOUT}"

# ─────────────────────────────────────────────────────────────
# UI HELPERS
# ─────────────────────────────────────────────────────────────

ok()   { printf "\e[32m✔\e[0m %s\n" "$*"; }
err()  { printf "\e[31m✘\e[0m %s\n" "$*" >&2; }
warn() { printf "\e[33m⚠\e[0m %s\n" "$*"; }
info() { printf "\e[36mℹ\e[0m %s\n" "$*"; }
line() { printf "\e[90m%s\e[0m\n" "───────────────────────────────────────────────────────────"; }

mask_ip() {
    local ip="$1"
    IFS='.' read -ra parts <<< "$ip"
    if [[ ${#parts[@]} -eq 4 ]]; then
        echo "${parts[0]}.${parts[1]}.${parts[2]}.*"
    else
        echo "***"
    fi
}

is_sensitive() {
    local key="$1"
    for sk in "${SENSITIVE_KEYS[@]}"; do
        [[ "$key" == "$sk" ]] && return 0
    done
    return 1
}

# ─────────────────────────────────────────────────────────────
# PROGRESS BAR
# ─────────────────────────────────────────────────────────────

render_progress() {
    local current="$1"
    local total="$2"
    local label="$3"
    local width=30

    (( total == 0 )) && total=1
    (( current > total )) && current=$total

    local percent=$(( current * 100 / total ))
    local total_ticks=$(( current * width * 8 / total ))
    local full_blocks=$(( total_ticks / 8 ))
    local partial_tick=$(( total_ticks % 8 ))

    local C_GREEN="\e[32m"
    local C_BG_GRAY="\e[48;5;235m"
    local C_FG_GRAY="\e[38;5;242m"
    local C_RESET="\e[0m"

    local bar_filled=""
    [[ $full_blocks -gt 0 ]] && bar_filled=$(printf '█%.0s' $(seq 1 $full_blocks))

    local bar_partial=""
    if (( partial_tick > 0 )); then
        case $partial_tick in
            1) bar_partial="▏" ;;
            2) bar_partial="▎" ;;
            3) bar_partial="▍" ;;
            4) bar_partial="▌" ;;
            5) bar_partial="▋" ;;
            6) bar_partial="▊" ;;
            7) bar_partial="▉" ;;
        esac
    fi

    local empty_spaces=$(( width - full_blocks ))
    [[ $partial_tick -gt 0 ]] && empty_spaces=$(( empty_spaces - 1 ))

    local bar_empty=""
    [[ $empty_spaces -gt 0 ]] && bar_empty=$(printf ' %.0s' $(seq 1 $empty_spaces))

    if [[ "$current" -eq "$total" ]]; then
        local full_bar
        full_bar=$(printf '█%.0s' $(seq 1 $width))
        printf "\r${C_GREEN}%3d%%${C_RESET} [${C_GREEN}%s${C_RESET}] %s\e[K\n" \
            "$percent" "$full_bar" "$label"
    else
        printf "\r${C_GREEN}%3d%%${C_RESET} [${C_GREEN}%s%s${C_BG_GRAY}%s${C_RESET}] ${C_FG_GRAY}%s${C_RESET}\e[K" \
            "$percent" "$bar_filled" "$bar_partial" "$bar_empty" "$label"
    fi
}

# ─────────────────────────────────────────────────────────────
# HEADER
# ─────────────────────────────────────────────────────────────

show_header() {
    clear
    gum style \
        --border double \
        --border-foreground "$PINK" \
        --foreground "$PINK" \
        --align center \
        --padding "1 4" \
"
██████╗  █████╗ ██████╗ ██╗  ██╗███████╗███████╗
██╔══██╗██╔══██╗██╔══██╗██║ ██╔╝██╔════╝██╔════╝
██████╔╝███████║██████╔╝█████╔╝ █████╗  █████╗
██╔═══╝ ██╔══██║██╔══██╗██╔═██╗ ██╔══╝  ██╔══╝
██║     ██║  ██║██║  ██╗██║  ██╗███████╗███████╗
╚═╝     ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝╚══════╝╚══════╝

EL TEMBAK AGENT
"
}

# ─────────────────────────────────────────────────────────────
# DEPENDENCY CHECK
# ─────────────────────────────────────────────────────────────

check_dependencies() {
    local deps=(gum curl rsync sshpass python3 fzf unzip bc)
    local missing=()

    for dep in "${deps[@]}"; do
        command -v "$dep" &>/dev/null || missing+=("$dep")
    done

    if (( ${#missing[@]} > 0 )); then
        err "Missing dependencies: ${missing[*]}"
        exit 1
    fi

    if [ ! -d "$APP_DIR" ]; then
        info "Creating app directory at ${APP_DIR}..."
        sudo mkdir -p "$APP_DIR"
    fi
    
    info "Validating local sudo privilege for deployment..."
    sudo -v
    
    sudo chown -R "$(whoami):$(id -gn)" "$APP_DIR"
}

# ─────────────────────────────────────────────────────────────
# LOAD SHEET
# ─────────────────────────────────────────────────────────────

load_sheet() {
    if [[ -f "$CACHE_FILE" ]]; then
        local age
        age=$(( $(date +%s) - $(stat -c %Y "$CACHE_FILE") ))
        if (( age < CACHE_TTL )); then
            ok "Using cached location data ($(( (CACHE_TTL - age) / 60 ))m remaining)"
            return 0
        fi
    fi

    gum spin \
        --spinner pulse \
        --title "Fetching Google Sheet..." \
        -- curl -sL --fail "$CSV_URL" -o "$CACHE_FILE"

    if [[ $? -ne 0 ]]; then
        err "Failed to fetch Google Sheet"
        [[ -f "$CACHE_FILE" ]] && warn "Using stale cache as fallback"
        [[ ! -f "$CACHE_FILE" ]] && exit 1
        return 0
    fi

    ok "Location data updated"
}

# ─────────────────────────────────────────────────────────────
# DETECT COLUMNS
# ─────────────────────────────────────────────────────────────

detect_columns() {
    read -r COL_UNI COL_NAME COL_IP <<< "$(
        python3 - "$CACHE_FILE" << 'PYEOF'
import csv, sys
with open(sys.argv[1], newline='', encoding='utf-8-sig') as f:
    reader = csv.reader(f)
    headers = [x.strip().lower() for x in next(reader)]
def find(name):
    return next((i for i, v in enumerate(headers) if v == name), -1)
print(find("unicode"), find("nama lokasi - unicode"), find("ip zt"))
PYEOF
    )"

    if [[ "$COL_UNI" == "-1" || "$COL_NAME" == "-1" || "$COL_IP" == "-1" ]]; then
        err "Failed detecting CSV columns (unicode=$COL_UNI, nama=$COL_NAME, ip=$COL_IP)"
        err "Check if Google Sheet headers match: 'Unicode', 'Nama Lokasi - Unicode', 'IP ZT'"
        exit 1
    fi
}

# ─────────────────────────────────────────────────────────────
# SELECT LOCATION via fzf
# ─────────────────────────────────────────────────────────────

select_location() {
    python3 - \
        "$CACHE_FILE" \
        "$COL_UNI" \
        "$COL_NAME" \
        "$COL_IP" << 'PYEOF' | fzf \
            --height 80% \
            --border \
            --prompt "SEARCH > " \
            --header $'UNICODE  | LOCATION                                      | IP (masked)' \
            --delimiter "§" \
            --with-nth "1" \
            --ansi
import csv, sys
path, cu, cn, ci = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4])

def mask_ip(ip):
    parts = ip.split(".")
    if len(parts) == 4:
        return f"{parts[0]}.{parts[1]}.{parts[2]}.*"
    return "***"

def truncate(s, n):
    return s if len(s) <= n else s[:n-3] + "..."

with open(path, newline='', encoding='utf-8-sig') as f:
    reader = csv.reader(f)
    next(reader)
    for row in reader:
        if len(row) <= max(cu, cn, ci): continue
        uni, nama, ip = row[cu].strip(), row[cn].strip(), row[ci].strip()
        if not ip: continue
        masked = mask_ip(ip)
        display = f"{uni:<8} | {truncate(nama, 45):<45} | {masked:<20}"
        # pakai separator § (unlikely ada di data) supaya fzf bisa hide field hidden
        print(f"{display}§{uni}§{nama}§{masked}§{ip}")
PYEOF
}

# ─────────────────────────────────────────────────────────────
# VERSION CHECK
# ─────────────────────────────────────────────────────────────

fetch_agent_version() {
    local ip="$1"
    local result
    result=$(sshpass -p "$SSH_PASS" ssh "${SSH_OPTS_ARR[@]}" "${SSH_USER}@${ip}" \
        "unzip -p '${AGENT_JAR_PATH}' META-INF/MANIFEST.MF 2>/dev/null | grep 'Implementation-Version' | cut -d: -f2 | tr -d ' \r'" \
        2>/dev/null)
    echo "${result:--}"
}

fetch_actuator_version() {
    local ip="$1"
    local port="$2"
    local result
    result=$(curl -sf --max-time "$ACTUATOR_TIMEOUT" "http://${ip}:${port}/actuator/info" 2>/dev/null \
        | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d['build']['version'])
except:
    print('-')
" 2>/dev/null)
    echo "${result:--}"
}

check_versions() {
    local ip="$1"
    local tmp_agent tmp_ws tmp_fs
    tmp_agent=$(mktemp)
    tmp_ws=$(mktemp)
    tmp_fs=$(mktemp)

    info "Checking versions (concurrent)..."

    fetch_agent_version "$ip" > "$tmp_agent" &
    local pid_agent=$!
    fetch_actuator_version "$ip" 9005 > "$tmp_ws" &
    local pid_ws=$!
    fetch_actuator_version "$ip" 8888 > "$tmp_fs" &
    local pid_fs=$!

    wait $pid_agent $pid_ws $pid_fs

    AGENT_VER=$(cat "$tmp_agent")
    WS_VER=$(cat "$tmp_ws")
    FS_VER=$(cat "$tmp_fs")

    rm -f "$tmp_agent" "$tmp_ws" "$tmp_fs"

    gum style \
        --border rounded \
        --border-foreground "$CYAN" \
        --padding "0 2" \
"
AGENT  : ${AGENT_VER}
WS     : ${WS_VER}
FS     : ${FS_VER}
"
}

# ─────────────────────────────────────────────────────────────
# STATS
# ─────────────────────────────────────────────────────────────

show_stats() {
    local ip="$1"
    local masked_ip
    masked_ip=$(mask_ip "$ip")

    local ping_ms
    ping_ms=$(ping -c 1 -W 1 "$ip" 2>/dev/null | awk -F'time=' '/time=/{print $2}' | cut -d' ' -f1)
    [[ -z "$ping_ms" ]] && ping_ms="OFFLINE"

    gum style \
        --border rounded \
        --border-foreground "$PURPLE" \
        --padding "0 2" \
"
TARGET STATUS

IP (masked) : ${masked_ip}
PING        : ${ping_ms} ms
SSH USER    : ${SSH_USER}
"
}

# ─────────────────────────────────────────────────────────────
# RSYNC (SAMA PERSIS DENGAN PYTHON LOGIC)
# ─────────────────────────────────────────────────────────────

sync_file() {
    local ip="$1"
    local file="$2"
    local fname
    fname=$(basename "$file")

    printf "  \e[34mℹ\e[0m Syncing: \e[1m%s\e[0m\n" "$fname"

    # Sudo + sshpass rsync dengan info progress asli dari rsync engine (--info=progress2)
    sudo sshpass -p "$SSH_PASS" rsync \
        -az \
        --info=progress2 \
        -e "ssh ${SSH_OPTS_STR}" \
        "${SSH_USER}@${ip}:${file}" \
        "${APP_DIR}/"
    
    local rc=$?
    if [[ $rc -eq 0 ]]; then
        printf "  \e[32m✓\e[0m %s Synced\n\n" "$fname"
        return 0
    else
        printf "  \e[31m✗\e[0m %s Failed (Exit Code: %d)\n\n" "$fname" "$rc"
        return 1
    fi
}

sync_files() {
    local ip="$1"
    local failed=0
    local succeeded=0
    local total_files=${#FILES_TO_SYNC[@]}

    printf "\n"
    printf "  \e[1m\e[35mRSYNC Files from Remote\e[0m\n"
    printf "  \e[2m────────────────────────────────────────────\e[0m\n"

    sudo -v

    for file in "${FILES_TO_SYNC[@]}"; do
        if sync_file "$ip" "$file"; then
            succeeded=$(( succeeded + 1 ))
        else
            failed=$(( failed + 1 ))
            break # Hentikan flow jika ada sync yang gagal/di-interrupt seperti python
        fi
    done

    printf "  \e[2m────────────────────────────────────────────\e[0m\n"

    if (( failed == 0 )); then
        return 0
    else
        return 1
    fi
}

# ─────────────────────────────────────────────────────────────
# UPDATE PROPERTIES
# ─────────────────────────────────────────────────────────────

update_properties() {
    local ip="$1"
    local unicode="$2"

    printf "\n  \e[35mUpdate Configuration\e[0m\n"
    printf "  \e[2m────────────────────────────────────────────\e[0m\n"

    python3 - "$ip" "$unicode" "$SERVER_PROPERTIES" << 'PYEOF'
import sys, re

ip, unicode, path = sys.argv[1], sys.argv[2], sys.argv[3]

SENSITIVE_KEYS = {
    "password", "username", "db", "credential.information",
    "minio.endpoint", "fisherman.host", "kafkaHost", "redisHost", "dbHost"
}

# Host merujuk ke lokasi yang dipilih
updates = {
    "serverHost": ip,
    "dbHost": ip,
    "wsHost": ip,
    "kafkaHost": ip,
    "redisHost": ip,
    "minio.endpoint": f"http://{ip}:9000",
    "fisherman.host": ip,
    "db": f"agent_{unicode}",
    "username": "agent",
    "password": f"{unicode}545115",
    "credential.information": "",
}

try:
    with open(path, "r") as f:
        lines = f.readlines()
except FileNotFoundError:
    lines = []

# Buat map dari config lama untuk display perbandingan
old_values = {}
config_dict = {}
for line in lines:
    if '=' in line and not line.strip().startswith('#'):
        k, v = line.split('=', 1)
        config_dict[k.strip()] = v.strip()

for k in updates:
    old_values[k] = config_dict.get(k, "(Not Found)")

# Tulis ulang konfigurasi
new_lines = []
updated_keys = set()

for line in lines:
    if '=' in line and not line.strip().startswith('#'):
        k, v = line.split('=', 1)
        key_clean = k.strip()
        if key_clean in updates:
            new_lines.append(f"{key_clean}={updates[key_clean]}\n")
            updated_keys.add(key_clean)
            continue
    new_lines.append(line)

# Jika ada key dari 'updates' yang belum ada di file asli, append ke paling bawah
for k, v in updates.items():
    if k not in updated_keys:
        new_lines.append(f"{k}={v}\n")

with open(path, "w") as f:
    f.writelines(new_lines)

print("\nConfiguration Changes")
print("FROM:")
for k in updates:
    if k in SENSITIVE_KEYS:
        continue
    print(f"  \e[31m{k:<25} = {old_values[k]}\e[0m")

print("\nTO:")
for k, v in updates.items():
    if k in SENSITIVE_KEYS:
        continue
    print(f"  \e[32m{k:<25} = {v}\e[0m")

print(f"\n  [INFO] {len(SENSITIVE_KEYS)} sensitive key(s) updated (hidden from display)")
PYEOF

    return $?
}

# ─────────────────────────────────────────────────────────────
# RUN AGENT
# ─────────────────────────────────────────────────────────────

run_agent() {
    local LOG_FILE="${LOG_DIR}/agent-$(date +%Y%m%d-%H%M%S).log"
    LATEST_LOG="$LOG_FILE"

    printf "\n  \e[35mStarting Parkee Agent\e[0m\n"
    printf "  \e[2m────────────────────────────────────────────\e[0m\n"

    if [[ ! -f "$JAVA_BIN" ]]; then
        err "Java binary not found: ${JAVA_BIN}"
        return 1
    fi

    local jar_path="${APP_DIR}/${JAR_NAME}"
    if [[ ! -f "$jar_path" ]]; then
        err "JAR not found: ${jar_path}"
        return 1
    fi

    if pgrep -f "$JAR_NAME" >/dev/null 2>&1; then
        warn "Killing existing agent instance..."
        pkill -f "$JAR_NAME" 2>/dev/null || true
        sleep 1
    fi

    info "Starting agent → log: ${LOG_FILE}"

    (
        cd "$APP_DIR" || exit 1
        export GDK_BACKEND=x11
        export _JAVA_AWT_WM_NONREPARENTING=1
        nohup "$JAVA_BIN" -Dprism.order=sw -jar "$JAR_NAME" > "$LOG_FILE" 2>&1 &
    )

    sleep 2

    if pgrep -f "$JAR_NAME" >/dev/null 2>&1; then
        ok "Agent process started (PID: $(pgrep -f "$JAR_NAME" | head -1))"
        return 0
    else
        err "Agent process not found after launch"
        err "Check log: ${LOG_FILE}"
        return 1
    fi
}

# ─────────────────────────────────────────────────────────────
# WAIT STARTUP
# ─────────────────────────────────────────────────────────────

wait_startup_log() {
    local LOG_FILE="$LATEST_LOG"
    local retries=60
    local i

    info "Waiting for agent startup (max ${retries}s)..."

    for (( i=1; i<=retries; i++ )); do
        if [[ ! -f "$LOG_FILE" ]]; then
            sleep 1
            continue
        fi

        if grep -Eq \
            "Started [A-Za-z]+Application|HikariPool.*Start completed|centerX\s*:|Application started" \
            "$LOG_FILE" 2>/dev/null; then
            sleep 2
            if pgrep -f "$JAR_NAME" >/dev/null 2>&1; then
                printf "\r\e[K"
                ok "Agent started successfully (${i}s)"
                return 0
            else
                printf "\r\e[K"
                err "Agent crashed after startup signal"
                grep -v "^\s*at " "$LOG_FILE" | tail -5 | sed 's/^/  /'
                return 1
            fi
        fi

        if grep -Eq "^.*Exception in thread|Address already in use|BUILD FAILED" "$LOG_FILE" 2>/dev/null \
            && ! grep -q "centerX\|HikariPool.*Start\|Started " "$LOG_FILE" 2>/dev/null; then
            printf "\r\e[K"
            err "Fatal error detected in agent log"
            grep -v "^\s*at \|Gdk-WARNING\|XSetErrorHandler\|^\s*$" "$LOG_FILE" \
                | grep -i "exception\|error\|failed\|denied" \
                | head -5 \
                | sed 's/^/  /'
            return 1
        fi

        printf "\r  \e[2mwaiting startup\e[0m  \e[36m%ds\e[0m\e[K" "$i"
        sleep 1
    done

    printf "\r\e[K"
    err "Startup timeout after ${retries}s — process $(pgrep -f "$JAR_NAME" >/dev/null && echo 'still running' || echo 'not found')"
    [[ -f "$LOG_FILE" ]] && grep -v "^\s*at " "$LOG_FILE" | tail -8 | sed 's/^/  /'
    return 1
}

# ─────────────────────────────────────────────────────────────
# DEPLOY FLOW
# ─────────────────────────────────────────────────────────────

deploy() {
    local ip="$1"
    local unicode="$2"
    local total=4
    local step=0

    (( step++ ))
    render_progress "$step" "$total" "Syncing files..."
    if ! sync_files "$ip"; then
        err "Sync files failed — deployment aborted"
        return 1
    fi

    (( step++ ))
    render_progress "$step" "$total" "Updating properties..."
    if ! update_properties "$ip" "$unicode"; then
        err "Update properties failed — deployment aborted"
        return 1
    fi

    (( step++ ))
    render_progress "$step" "$total" "Launching agent..."
    if ! run_agent; then
        err "Launch agent failed — deployment aborted"
        return 1
    fi

    (( step++ ))
    render_progress "$step" "$total" "Waiting startup..."
    if ! wait_startup_log; then
        err "Agent startup failed"
        return 1
    fi

    render_progress "$total" "$total" "Deployment complete!"
    printf "\n"

    line
    ok "Deployment Summary"
    info "Non-sensitive config applied:"
    grep -E "^(serverHost|wsHost|dbHost)=" "$SERVER_PROPERTIES" 2>/dev/null \
        | sed 's/^/  /' || true
    info "${#SENSITIVE_KEYS[@]} sensitive key(s) applied (hidden)"
    line

    return 0
}

# ─────────────────────────────────────────────────────────────
# MAIN MENU
# ─────────────────────────────────────────────────────────────

main_menu() {
    gum choose \
        --cursor.foreground "$PINK" \
        --selected.foreground "$PINK" \
        "Deploy Agent" \
        "Refresh Location Cache" \
        "Exit"
}

# ─────────────────────────────────────────────────────────────
# MAIN
# ─────────────────────────────────────────────────────────────

main() {
    check_dependencies
    show_header
    load_sheet
    detect_columns

    while true; do
        line
        OPTION=$(main_menu) || { warn "Menu cancelled"; continue; }

        case "$OPTION" in
            "Deploy Agent")
                RESULT=$(select_location) || { warn "Location selection cancelled"; continue; }
                [[ -z "$RESULT" ]] && continue

                IFS='§' read -r _DISPLAY UNICODE NAMA IP_MASKED IP <<< "$RESULT"

                if [[ -z "$IP" || "$IP" == "-" ]]; then
                    err "No valid IP for this location"
                    continue
                fi

                line
                gum style \
                    --border rounded \
                    --border-foreground "$PINK" \
                    --padding "0 2" \
"
UNICODE  : ${UNICODE}
LOCATION : ${NAMA}
IP       : ${IP_MASKED}
"
                show_stats "$IP"
                check_versions "$IP"
                printf "\n"

                if gum confirm "Deploy to Local using data from ${NAMA}?"; then
                    if deploy "$IP" "$UNICODE"; then
                        gum style \
                            --border double \
                            --border-foreground "$GREEN" \
                            --foreground "$GREEN" \
                            --align center \
                            --padding "1 4" \
                            "DEPLOYMENT SUCCESS

${NAMA}
${IP_MASKED}"
                    else
                        gum style \
                            --border double \
                            --border-foreground "$RED" \
                            --foreground "$RED" \
                            --align center \
                            --padding "1 4" \
                            "DEPLOYMENT FAILED

CHECK LOG: ${LATEST_LOG}"
                    fi
                else
                    warn "Deployment cancelled"
                fi
                ;;

            "Refresh Location Cache")
                rm -f "$CACHE_FILE"
                load_sheet
                detect_columns
                ok "Cache refreshed"
                ;;

            "Exit")
                printf "\n"
                gum style --foreground "$PINK" "Disconnecting..."
                exit 0
                ;;

            *)
                warn "Unknown option: ${OPTION}"
                ;;
        esac
    done
}

main "$@"
