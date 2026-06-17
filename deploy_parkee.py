#!/usr/bin/env python3
"""
deploy_parkee.py
Parkee Agent Deployment Tool
UI: rich + questionary + iterfzf  |  Logic: merged from py_deploy by Mas Michael Martoyo + gum.sh
"""

import csv
import os
import signal
import subprocess
import sys
import threading
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

import questionary
import requests
from iterfzf import iterfzf
from questionary import Style as QStyle
from rich import print as rprint
from rich.align import Align
from rich.columns import Columns
from rich.console import Console
from rich.live import Live
from rich.panel import Panel
from rich.progress import BarColumn, Progress, TextColumn, TimeElapsedColumn
from rich.prompt import Confirm
from rich.rule import Rule
from rich.style import Style
from rich.table import Table
from rich.text import Text

# ─────────────────────────────────────────────────────────────
# CONFIG
# ─────────────────────────────────────────────────────────────

SPREADSHEET_ID = "1A0ce374Dgw3pS4w05Yw9y1flJK5pZi6D-UUII6PG5VM"
SHEET_GID = "463772829"
CSV_URL = (
    f"https://docs.google.com/spreadsheets/d/{SPREADSHEET_ID}/export"
    f"?format=csv&gid={SHEET_GID}"
)

SSH_USER = os.environ.get("PARKEE_SSH_USER", "support")
SSH_PASS = os.environ.get("PARKEE_SSH_PASS", "REMOVED_PASSWORD")
SSH_TIMEOUT = 10
ACTUATOR_TIMEOUT = 5

APP_DIR = "/opt/app/agent/parkee-agent"
SERVER_PROPS = f"{APP_DIR}/server.properties"
JAVA_BIN = "/usr/lib/jvm/bellsoft-java15-full-amd64/bin/java"
JAR_NAME = "parkee-agent-production.jar"
AGENT_JAR_PATH = "/mnt/shared/production/parkee-agent-production.jar"

REMOTE_PROPS_PATH = f"{APP_DIR}/server.properties"

FILES_TO_SYNC = [
    "/mnt/shared/production/parkee-agent-production.jar",
    "/mnt/shared/sound",
    "/mnt/shared/dependencies",
]

CACHE_DIR = Path.home() / ".cache" / "parkee"
CACHE_FILE = CACHE_DIR / "master_loc.csv"
CACHE_TTL = 3600  # 1 jam

LOG_DIR = Path.home() / "logs" / "parkee"

SENSITIVE_KEYS = {
    "password",
    "username",
    "db",
    "credential.information",
    "minio.endpoint",
    "fisherman.host",
    "kafkaHost",
    "redisHost",
    "dbHost",
}

SSH_OPTS = (
    f"-o StrictHostKeyChecking=no -o LogLevel=ERROR -o ConnectTimeout={SSH_TIMEOUT}"
)

# JVM flags — full GPU + OpenGL
JVM_FLAGS = [
    "-Dprism.order=d3d,es2,es1,sw,j2d",
    "-Dsun.java2d.opengl=true",
    "-Dprism.vsync=false",
    "-Dprism.forceGPU=true",
]

DEPS_REQUIRED = ["sshpass", "rsync", "unzip", "fzf", "ping", "curl"]

# ─────────────────────────────────────────────────────────────
# CONSOLE & THEME
# ─────────────────────────────────────────────────────────────

console = Console()

PARKEE_STYLE = QStyle(
    [
        ("qmark", "fg:#ff00ff bold"),
        ("question", "fg:#ffffff bold"),
        ("answer", "fg:#00ff87 bold"),
        ("pointer", "fg:#ff00ff bold"),
        ("highlighted", "fg:#ff00ff bold"),
        ("selected", "fg:#00ff87"),
        ("separator", "fg:#444444"),
        ("instruction", "fg:#888888"),
        ("text", "fg:#ffffff"),
    ]
)

PINK = "bright_magenta"
CYAN = "cyan"
GREEN = "bright_green"
RED = "bright_red"
YELLOW = "yellow"
PURPLE = "medium_purple1"
GREY = "grey50"

# ─────────────────────────────────────────────────────────────
# INIT DIRS
# ─────────────────────────────────────────────────────────────

CACHE_DIR.mkdir(parents=True, exist_ok=True)
LOG_DIR.mkdir(parents=True, exist_ok=True)

