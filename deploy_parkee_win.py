#!/usr/bin/env python3
"""
deploy_parkee_win.py
Parkee Agent Deployment Tool untuk Windows
Menggunakan Paramiko + SCP instead of subprocess rsync/sshpass
UI: rich + questionary + iterfzf  |  Logic: adaptation dari deploy_parkee.py
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
# AUTO-INSTALL DEPENDENCIES
# ─────────────────────────────────────────────────────────────
def check_and_install_packages():
    """Cek dan install package otomatis jika belum ada"""
    packages = {
        "paramiko": "paramiko",
        "scp": "scp",
        "requests": "requests",
        "questionary": "questionary",
        "iterfzf": "iterfzf",
        "rich": "rich",
    }
    for module, pip_name in packages.items():
        try:
            __import__(module)
        except ImportError:
            print(f"[*] Modul '{module}' belum ada. Menginstal '{pip_name}'...")
            try:
                subprocess.check_call(
                    [sys.executable, "-m", "pip", "install", pip_name]
                )
                print(f"[*] Berhasil menginstal {pip_name}!\n")
            except subprocess.CalledProcessError:
                print(
                    f"[!] Gagal menginstal {pip_name}. Silakan install manual: pip install {pip_name}"
                )
                sys.exit(1)


check_and_install_packages()

import paramiko
from scp import SCPClient

# ─────────────────────────────────────────────────────────────
# CONFIG
# ─────────────────────────────────────────────────────────────

SPREADSHEET_ID = os.environ.get("GSHEET_DEPLOY_ID", "")
SHEET_GID = os.environ.get("GSHEET_DEPLOY_GID", "")
CSV_URL = (
    f"https://docs.google.com/spreadsheets/d/{SPREADSHEET_ID}/export"
    f"?format=csv&gid={SHEET_GID}"
)

SSH_USER = os.environ.get("PARKEE_SSH_USER")
SSH_PASS = os.environ.get("PARKEE_SSH_PASS")
SSH_TIMEOUT = 15
ACTUATOR_TIMEOUT = 10

# Environment Variable Validation (seperti settlement_rfs.py pattern)
if not all([SSH_USER, SSH_PASS, SPREADSHEET_ID, SHEET_GID]):
    required = []
    if not SSH_USER:
        required.append("PARKEE_SSH_USER")
    if not SSH_PASS:
        required.append("PARKEE_SSH_PASS")
    if not SPREADSHEET_ID:
        required.append("GSHEET_DEPLOY_ID")
    if not SHEET_GID:
        required.append("GSHEET_DEPLOY_GID")

    print(
        f"\n[!] Error: Environment variable(s) belum di-set: {', '.join(required)}"
    )
    print("[!] Silakan set di .env atau jalankan via GASAK\n")
    sys.exit(1)

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
CACHE_TTL = 3600

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

# JVM flags — full GPU + OpenGL
JVM_FLAGS = [
    "-Dprism.order=d3d,es2,es1,sw,j2d",
    "-Dsun.java2d.opengl=true",
    "-Dprism.vsync=false",
    "-Dprism.forceGPU=true",
]

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
██║     ██║  ██║██║  ██║██║  ██╗███████╗███████╗
╚═╝     ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝╚══════╝╚══════╝

EL TEMBAK AGENT (WINDOWS)
"""


def show_header():
    os.system("cls" if os.name == "nt" else "clear")
    art = Text(ASCII_ART, style=f"bold {PINK}", justify="center")
    panel = Panel(
        Align.center(art),
        border_style=PINK,
        padding=(0, 4),
    )
    console.print(panel)
    console.print()


# ─────────────────────────────────────────────────────────────
# SSH CONNECTION — PARAMIKO
# ─────────────────────────────────────────────────────────────


class SSHConnectionError(Exception):
    """Custom exception untuk SSH connection errors"""
    pass


