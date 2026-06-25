<p align="center">
  <img src="https://img.shields.io/badge/version-1.5.2-blue" alt="Version">
  <img src="https://img.shields.io/badge/go-1.24.2-00ADD8?logo=go" alt="Go">
  <img src="https://img.shields.io/badge/python-3.8+-3776AB?logo=python" alt="Python">
  <img src="https://img.shields.io/badge/license-proprietary-red" alt="License">
</p>

<h1 align="center">GASAK CLI</h1>

<p align="center">
  <strong>Internal Operations Automation Platform for Parkee Field Support</strong><br>
  <sub>Built by Fadlan — PT Inovasi Anak Indonesia (Parkee)</sub>
</p>

<p align="center">
  <a href="#overview">Overview</a> &bull;
  <a href="#architecture">Architecture</a> &bull;
  <a href="#features">Features</a> &bull;
  <a href="#installation">Installation</a> &bull;
  <a href="#configuration">Configuration</a> &bull;
  <a href="#distribution">Distribution</a>
</p>

---

## Overview

**GASAK CLI** is an internal operations automation platform built for the Technical Support Engineering (TSE) team at Parkee. It replaces fragmented bash scripts, manual SSH sessions, and ad-hoc Python utilities with a single, structured CLI tool that manages over 700 parking locations across Indonesia.

The tool is distributed as a single Go binary via an HTTP distribution server running on ZeroTier, with an integrated auto-update mechanism that keeps all field engineers on the latest version without manual coordination.

### Problem Statement

Parkee operates parking management systems at 700+ field locations, each running a Parkee Agent connected through a ZeroTier overlay network. Prior to GASAK, the team faced:

- Manual SSH sessions to individual machines just to check agent versions
- Copy-pasting IP addresses from Google Sheets into terminals
- Running version-less bash scripts with no validation or error handling
- No access control — all scripts accessible regardless of role
- Manual SCP commands for log retrieval with no file browsing capability

### Solution