# ─────────────────────────────────────────────────────────────
# UI HELPERS
# ─────────────────────────────────────────────────────────────


def ok(msg: str):
    console.print(f"[{GREEN}]✔[/] {msg}")


def err(msg: str):
    console.print(f"[{RED}]✘[/] {msg}")


def warn(msg: str):
    console.print(f"[{YELLOW}]⚠[/] {msg}")


def info(msg: str):
    console.print(f"[{CYAN}]ℹ[/] {msg}")


def line():
    console.print(Rule(style=GREY))


def mask_ip(ip: str) -> str:
    parts = ip.split(".")
    if len(parts) == 4:
        return f"{parts[0]}.{parts[1]}.{parts[2]}.*"
    return "***"


def normalize(s: str) -> str:
    return str(s).strip().lower()


def pad_unicode(raw: str) -> str:
    s = raw.strip().lower()
    if len(s) < 3:
        return s.zfill(3)
    return s


# ─────────────────────────────────────────────────────────────
# HEADER
# ─────────────────────────────────────────────────────────────

ASCII_ART = """
██████╗  █████╗ ██████╗ ██╗  ██╗███████╗███████╗
██╔══██╗██╔══██╗██╔══██╗██║ ██╔╝██╔════╝██╔════╝
██████╔╝███████║██████╔╝█████╔╝ █████╗  █████╗
██╔═══╝ ██╔══██║██╔══██╗██╔═██╗ ██╔══╝  ██╔══╝
██║     ██║  ██║██║  ██╗██║  ██╗███████╗███████╗
╚═╝     ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝╚══════╝╚══════╝

EL TEMBAK AGENT
"""


def show_header():
    os.system("clear")
    art = Text(ASCII_ART, style=f"bold {PINK}", justify="center")
    panel = Panel(
        Align.center(art),
        border_style=PINK,
        padding=(0, 4),
    )
    console.print(panel)
    console.print()


# ─────────────────────────────────────────────────────────────
# DEPENDENCY CHECK
# ─────────────────────────────────────────────────────────────


def check_dependencies():
    missing = [
        d
        for d in DEPS_REQUIRED
        if subprocess.run(["which", d], capture_output=True).returncode != 0
    ]

    if missing:
        err(f"Missing dependencies: {', '.join(missing)}")
        err("Install depend nya dulu bre hehe")
        sys.exit(1)

    app_path = Path(APP_DIR)
    if not app_path.exists():
        info(f"Creating app directory: {APP_DIR}")
        subprocess.run(["sudo", "mkdir", "-p", APP_DIR], check=True)

    info("Validating sudo privilege...")
    subprocess.run(["sudo", "-v"], check=True)
    subprocess.run(
        ["sudo", "chown", "-R", f"{os.getenv('USER')}:{os.getenv('USER')}", APP_DIR],
        check=True,
    )
    ok("Dependencies AMAN!")


# ─────────────────────────────────────────────────────────────
# LOAD SHEET + CACHE
# ─────────────────────────────────────────────────────────────


def load_sheet(force_refresh: bool = False) -> list[dict]:
    """
    Load CSV dari Google Sheet dengan cache TTL 1 jam.
    Return list of row dicts dengan unicode di-pad 3 digit.
    """
    if not force_refresh and CACHE_FILE.exists():
        age = time.time() - CACHE_FILE.stat().st_mtime
        if age < CACHE_TTL:
            remaining = int((CACHE_TTL - age) / 60)
            ok(f"Using cached location data ({remaining}m remaining)")
            return _parse_csv(CACHE_FILE)

    with console.status("[cyan]Fetching Google Sheet...[/]", spinner="dots"):
        try:
            r = requests.get(CSV_URL, timeout=15)
            r.raise_for_status()
            CACHE_FILE.write_text(r.text, encoding="utf-8")
            ok("Location data updated")
        except Exception as e:
            if CACHE_FILE.exists():
                warn(f"Fetch failed ({e}), using stale cache as fallback")
            else:
                err(f"Failed to fetch Google Sheet: {e}")
                sys.exit(1)

    return _parse_csv(CACHE_FILE)