def create_ssh_client(ip: str, username: str, password: str) -> paramiko.SSHClient:
    """
    Create SSH client dengan Paramiko.
    Raises SSHConnectionError jika gagal connect.
    """
    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())

    try:
        ssh.connect(
            ip,
            username=username,
            password=password,
            timeout=SSH_TIMEOUT,
            look_for_keys=False,
            allow_agent=False,
        )
        return ssh
    except paramiko.AuthenticationException as e:
        raise SSHConnectionError(f"Authentication failed for {ip}: {e}")
    except paramiko.SSHException as e:
        raise SSHConnectionError(f"SSH connection failed to {ip}: {e}")
    except Exception as e:
        raise SSHConnectionError(f"Connection error to {ip}: {e}")


def run_ssh_command(ssh: paramiko.SSHClient, command: str) -> tuple[str, str, int]:
    """
    Run command via SSH dan return stdout, stderr, return_code.
    """
    try:
        stdin, stdout, stderr = ssh.exec_command(command, timeout=SSH_TIMEOUT)
        out = stdout.read().decode("utf-8", errors="ignore").strip()
        err_msg = stderr.read().decode("utf-8", errors="ignore").strip()
        exit_code = stdout.channel.recv_exit_status()
        return out, err_msg, exit_code
    except Exception as e:
        return "", str(e), -1


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
            r = requests.get(CSV_URL, timeout=30)
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
            "--delimiter=|",
            "--nth=1,2",
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
    """Fetch agent version dari remote via SSH + paramiko"""
    try:
        ssh = create_ssh_client(ip, SSH_USER, SSH_PASS)
        cmd = (
            f"unzip -p '{AGENT_JAR_PATH}' META-INF/MANIFEST.MF 2>/dev/null "
            f"| grep 'Implementation-Version' | cut -d: -f2 | tr -d ' \\r'"
        )
        out, err_msg, exit_code = run_ssh_command(ssh, cmd)
        ssh.close()
        return out or "-"
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
    """Show target stats (ping, IP, SSH user)"""
    try:
        # Windows: ping -n, Linux: ping -c
        ping_cmd = ["ping", "-n" if os.name == "nt" else "-c", "1"]
        if os.name != "nt":
            ping_cmd.extend(["-W", "1"])
        ping_cmd.append(ip)

        r = subprocess.run(ping_cmd, capture_output=True, text=True, timeout=5)
        if "time=" in r.stdout or "time<" in r.stdout:
            if os.name == "nt":
                ping_ms = r.stdout.split("time=")[1].split("ms")[0] + "ms"
            else:
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
        "PING        :", f"{ping_ms}" if ping_ms != "OFFLINE" else "[red]OFFLINE[/]"
    )
    stats_table.add_row("SSH USER    :", SSH_USER)

    console.print(
        Panel(stats_table, title="TARGET STATUS", border_style=PURPLE, padding=(0, 2))
    )


# ─────────────────────────────────────────────────────────────
# SCP FILE SYNC — PARAMIKO
# ─────────────────────────────────────────────────────────────


def sync_files(ip: str) -> bool:
    """
    Sync files dari remote ke local menggunakan paramiko + SCP.
    Return True jika semua file berhasil, False jika ada yang gagal.
    """
    console.print(f"\n[bold {PINK}]  SCP Files from Remote[/]")
    console.print(Rule(style=GREY))

    try:
        ssh = create_ssh_client(ip, SSH_USER, SSH_PASS)
    except SSHConnectionError as e:
        err(f"Failed to connect: {e}")
        return False

    all_ok = True

    with SCPClient(ssh.get_transport(), progress4=_scp_progress) as scp:
        for file_path in FILES_TO_SYNC:
            fname = os.path.basename(file_path)
            info(f"Syncing: [bold]{fname}[/]")

            try:
                local_path = Path(APP_DIR) / fname
                local_path.parent.mkdir(parents=True, exist_ok=True)

                # SCP get remote file → local
                scp.get(file_path, str(local_path))
                ok(f"{fname} synced")

            except FileNotFoundError:
                err(f"{fname} not found on remote")
                all_ok = False
                break
            except Exception as e:
                err(f"{fname} failed: {e}")
                all_ok = False
                break

    ssh.close()
    return all_ok


def _scp_progress(filename, size, sent):
    """Progress callback untuk SCP transfer"""
    percent = int((sent / size) * 100)
    console.print(f"  {filename}: {percent}%", end="\r")