GASAK consolidates these workflows into a single binary with role-based access control, automated deployment pipelines, and integrated knowledge base search.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    GASAK CLI (Go Binary)                     │
├─────────────────────────────────────────────────────────────┤
│  TUI Layer (Charmbracelet: huh, lipgloss, glamour)          │
│  ├── Role-filtered main menu                                │
│  ├── Location selector (fuzzy search, Google Sheets cache)  │
│  └── Sub-menus (SSH, version check, log fetch, etc.)        │
├─────────────────────────────────────────────────────────────┤
│  Core Modules                                               │
│  ├── Teleport integration (tsh login, tsh ssh, tsh scp)     │
│  ├── Agent deployment (deploy_parkee.py subprocess)         │
│  ├── Log management (log_cleaner.py GUI, SCP fetch)         │
│  ├── Settlement tools (RFS compare, payment decode)         │
│  ├── Version checker (concurrent HTTP + SSH)                │
│  ├── Knowledge search (Outline API, Linear GraphQL)         │
│  ├── Reader management (firmware inject, PSAM config)       │
│  ├── Vault client (RSA-OAEP + AES-GCM decryption)           │
│  └── File manager (Superfile subprocess)                    │
├─────────────────────────────────────────────────────────────┤
│  Distribution Layer                                         │
│  ├── serve.sh (HTTP dist server @ :9001 via ZeroTier)       │
│  ├── install.sh (client installer with pre-flight checks)   │
│  └── Auto-update (version check + self-replace on startup)  │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│                  Vault Server (Go, port 9002)                │
│  ├── Hybrid encryption (RSA-OAEP + AES-256-GCM)             │
│  ├── PLOC API (location data from Google Sheets)            │
│  ├── Gate DB queries (via Teleport SSH)                     │
│  └── Health check endpoint                                  │
└─────────────────────────────────────────────────────────────┘
```

### Tech Stack

| Component | Technology | Purpose |
|-----------|-----------|---------|
| **Core CLI** | Go 1.24.2 | Single binary, fast startup, no runtime dependencies |
| **Terminal UI** | Charmbracelet (`huh`, `lipgloss`, `glamour`) | Interactive keyboard-driven interface |
| **Deployment** | Python (`rich`, `questionary`, `iterfzf`) | Rich deployment flow with fuzzy search |
| **Log Management** | Python (`tkinter`) | GUI date-range filter for large log files |
| **Remote Access** | Teleport (`tsh`) / `sshpass` | Role-based SSH (L2 via Teleport, L1 via direct SSH) |
| **Network** | ZeroTier | Overlay network connecting 700+ locations |
| **Vault** | RSA-OAEP + AES-256-GCM | Encrypted credential distribution |
| **Knowledge Base** | Outline (Self-hosted) | Internal documentation search |
| **Issue Tracking** | Linear | GraphQL-based issue search |
| **Monitoring** | Python (`rich`) | TUI dashboard for distribution server |

---

## Features

### Agent Deployment (`Tembak Agent`)

Orchestrates full Parkee Agent deployment in a validated 5-step pipeline:

1. **File Sync** — rsync JAR, sound assets, and dependencies from server to target via SSH
2. **Remote Config Pull** — SCP `server.properties` from target as base configuration
3. **Local Config Override** — Update host-specific keys (serverHost, dbHost, wsHost, etc.) on top of remote base
4. **Post-Write Verification** — Re-read config to validate every key matches expected values
5. **Agent Launch** — JVM startup with GPU acceleration flags, monitored via nohup log with 60s timeout

### Location Operations

- **Fuzzy Search** — Interactive location browser with Unicode, name, and ZeroTier IP search from cached Google Sheets CSV (1-hour TTL)
- **Direct SSH** — Open SSH session from selected location with auto-loaded credentials
- **Mass Version Checker** — Concurrent version checking (Agent JAR, WS actuator, FS actuator) across multiple locations simultaneously

### Log Management

- **Log Fetcher** — Browse and download logs from 6 sources (Watersheep, Fisherman, Syslog, PostgreSQL, Agent logs, Agent tmp) to `~/Downloads/logs/<UNICODE>/`
- **Log Cutter** — Tkinter GUI for date-range filtering of large log files with multi-format timestamp detection and auto-backup

### Settlement Tools

- **Settlement RFS** — PostgreSQL-based comparison of pending settlement data with automatic file download and escalation report generation
- **Settlement Decode** — Payment detail decoder via Parkee Cloud API with token caching (30-day TTL)

### Reader Management

- **Firmware Injection** — Multi-version reader firmware deployment (v8/v12/v13/v14/v17/v19) with automated SCP, permission setting, and crontab configuration
- **PSAM DKI Config** — Install, disable, enable, reset, and verify PSAM DKI configurations on reader devices
- **Update Reader** — End-to-end firmware update with server file fetching, reader reboot, and agent service restart

### Knowledge Base

- **Outline Search** — Full-text search across internal Parkee documentation with markdown rendering in terminal
- **Linear Search** — GraphQL-based issue search with priority, status, assignee, and team metadata display

### System Integration

- **Teleport Login** — Seamless `tsh login` with `--add-keys-to-agent=no` flag
- **Superfile** — TUI file manager for browsing remote directories
- **Crush** — Integration with Crush task management tool
- **Vault Client** — Encrypted credential distribution from central vault server

---

## Role-Based Access Control

GASAK detects user role at startup via `tsh status` parsing (with fallback to `TELEPORT_ROLES` / `TELEPORT_USER` env vars).

| Feature | L1 Support | L2 & Other Roles |
|---------|-----------|-----------------|
| Login Teleport | Yes | Yes |
| Tembak Agent (Deploy) | Yes | Yes |
| Location Lookup | Yes | Yes |
| Potong Log (Log Cutting) | Yes | Yes |
| Ambil Log (Log Fetcher) | Yes | Yes |
| Settlement RFS | Yes | Yes |
| Settlement Decode | Yes | Yes |
| Inject Reader | Yes | Yes |
| Update Reader | Yes | Yes |
| Search Outline Docs | Yes | Yes |
| Search Linear Issues | Yes | Yes |
| Central v2 (SSH) | No | Yes |
| Superfile (File Manager) | No | Yes |
| Crush Integration | No | Yes |

---

## Project Structure

```
gasak/
├── main.go                    # Go CLI entry point (TUI, auto-updater, all modules)
├── vault.go                   # Client-side vault decryption (RSA-OAEP + AES-GCM)
├── vault-server.go            # Vault server (port 9002, PLOC API, health check)
├── go.mod                     # Go module definition
├── go.sum                     # Go dependency checksums
│
├── deploy_parkee.py           # Agent deployment pipeline (Linux)
├── log_cleaner.py             # Tkinter GUI log date-range cutter
├── settlement_rfs.py          # PostgreSQL settlement RFS comparison
├── decode_and_merge.py        # Payment decode via Parkee Cloud API
│
├── install.sh                 # Client-side installer (5-step, progress bars)
├── serve.sh                   # Distribution HTTP server (port 9001)
├── reinstall-vault.sh         # Vault re-registration tool
│
├── reader_script.sh           # Reader firmware injection (v8-v19)
├── update_reader.sh           # Firmware updater with PSAM config management
│
├── server.properties          # Agent configuration template
├── version.txt                # Current release version
├── LICENSE                    # Proprietary — PT Inovasi Anak Indonesia
│
├── vmon/
│   └── gasak-monitor.py       # TUI dashboard for dist server monitoring
│
├── ploc/
│   ├── ploc_method.py         # Google Sheets location lookup
│   └── service_account.json   # Google service account credentials (not in repo)
│
├── windows-version/
│   └── deploy_parkee_win.py   # Windows deployment tool (Paramiko + SCP)
│
└── firmware/
    ├── parque-fw-14.zip       # Reader firmware v14
    ├── parque-fw-17.zip       # Reader firmware v17
    ├── parque-fw-19.zip       # Reader firmware v19
    └── jellies_scripts.zip    # Reader support scripts