def _parse_csv(path: Path) -> list[dict]:
    """Parse CSV dengan normalisasi unicode super ketat."""
    rows = []
    with open(path, newline="", encoding="utf-8-sig") as f:
        reader = csv.DictReader(f)
        if reader.fieldnames is None:
            err("CSV kosong atau headers ga ketemu")
            sys.exit(1)

        header_map = {h.strip().lower(): h for h in reader.fieldnames}
        col_unicode = _find_col(header_map, ["unicode"])
        col_nama = _find_col(header_map, ["nama lokasi - unicode", "nama lokasi"])
        col_ip = _find_col(header_map, ["ip zt", "ip"])

        if not all([col_unicode, col_nama, col_ip]):
            err(
                f"Kolom ga ketemu — unicode={col_unicode}, nama={col_nama}, ip={col_ip}"
            )
            sys.exit(1)

        for row in reader:
            raw_uni = row.get(col_unicode, "").strip()
            nama = row.get(col_nama, "").strip()
            ip = row.get(col_ip, "").strip()

            if not ip or not raw_uni:
                continue

            # Paksa lowercase & 3 digit di sini, bre
            uni_padded = pad_unicode(raw_uni)

            rows.append(
                {
                    "unicode": uni_padded,
                    "unicode_raw": raw_uni,
                    "nama": nama,
                    "ip": ip,
                    "ip_masked": mask_ip(ip),
                }
            )
    return rows


def _find_col(header_map: dict, candidates: list[str]) -> str | None:
    for c in candidates:
        if c in header_map:
            return header_map[c]
    return None


# ─────────────────────────────────────────────────────────────
# LOCATION SELECTOR — FZF FUZZY
# ─────────────────────────────────────────────────────────────


def select_location(rows: list[dict]) -> dict | None:
    HEADER = f"{'UNICODE':<10}| {'LOCATION NAME':<65}| {'IP (MASKED)':<20}"

    lines = []
    row_map: dict[str, dict] = {}

    for r in rows:
        uni = r["unicode"].strip().lower()
        nama = r["nama"][:65].ljust(65)
        masked = r["ip_masked"].ljust(20)

        display_line = f"{uni:<10}| {nama}| {masked}"

        lines.append(display_line)
        row_map[uni] = r

    console.print(
        f"\n[{PINK}]  Search lokasi (Ketik Unicode atau Nama Lokasi nyah):[/]"
    )

    result = iterfzf(
        lines,
        multi=False,
        ansi=True,
        __extra__=[
            "--height=85%",
            "--border",
            "--layout=reverse",
            "--info=inline",
            # separator kolom
            "--delimiter=|",
            # search unicode + nama lokasi
            "--nth=1,2",
            # tampilkan semua kolom
            "--with-nth=1,2,3",
            "--prompt=SEARCH > ",
            f"--header={HEADER}",
            "--tiebreak=begin,length",
        ],
    )

    if not result:
        return None

    try:
        selected_uni = result.split("|", 1)[0].strip().lower()

        selected_row = row_map.get(selected_uni)

        if selected_row:
            return selected_row

        err(f"Data lokasi dengan unicode '{selected_uni}' ga ketemu di master data")
        return None

    except Exception as e:
        err(f"Gagal parsing hasil fuzzy nya nih men: {e}")
        return None


# ─────────────────────────────────────────────────────────────
# VERSION CHECK — concurrent
# ─────────────────────────────────────────────────────────────


def _fetch_agent_version(ip: str) -> str:
    cmd = [
        "sshpass",
        "-p",
        SSH_PASS,
        "ssh",
        "-o",
        "StrictHostKeyChecking=no",
        "-o",
        "LogLevel=ERROR",
        "-o",
        f"ConnectTimeout={SSH_TIMEOUT}",
        f"{SSH_USER}@{ip}",
        f"unzip -p '{AGENT_JAR_PATH}' META-INF/MANIFEST.MF 2>/dev/null "
        f"| grep 'Implementation-Version' | cut -d: -f2 | tr -d ' \\r'",
    ]
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=SSH_TIMEOUT)
        return r.stdout.strip() or "-"
    except Exception:
        return "-"


def _fetch_actuator_version(ip: str, port: int) -> str:
    try:
        r = requests.get(f"http://{ip}:{port}/actuator/info", timeout=ACTUATOR_TIMEOUT)
        r.raise_for_status()
        return r.json()["build"]["version"]
    except Exception:
        return "-"