# ─────────────────────────────────────────────────────────────
# UPDATE PROPERTIES
# ─────────────────────────────────────────────────────────────


def pull_remote_properties(ip: str) -> bool:
    """
    Pull server.properties dari remote via SSH + SCP.
    Base config — semua key lokasi-spesifik dari source of truth remote.
    """
    console.print(f"\n[bold {PINK}]  Pull server.properties from Remote[/]")
    console.print(Rule(style=GREY))

    props_path = Path(SERVER_PROPS)
    props_path.parent.mkdir(parents=True, exist_ok=True)

    try:
        ssh = create_ssh_client(ip, SSH_USER, SSH_PASS)
    except SSHConnectionError as e:
        err(f"Failed to connect: {e}")
        if props_path.exists():
            warn("Using existing local server.properties as fallback")
            warn("Value nya ga sesuai nih men")
            return True
        else:
            err("Tidak ada fallback — gaada server.properties lokal")
            return False

    with console.status("[cyan]Pulling server.properties...[/]", spinner="dots"):
        try:
            with SCPClient(ssh.get_transport()) as scp:
                scp.get(REMOTE_PROPS_PATH, str(props_path))
            ok(f"server.properties pulled from {ip}")

        except FileNotFoundError:
            err(f"server.properties not found on remote {ip}")
            if props_path.exists():
                warn("Using existing local server.properties as fallback")
                warn("Value nya ga sesuai nih men")
                ssh.close()
                return True
            else:
                err("Tidak ada fallback — gaada server.properties lokal")
                ssh.close()
                return False

        except Exception as e:
            err(f"Failed to pull server.properties from {ip}")
            err(f"SCP error: {e}")
            if props_path.exists():
                warn("Using existing local server.properties as fallback")
                warn("Value nya ga sesuai nih men")
                ssh.close()
                return True
            else:
                err("Tidak ada fallback — gaada server.properties lokal")
                ssh.close()
                return False

    ssh.close()

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
    Verify bahwa semua required keys ada di server.properties.
    Return (success, missing_keys).
    """
    props_path = Path(SERVER_PROPS)
    if not props_path.exists():
        return False, ["server.properties tidak ada"]

    existing = _parse_properties(props_path)
    missing = [k for k in updates.keys() if k not in existing]

    if missing:
        return False, missing
    return True, []


# ─────────────────────────────────────────────────────────────
# MAIN FLOW
# ─────────────────────────────────────────────────────────────


def main():
    show_header()

    # Load location data
    with console.status("[cyan]Loading location data...[/]", spinner="dots"):
        locations = load_sheet()

    if not locations:
        err("No locations loaded!")
        sys.exit(1)

    # Select target location
    target = select_location(locations)
    if not target:
        warn("Tidak ada lokasi yang dipilih")
        sys.exit(0)

    console.print()
    console.print(
        Panel(
            f"[{PINK}]TARGET SELECTED[/]\n"
            f"Unicode: [bold]{target['unicode']}[/]\n"
            f"Nama: [bold]{target['nama']}[/]\n"
            f"IP: [bold]{target['ip']}[/]",
            border_style=PINK,
        )
    )

    # Show stats
    show_stats(target["ip"], target["ip_masked"])

    # Check versions
    agent_ver, ws_ver, fs_ver = check_versions(target["ip"])

    # Sync files
    if not Confirm.ask("\n[?] Lanjutin ke sync files?", default=True):
        warn("Cancelled oleh user")
        sys.exit(0)

    if not sync_files(target["ip"]):
        err("File sync failed")
        sys.exit(1)

    # Pull properties
    if not Confirm.ask("\n[?] Lanjutin ke pull properties?", default=True):
        warn("Cancelled oleh user")
        sys.exit(0)

    if not pull_remote_properties(target["ip"]):
        err("Property pull failed")
        sys.exit(1)

    ok("\n[bold]Deployment completed successfully![/]")
    console.print(Rule(style=GREY))


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        console.print("\n")
        warn("Interrupted oleh user")
        sys.exit(0)
    except Exception as e:
        err(f"Unexpected error: {e}")
        sys.exit(1)