```

---

## Installation

### Prerequisites

- Linux (Ubuntu 22.04+ / Debian / Linux Mint) with ZeroTier connected
- `curl`, `python3`, `pip3`, `sshpass`, `rsync`
- Teleport (`tsh`) logged in for L2 access

### Install via Script

```bash
curl -fsSL http://10.70.0.110:9001/install.sh | bash
```

The installer will:
1. Validate network connectivity and system compatibility
2. Install system dependencies (sshpass, rsync, fzf, python3-tk)
3. Install Python packages (rich, questionary, iterfzf, psycopg2-binary, etc.)
4. Download GASAK components from the distribution server
5. Generate RSA keypair and register with the vault server

### Quick Start

```bash
# Reload shell after installation
source ~/.zshrc   # or ~/.bashrc

# Run GASAK
gasak
```

---

## Configuration

### Environment Variables

GASAK loads credentials from an encrypted vault (preferred) or `.env` fallback. Create `~/gasak-dist/.env`:

```env
# API Keys
LINEAR_API_KEY=your_linear_api_key
OUTLINE_API_KEY=your_outline_api_key
OUTLINE_URL=https://your-outline-domain.com
GLPI_URL=https://your-glpi-domain.com

# SSH Credentials
PARKEE_SSH_USER=support
PARKEE_SSH_PASS=your_ssh_password

# Google Sheets
GSHEET_DEPLOY_ID=your_spreadsheet_id
GSHEET_DEPLOY_GID=your_sheet_gid

# CMS Database
CMS_DB_HOST=your_db_host
CMS_DB_PORT=5432
CMS_DB_USER=your_db_user
CMS_DB_PASS=your_db_password
CMS_DB_NAME=your_db_name

# Vault & Distribution
GASAK_VAULT_URL=http://10.70.0.110:9002
GASAK_DIST_URL=http://10.70.0.110:9001
GASAK_DIST_TOKEN=gsk_dist_9f2k7x
```

### Vault Re-registration

If vault sync fails, re-register your device:

```bash
bash ~/gasak-dist/reinstall-vault.sh
```

---

## Distribution & Auto-Update

### Distribution Server

The distribution server runs on `10.70.0.110:9001` (ZeroTier) and serves:

| Endpoint | Description |
|----------|-------------|
| `GET /` | Install script |
| `GET /gasak` | Latest binary |
| `GET /version.txt` | Current version |
| `GET /status` | Server status (JSON) |
| `GET /clients` | Connected clients (JSON) |
| `GET /checksums.sha256` | File checksums |
| `GET /getenv?token=xxx` | .env distribution (auth required) |
| `GET /logs?lines=N` | Recent server logs |

### Auto-Update

On every startup, GASAK checks `version.txt` on the distribution server. If a newer version is detected:
1. Downloads the new binary
2. Self-replaces the current executable
3. Syncs 6 supporting scripts from the server
4. Exits with a message to restart

### Monitoring Dashboard

```bash
python3 ~/gasak-dist/vmon/gasak-monitor.py
```

Real-time TUI showing server status, connected clients, and recent activity.

---

## Build

### Client Binary

```bash
go build -o gasak main.go vault.go
```

### Vault Server

```bash
go build -o vault-server vault-server.go
```

---

## License

Proprietary Software — Copyright PT Inovasi Anak Indonesia (Parkee). All rights reserved.

Unauthorized use, copying, distribution, or modification of this code outside of internal operational purposes requires written permission from management.