def check_versions(ip: str) -> tuple[str, str, str]:
    """Concurrent version check — agent + WS + FS parallel."""
    info("Checking versions (concurrent)...")

    with ThreadPoolExecutor(max_workers=3) as ex:
        fut_agent = ex.submit(_fetch_agent_version, ip)
        fut_ws = ex.submit(_fetch_actuator_version, ip, 9005)
        fut_fs = ex.submit(_fetch_actuator_version, ip, 8888)

        agent_ver = fut_agent.result()
        ws_ver = fut_ws.result()
        fs_ver = fut_fs.result()

    ver_table = Table(show_header=False, box=None, padding=(0, 1))
    ver_table.add_column(style=GREY)
    ver_table.add_column(style=YELLOW)
    ver_table.add_row("AGENT :", agent_ver)
    ver_table.add_row("WS    :", ws_ver)
    ver_table.add_row("FS    :", fs_ver)

    console.print(Panel(ver_table, border_style=CYAN, padding=(0, 2)))

    return agent_ver, ws_ver, fs_ver


# ─────────────────────────────────────────────────────────────
# PING / STATS
# ─────────────────────────────────────────────────────────────


def show_stats(ip: str, ip_masked: str):
    try:
        r = subprocess.run(
            ["ping", "-c", "1", "-W", "1", ip], capture_output=True, text=True
        )
        if "time=" in r.stdout:
            ping_ms = r.stdout.split("time=")[1].split()[0]
        else:
            ping_ms = "OFFLINE"
    except Exception:
        ping_ms = "OFFLINE"

    stats_table = Table(show_header=False, box=None, padding=(0, 1))
    stats_table.add_column(style=GREY)
    stats_table.add_column(style="white")
    stats_table.add_row("IP (masked) :", ip_masked)
    stats_table.add_row(
        "PING        :", f"{ping_ms} ms" if ping_ms != "OFFLINE" else "[red]OFFLINE[/]"
    )
    stats_table.add_row("SSH USER    :", SSH_USER)

    console.print(
        Panel(stats_table, title="TARGET STATUS", border_style=PURPLE, padding=(0, 2))
    )


# ─────────────────────────────────────────────────────────────
# RSYNC
# ─────────────────────────────────────────────────────────────


def sync_files(ip: str) -> bool:
    console.print(f"\n[bold {PINK}]  RSYNC Files from Remote[/]")
    console.print(Rule(style=GREY))

    subprocess.run(["sudo", "-v"], check=True)

    all_ok = True
    for file_path in FILES_TO_SYNC:
        fname = os.path.basename(file_path)
        info(f"Syncing: [bold]{fname}[/]")

        cmd = [
            "sudo",
            "sshpass",
            "-p",
            SSH_PASS,
            "rsync",
            "-az",
            "--info=progress2",
            "-e",
            f"ssh {SSH_OPTS}",
            f"{SSH_USER}@{ip}:{file_path}",
            f"{APP_DIR}/",
        ]

        rc = subprocess.call(cmd)
        if rc == 0:
            ok(f"{fname} synced")
        else:
            err(f"{fname} failed (exit code: {rc})")
            all_ok = False
            break

    return all_ok


# ─────────────────────────────────────────────────────────────
# UPDATE PROPERTIES
# ─────────────────────────────────────────────────────────────


def pull_remote_properties(ip: str) -> bool:
    """
    Pull server.properties dari remote via SSH → simpan ke local SERVER_PROPS.
    Ini jadi base config — semua key lokasi-spesifik (port, ftp, minio, qiqo, dll)
    langsung dari source of truth remote, bukan hardcoded.
    """
    console.print(f"\n[bold {PINK}]  Pull server.properties from Remote[/]")
    console.print(Rule(style=GREY))

    props_path = Path(SERVER_PROPS)
    props_path.parent.mkdir(parents=True, exist_ok=True)

    cmd = [
        "sshpass",
        "-p",
        SSH_PASS,
        "scp",
        "-o",
        "StrictHostKeyChecking=no",
        "-o",
        "LogLevel=ERROR",
        "-o",
        f"ConnectTimeout={SSH_TIMEOUT}",
        f"{SSH_USER}@{ip}:{REMOTE_PROPS_PATH}",
        str(props_path),
    ]

    with console.status("[cyan]Pulling server.properties...[/]", spinner="dots"):
        result = subprocess.run(cmd, capture_output=True, text=True)

    if result.returncode != 0:
        err(f"Failed to pull server.properties from {ip}")
        err(f"SCP error: {result.stderr.strip()}")
        if props_path.exists():
            warn("Using existing local server.properties as fallback")
            warn("Value nya ga sesuai nih men")
            return True  # bisa lanjut tapi ada warning awkawkawka
        else:
            err("Tidak ada fallback — gaada server.properties lokal")
            return False

    ok(f"server.properties pulled from {ip}")

    # Sanity check — mastiin file ga kosong
    if props_path.stat().st_size == 0:
        err("server.properties yang di-pull kosong — sesuatu ga beres nih men")
        return False

    pulled = _parse_properties(props_path)
    info(f"Pulled {len(pulled)} key(s) from remote")
    return True


def _parse_properties(path: Path) -> dict[str, str]:
    """Parse server.properties jadi dict, skip comments dan blank lines."""
    result = {}
    if not path.exists():
        return result
    for line in path.read_text(encoding="utf-8").splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        if "=" in stripped:
            k, _, v = stripped.partition("=")
            result[k.strip()] = v.strip()
    return result


def verify_properties(updates: dict[str, str]) -> tuple[bool, list[str]]:
    """
    Baca ulang server.properties setelah write dan verifikasi
    semua key yang di-update udah beneran ke-write dengan value yang bener.
    Return (all_ok, list_of_failed_keys)
    """
    actual = _parse_properties(Path(SERVER_PROPS))
    failed = []
    for k, expected_v in updates.items():
        actual_v = actual.get(k)
        if actual_v != expected_v:
            failed.append(k)
    return (len(failed) == 0), failed


def update_properties(ip: str, unicode_code: str) -> bool:
    """
    Override key-key yang perlu diganti untuk deploy lokal,
    di atas base config yang udah di-pull dari remote.
    Key lain (port, ftp, minio creds, qiqo, dll) dibiarkan dari remote.
    """
    console.print(f"\n[bold {PINK}]  Override Local Config[/]")
    console.print(Rule(style=GREY))

    # Hanya key yang perlu di-override untuk lokal
    # Semua key lain (dbPort, ftp.*, minio.accesskey, qiqo.*, dll)
    # sudah ada dari pull_remote_properties — jangan di-touch
    updates = {
        "serverHost": ip,
        "dbHost": ip,
        "wsHost": ip,
        "kafkaHost": ip,
        "redisHost": ip,
        "minio.endpoint": f"http://{ip}:9000",
        "fisherman.host": ip,
        "db": f"agent_{unicode_code}",
        "username": "agent",
        "password": f"{unicode_code}545115",
        "credential.information": "",  # ini kosong kan buat lokal yak? bener ga gue akwakwka
    }

    props_path = Path(SERVER_PROPS)

    # File harus ada dari pull_remote_properties
    try:
        raw_lines = props_path.read_text(encoding="utf-8").splitlines(keepends=True)
    except FileNotFoundError:
        err(f"server.properties gaada lagi di {SERVER_PROPS}")
        err("Pastiin pull_remote_properties berhasil sebelum update_properties")
        return False

    # Build old config map untuk display diff
    old_values: dict[str, str] = {}
    config_dict = _parse_properties(props_path)
    for k in updates:
        old_values[k] = config_dict.get(k, "(Not Found)")

    # Rewrite — iterate raw lines, replace key yang match
    # Pake partition pada stripped line tapi NULIS tanpa leading/trailing space
    # supaya format konsisten ini yang kemarin bug akwakwka
    new_lines = []
    updated_keys: set[str] = set()

    for raw_line in raw_lines:
        stripped = raw_line.strip()
        if stripped and not stripped.startswith("#") and "=" in stripped:
            k, _, _ = stripped.partition("=")
            key = k.strip()
            if key in updates:
                # Ngewrite clean tanpa extra whitespace
                new_lines.append(f"{key}={updates[key]}\n")
                updated_keys.add(key)
                continue
        # Preserve line asli (termasuk blank lines dan comments biar asik)
        new_lines.append(raw_line if raw_line.endswith("\n") else raw_line + "\n")

    # Kalo misal belom ada, langsung append keys yang sama sekali belum ada di file
    for k, v in updates.items():
        if k not in updated_keys:
            new_lines.append(f"{k}={v}\n")

    # Writinnggg
    try:
        props_path.write_text("".join(new_lines), encoding="utf-8")
    except PermissionError:
        err(f"Waduh permission denied writing to {SERVER_PROPS}")
        err("Coba jalanin: sudo chown $(whoami) " + SERVER_PROPS)
        return False
    except Exception as e:
        err(f"Gagal nih men writing server.properties: {e}")
        return False

    # ── POST-WRITE VERIFICATION ──
    all_ok, failed_keys = verify_properties(updates)
    if not all_ok:
        err(f"Properties verification FAILED — key itu ga ke-write dengan bener:")
        for fk in failed_keys:
            actual_val = _parse_properties(props_path).get(fk, "(missing)")
            expected_val = updates[fk]
            if fk in SENSITIVE_KEYS:
                console.print(f"  [{RED}]{fk}[/] → expected [hidden], got [hidden]")
            else:
                console.print(
                    f"  [{RED}]{fk}[/] → expected [{GREEN}]{expected_val}[/], got [{RED}]{actual_val}[/]"
                )
        err("Deployment aborted — fix server.properties permissions atau path dulu")
        return False

    ok("server.properties verified OK")

    # Display diff — hide sensitive keys buat regulasi
    diff_table = Table(
        show_header=True, header_style=f"bold {YELLOW}", box=None, padding=(0, 2)
    )
    diff_table.add_column("KEY", style=GREY, width=28)
    diff_table.add_column("FROM", style=RED)
    diff_table.add_column("TO", style=GREEN)

    for k, new_v in updates.items():
        if k in SENSITIVE_KEYS:
            diff_table.add_row(k, "***", "***")
        else:
            diff_table.add_row(k, old_values.get(k, "(Not Found)"), new_v)

    console.print(
        Panel(
            diff_table,
            title="Configuration Changes",
            border_style=YELLOW,
            padding=(0, 1),
        )
    )
    info(f"{len(SENSITIVE_KEYS)} sensitive key(s) updated (hidden from display)")

    return True


# ─────────────────────────────────────────────────────────────
# RUN AGENT — full JVM flags + background nohup + logging
# ─────────────────────────────────────────────────────────────


def run_agent() -> tuple[bool, Path]:
    log_file = LOG_DIR / f"agent-{time.strftime('%Y%m%d-%H%M%S')}.log"

    console.print(f"\n[bold {PINK}]  Starting Parkee Agent[/]")
    console.print(Rule(style=GREY))

    # Validasi binary
    if not Path(JAVA_BIN).exists():
        err(f"Java binary not found: {JAVA_BIN}")
        return False, log_file

    jar_path = Path(APP_DIR) / JAR_NAME
    if not jar_path.exists():
        err(f"JAR not found: {jar_path}")
        return False, log_file

    # Kill existing — targeted by JAR name
    result = subprocess.run(["pgrep", "-f", JAR_NAME], capture_output=True, text=True)
    if result.returncode == 0:
        warn("Killing existing agent instance...")
        subprocess.run(["pkill", "-f", JAR_NAME], capture_output=True)
        time.sleep(1)

    info(f"Starting agent → log: {log_file}")

    # Launch background process dengan full JVM flags
    env = os.environ.copy()
    env["GDK_BACKEND"] = "x11"
    env["_JAVA_AWT_WM_NONREPARENTING"] = "1"

    cmd = (
        f"cd {APP_DIR} && nohup {JAVA_BIN} "
        + " ".join(JVM_FLAGS)
        + f" -jar {JAR_NAME} > {log_file} 2>&1 &"
    )

    subprocess.Popen(
        cmd,
        shell=True,
        executable="/bin/bash",
        env=env,
        start_new_session=True,
    )

    time.sleep(2)

    # Verify process jalan
    check = subprocess.run(["pgrep", "-f", JAR_NAME], capture_output=True, text=True)
    if check.returncode == 0:
        pid = check.stdout.strip().split("\n")[0]
        ok(f"Agent process gasak di (PID: {pid})")
        return True, log_file
    else:
        err("Agent process not found after launch")
        err(f"Check log: {log_file}")
        return False, log_file


# ─────────────────────────────────────────────────────────────
# WAIT STARTUP — monitor log file
# ─────────────────────────────────────────────────────────────

STARTUP_OK_PATTERNS = [
    "Started [A-Za-z]+Application",
    r"HikariPool.*Start completed",
    "centerX\\s*:",
    "Application started",
    # Agent udah boot, DB belum konek — tetep valid startup signal dengan suatu kondisi tapi
    "Failed Connecting to Database, retrying",
    "SplashPreloader",
    "JavaFX Application Thread",
]

FATAL_PATTERNS = [
    "Exception in thread",
    "Address already in use",
    "BUILD FAILED",
]


def wait_startup_log(log_file: Path, timeout: int = 60) -> bool:
    import re

    from rich.live import Live
    from rich.spinner import Spinner

    info(f"Tunggu agent startup men, bentar (max {timeout}s)...")

    ok_re = re.compile("|".join(STARTUP_OK_PATTERNS))
    fatal_re = re.compile("|".join(FATAL_PATTERNS))

    result_holder = {"status": None}

    def _monitor():
        for i in range(1, timeout + 1):
            if log_file.exists():
                try:
                    content = log_file.read_text(errors="replace")
                except Exception:
                    content = ""

                if ok_re.search(content):
                    time.sleep(2)
                    check = subprocess.run(
                        ["pgrep", "-f", JAR_NAME], capture_output=True, text=True
                    )
                    if check.returncode == 0:
                        result_holder["status"] = ("ok", i)
                    else:
                        result_holder["status"] = ("crashed", i)
                    return

                if fatal_re.search(content) and not ok_re.search(content):
                    result_holder["status"] = ("fatal", i)
                    return

            time.sleep(1)

        result_holder["status"] = ("timeout", timeout)

    monitor_thread = threading.Thread(target=_monitor, daemon=True)
    monitor_thread.start()

    # Rich Live spinner yang better daripada per detik info
    with Live(console=console, refresh_per_second=4, transient=True) as live:
        i = 0
        while monitor_thread.is_alive():
            i += 1
            live.update(Text(f"  ⏳ waiting startup  {i}s", style=GREY))
            time.sleep(0.25)
        monitor_thread.join()

    # Handle result
    status_val = result_holder["status"]

    if status_val is None:
        status_val = ("timeout", timeout)

    kind, elapsed = status_val

    if kind == "ok":
        ok(f"GASAK MEN! ({elapsed}s)")
        return True
    elif kind == "crashed":
        err("Agent crashed after startup signal")
        _tail_log(log_file, lines=5)
        return False
    elif kind == "fatal":
        err("Fatal error detected in agent log")
        _tail_log(log_file, lines=5)
        return False
    else:
        still_running = (
            subprocess.run(["pgrep", "-f", JAR_NAME], capture_output=True).returncode
            == 0
        )
        status_str = "still running" if still_running else "not found"
        err(f"Startup timeout after {timeout}s — process {status_str}")
        if log_file.exists():
            _tail_log(log_file, lines=8)
        return False


def _tail_log(log_file: Path, lines: int = 5):
    content = log_file.read_text(errors="replace").splitlines()
    filtered = [
        l
        for l in content
        if not l.strip().startswith("at ") and l.strip() and "Gdk-WARNING" not in l
    ]
    tail = filtered[-lines:]
    console.print(f"\n[{GREY}]  --- last {lines} log lines ---[/]")
    for l in tail:
        console.print(f"  [{GREY}]{l}[/]")


# ─────────────────────────────────────────────────────────────
# DEPLOY FLOW — dengan progress bar
# ─────────────────────────────────────────────────────────────

LATEST_LOG: Path | None = None


def deploy(ip: str, unicode_code: str, nama: str) -> bool:
    global LATEST_LOG

    total = 5

    # Step 1: Sync files
    console.print(f"\n[{GREY}][1/{total}][/] Syncing files...")
    if not sync_files(ip):
        err("Yah sync files gagal men, gagal nembak nich")
        return False

    # Step 2: Pull server.properties dari remote (base config)
    console.print(f"\n[{GREY}][2/{total}][/] Pulling remote config...")
    if not pull_remote_properties(ip):
        err("Yah pull remote juga gagal men, gagal nembak nich")
        return False

    # Step 3: Override key lokal di atas base remote config
    console.print(f"\n[{GREY}][3/{total}][/] Overriding local config...")
    if not update_properties(ip, unicode_code):
        err("Yah update properties juga gagal nich men, gagal nembak juga nich")
        return False

    # Step 4: Run agent
    console.print(f"\n[{GREY}][4/{total}][/] Launching agent...")
    launched, log_file = run_agent()
    LATEST_LOG = log_file
    if not launched:
        err("Sorry men, gagal nembak agent :(")
        return False

    # Step 5: Wait startup
    console.print(f"\n[{GREY}][5/{total}][/] Waiting startup...")
    if not wait_startup_log(log_file):
        err("Agent startup failed")
        return False

    return True


# ─────────────────────────────────────────────────────────────
# LOCATION INFO PANEL
# ─────────────────────────────────────────────────────────────


def show_location_panel(loc: dict):
    loc_table = Table(show_header=False, box=None, padding=(0, 1))
    loc_table.add_column(style=GREY)
    loc_table.add_column(style="white")
    loc_table.add_row("UNICODE  :", loc["unicode"])
    loc_table.add_row("LOCATION :", loc["nama"])
    loc_table.add_row("IP       :", loc["ip_masked"])

    console.print(
        Panel(
            loc_table,
            border_style=PINK,
            padding=(0, 2),
        )
    )


# ─────────────────────────────────────────────────────────────
# MAIN MENU
# ─────────────────────────────────────────────────────────────


def main_menu() -> str | None:
    return questionary.select(
        "Main Menu",
        choices=[
            "Tembak Agent",
            "Refresh Location Cache",
            "Exit",
        ],
        style=PARKEE_STYLE,
        use_shortcuts=False,
    ).ask()


# ─────────────────────────────────────────────────────────────
# MAIN
# ─────────────────────────────────────────────────────────────


def main():
    def _sigint(sig, frame):
        console.print(f"\n\n[{PINK}]  Disconnecting...[/]\n")
        sys.exit(0)

    signal.signal(signal.SIGINT, _sigint)

    check_dependencies()
    show_header()

    rows = load_sheet()

    while True:
        line()
        option = main_menu()

        if option is None or option == "Exit":
            console.print(f"\n[{PINK}]  Disconnecting...[/]\n")
            break

        elif option == "Tembak Agent":
            loc = select_location(rows)
            if not loc:
                warn("Pilih lokasi dibatalin")
                continue

            if not loc["ip"] or loc["ip"] == "-":
                err("IP Loc ini ga valid men")
                continue

            line()
            show_location_panel(loc)
            show_stats(loc["ip"], loc["ip_masked"])
            check_versions(loc["ip"])
            console.print()

            confirmed = questionary.confirm(
                f"Gasak tembak agent ke {loc['nama']}?",
                style=PARKEE_STYLE,
                default=False,
            ).ask()

            if not confirmed:
                warn("Nembak agent dibatalin")
                continue

            success = deploy(loc["ip"], loc["unicode"], loc["nama"])

            if success:
                result_text = Text(justify="center")
                result_text.append("NEMBAK AGENT SUCCESS\n\n", style=f"bold {GREEN}")
                result_text.append(f"{loc['nama']}\n", style="white")
                result_text.append(loc["ip_masked"], style=GREY)
                console.print(
                    Panel(
                        Align.center(result_text),
                        border_style=GREEN,
                        padding=(1, 4),
                    )
                )
                # Print non-sensitive applied config
                console.print(f"\n[{GREY}]Applied config:[/]")
                for key in ["serverHost", "wsHost"]:
                    console.print(f"  [{GREY}]{key}[/] = [{GREEN}]{loc['ip']}[/]")
                info(f"{len(SENSITIVE_KEYS)} sensitive key(s) applied (hidden)")
                if LATEST_LOG:
                    info(f"Log: {LATEST_LOG}")
            else:
                result_text = Text(justify="center")
                result_text.append("NEMBAK AGENT GAGAL\n\n", style=f"bold {RED}")
                if LATEST_LOG:
                    result_text.append(f"CHECK LOG: {LATEST_LOG}", style=GREY)
                console.print(
                    Panel(
                        Align.center(result_text),
                        border_style=RED,
                        padding=(1, 4),
                    )
                )

        elif option == "Refresh Location Cache":
            CACHE_FILE.unlink(missing_ok=True)
            rows = load_sheet(force_refresh=True)
            ok("Cache refreshed")


if __name__ == "__main__":
    main()
