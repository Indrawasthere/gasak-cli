<p align="center">
  <img src="https://img.shields.io/badge/version-1.5.2-magenta?style=for-the-badge" alt="version"/>
  <img src="https://img.shields.io/badge/go-1.24-00ADD8?style=for-the-badge&logo=go&logoColor=white" alt="go"/>
  <img src="https://img.shields.io/badge/platform-linux--amd64-333333?style=for-the-badge" alt="platform"/>
  <img src="https://img.shields.io/badge/license-proprietary-red?style=for-the-badge" alt="license"/>
</p>

<h1 align="center">GASAK CLI</h1>

<p align="center">
  <b>General Automation System & Administration Kit</b><br/>
  Internal platform otomasi berbasis terminal untuk Technical Support Engineering<br/>
  PT Inovasi Anak Indonesia (Parkee)
</p>

---

## Overview

**GASAK CLI** adalah platform otomasi internal berbasis terminal yang dibangun menggunakan Go, dirancang khusus untuk merapikan alur kerja Technical Support Engineering (TSE) di lingkungan PT Inovasi Anak Indonesia (Parkee).

Sebelum adanya GASAK, tim lapangan mengandalkan serangkaian script bash terfragmentasi, sesi SSH manual, dan utility Python ad-hoc untuk mengelola lebih dari 700 lokasi parkir lapangan. Pendekatan lama tersebut rawan error, inkonsisten antar engineer, dan sulit dimaintain pada skala besar.

GASAK menggantikan fragmentasi tersebut dengan CLI terstruktur yang mengenali role pengguna (*role-aware*) dan menerapkan prosedur operasional standar secara konsisten di seluruh lingkungan jaringan overlay ZeroTier.

---

## Problem Statement

Parkee mengoperasikan sistem manajemen parkir di **700+ lokasi lapangan**, di mana masing-masing menjalankan instance Parkee Agent yang terhubung melalui jaringan ZeroTier. Proses maintenance, peluncuran, dan diagnostik agen sebelumnya menghadapi kendala berupa:

- SSH manual ke tiap mesin secara individual hanya untuk mengecek versi agent
- Copy-paste IP address dari Google Sheets secara manual ke terminal
- Menjalankan script bash tanpa versi, tanpa validasi, atau error handling yang jelas
- Tidak adanya access control (seluruh script bisa diakses oleh semua engineer tanpa memandang role)
- Pengambilan file log memerlukan command SCP manual tanpa kemampuan menjelajahi direktori

---

## Solution

GASAK didistribusikan sebagai **satu binary Go tunggal** kepada seluruh engineer TSE melalui HTTP distribution server internal via ZeroTier. Fitur-fitur desain utamanya meliputi:

| Fitur | Deskripsi |
| --- | --- |
| **Single Binary Distribution** | Tidak memerlukan runtime dependencies di target machine, sangat krusial untuk deployment di skala besar pada lingkungan Linux yang heterogen |
| **Role-Based Access Control** | Menu dan aksi disaring berdasarkan deteksi role Teleport saat startup (L1 Support memiliki akses fitur yang lebih terbatas dibandingkan L2) |
| **Subprocess Launcher Pattern** | Tool dengan event loop eksternal (seperti Superfile atau Python GUI) dijalankan sebagai subprocess untuk menjaga stabilitas TUI utama |
| **Encrypted Vault System** | Semua kredensial sensitif dienkripsi menggunakan hybrid RSA-OAEP + AES-GCM, didistribusikan dari central vault server tanpa hardcode di binary |
| **Auto-Update Mechanism** | Setiap kali dijalankan, GASAK melakukan pengecekan versi ke server distribusi. Jika ditemukan versi baru, binary secara otomatis ter-update beserta seluruh script pendukung |

---

## Core Capabilities

### Tembak Agent (Agent Deployment)

Mengorkestrasi peluncuran penuh Parkee Agent ke lokasi lapangan dalam tahapan sekuensial yang tervalidasi:

1. **File Sync** — Sinkronisasi file JAR, aset suara, dan dependensi dari server pusat ke lokasi target via SSH (`rsync`)
2. **Remote Config Pull** — Mengambil file `server.properties` dari target via SCP sebagai base configuration
3. **Local Config Override** — Memperbarui key spesifik host (serverHost, dbHost, wsHost, kafkaHost, redisHost, minio endpoint, nama database, dan kredensial) di atas konfigurasi remote base
4. **Post-Write Verification** — Membaca ulang konfigurasi yang telah ditulis untuk memvalidasi setiap key sesuai dengan nilai yang diharapkan sebelum mengeksekusi proses
5. **Agent Launch** — Menjalankan JVM dengan flag akselerasi GPU via `nohup`, memonitor startup log untuk mendeteksi pola sukses/gagal

### Location Operations

- **Location Lookup** — Browser lokasi interaktif dengan pencarian fuzzy (*fuzzy search*) mencakup Unicode code, nama lokasi, dan ZeroTier IP menggunakan data dari cached Google Sheets CSV (1-hour TTL)
- **Direct SSH** — Membuka sesi SSH langsung dari lokasi yang dipilih dengan auto-load kredensial dari environment variables
- **Concurrent Version Checker** — Melakukan pengecekan versi secara paralel (Manifest JAR Agent, WS actuator `/info`, FS actuator `/info`) dengan timeout 3 detik per endpoint. Mendukung mass version checking multi-lokasi sekaligus

### Log Management

- **Log Fetcher** — Menjelajahi dan mengunduh file log jarak jauh dari 6 source (Watersheep, Fisherman, Syslog, PostgreSQL, Parkee Agent log dir, dan Parkee Agent tmp dir) langsung ke direktori lokal `~/Downloads/logs/<UNICODE>/`
- **Log Cutter** — Tool GUI berbasis Python untuk menyaring file log berukuran besar berdasarkan rentang tanggal (*date-range*). Mendukung multi-format timestamp detection, pembuatan backup otomatis, dan preview sebelum eksekusi

### Knowledge Base & Issue Tracking

- **Outline Search** — Pencarian full-text ke dokumentasi internal Parkee via Outline API, dirender langsung dalam format markdown di terminal
- **Linear Search** — Integrasi GraphQL untuk mencari isu/tiket di Linear lengkap dengan tampilan prioritas, status, assignee, dan metadata tim

### Settlement Tools

- **Settlement RFS** — Tool untuk download & compare data settlement STI remapping pending dari CMS database PostgreSQL, termasuk eskalasi otomatis ke pihak eksternal
- **Settlement Decode** — Dekripsi dan merge data payment dari API Parkee Cloud untuk analisis transaksi

### Reader Management

- **Reader Inject** — Setup dan konfigurasi reader Parkee (firmware v8/v12/v13/v14/v17/v19), termasuk PSAM configuration, crontab setup, dan serial port detection
- **Reader Update** — Update firmware reader via SCP dari server distribusi, dengan dukungan multi-version dan auto-cleanup

---

## Role-Based Access Control Matrix

GASAK mendeteksi role pengguna saat startup melalui parsing output `tsh status` (dengan fallback ke env `TELEPORT_ROLES` / `TELEPORT_USER` untuk konteks otomatisasi/CI).

| Feature | L1 Support | L2 & Other Roles |
| --- | ---: | :---: |
| Login Teleport | ✓ | ✓ |
| Tembak Agent (Deploy) | ✓ | ✓ |
| Location Lookup & Fuzzy Search | ✓ | ✓ |
| Potong Log (Log Cutting) | ✓ | ✓ |
| Ambil Log (Log Fetcher) | ✓ | ✓ |
| Search Outline Docs | ✓ | ✓ |
| Search Linear Issues | ✓ | ✓ |
| Settlement RFS | ✓ | ✓ |
| Settlement Decode | ✓ | ✓ |
| Inject Reader | ✓ | ✓ |
| Update Reader | ✓ | ✓ |
| Central v2 (SSH to Central) | — | ✓ |
| Superfile (File Manager) | — | ✓ |
| Crush Integration | — | ✓ |

---

## Architecture & Tech Stack

```
gasak (Go binary)
│
├── TUI Layer (Charmbracelet: huh, lipgloss, glamour)
│   ├── Main menu (role-filtered)
│   ├── Location selector (fuzzy search, Google Sheets cache)
│   └── Sub-menus (SSH, version check, log fetch, settlement)
│
├── Core Modules
│   ├── Teleport integration (tsh login, tsh ssh, tsh scp)
│   ├── Agent Launcher (deploy_parkee.py subprocess)
│   ├── Log management (log_cleaner.py subprocess, SCP fetch)
│   ├── Version checker (concurrent HTTP + SSH)
│   ├── Knowledge search (Outline API, Linear GraphQL API)
│   ├── Settlement engine (PostgreSQL direct query, Parkee Cloud API)
│   ├── Reader management (SSH/SCP, firmware deploy, PSAM config)
│   └── File manager (Superfile subprocess)
│
├── Vault System
│   ├── Vault Server (Go HTTP server, port 9002)
│   ├── Client Vault (RSA-2048 keypair + AES-256-GCM encryption)
│   └── Hybrid encryption (RSA-OAEP key envelope)
│
└── Distribution Layer
    ├── serve.sh (HTTP dist server @ 9001 via ZeroTier)
    ├── install.sh (client-side installer with ZeroTier pre-flight)
    ├── gasak-monitor.py (real-time TUI dashboard)
    └── Auto-update (version check on every startup, self-replace binary + scripts)
```

### Technology Stack

| Component | Technology | Rationale |
| --- | --- | --- |
| **Core language** | Go 1.24 | Menghasilkan single binary, startup cepat, tanpa runtime dependencies di target machine |
| **Terminal UI** | Charmbracelet (`huh`, `lipgloss`, `glamour`) | Framework TUI Go standar produksi untuk antarmuka keyboard-driven yang interaktif |
| **Deployment tool** | Python (`rich`, `questionary`, `iterfzf`) | Menyediakan flow interaktif yang kaya untuk logika konfigurasi deployment yang kompleks |
| **Log management** | Python (`tkinter`) | GUI interface untuk memudahkan filtering rentang tanggal pada file log yang besar |
| **Remote access** | Teleport (`tsh`) / `sshpass` | Enforcing keamanan berbasis role; L2 via Teleport, L1 via direct SSH overlay network |
| **Network layer** | ZeroTier | Jaringan overlay yang menghubungkan sistem manajemen pusat dengan 700+ lokasi lapangan |
| **Secret management** | Hybrid RSA-OAEP + AES-256-GCM | Enkripsi kredensial sensitif tanpa hardcode, didistribusikan dari central vault |
| **Knowledge Base** | Outline (Self-hosted) | Integrasi API pencarian dokumentasi internal tim |
| **Issue tracking** | Linear | Integrasi API GraphQL untuk tracking task engineering secara langsung |
| **CMS Database** | PostgreSQL | Direct query untuk settlement data analysis dan eskalasi |

---

## Project Structure

```
gasak/
├── main.go                  # Entry point utama — TUI menu, routing, version check
├── vault.go                 # Client-side vault decryption (RSA + AES-GCM)
├── vault-server.go          # Central vault server — encrypts secrets per-client
├── go.mod                   # Go module dependencies
├── go.sum                   # Dependency checksums
│
├── deploy_parkee.py         # Agent deployment tool (Linux — sshpass/rsync)
├── log_cleaner.py           # Log cutter GUI (Python tkinter)
├── decode_and_merge.py      # Settlement decode & merge API
├── settlement_rfs.py        # Settlement RFS compare & download
│
├── install.sh               # Client-side installer (5-step setup)
├── serve.sh                 # Distribution server (HTTP port 9001)
├── reinstall-vault.sh       # Vault re-registration tool
├── reader_script.sh         # Reader injection & PSAM config (multi-version)
├── update_reader.sh         # Reader firmware update (v14/v17/v19)
│
├── server.properties        # Base agent configuration template
├── version.txt              # Current release version (auto-update source)
├── .env.example             # Environment variable template
├── .gitignore               # Git ignore rules
├── LICENSE                  # Proprietary — PT Inovasi Anak Indonesia
│
├── windows-version/
│   └── deploy_parkee_win.py # Windows deployment variant (Paramiko/SCP)
│
├── vmon/
│   └── gasak-monitor.py     # Real-time distribution server TUI dashboard
│
└── firmware/                # Reader firmware packages (zip archives)
    ├── parque-fw-14.zip
    ├── parque-fw-17.zip
    ├── parque-fw-19.zip
    └── jellies_scripts.zip
```

---

## Quick Start

### Install via Distribution Server

Jalankan command berikut di terminal untuk mengunduh dan memasang GASAK (membutuhkan koneksi ZeroTier):

```bash
curl -fsSL http://10.70.0.110:9001/install.sh | bash
```

Installer akan melakukan:
1. Pre-flight check koneksi ZeroTier
2. Instalasi system dependencies (sshpass, rsync, fzf, build-essential)
3. Setup Python environment dengan semua package yang dibutuhkan
4. Download GASAK binary dan semua script pendukung
5. Registrasi vault & keypair untuk enkripsi kredensial
6. Setup shell alias (`gasak`)

### First Run

```bash
# Reload shell
source ~/.zshrc

# Jalankan GASAK
gasak
```

---

## Environment Configuration

GASAK memuat kredensial sensitif dari encrypted vault (atau fallback ke file `.env` lokal) menggunakan `godotenv`. Berikut template variabel yang dibutuhkan:

```env
# ─── Core ────────────────────────────────────────────────
LINEAR_API_KEY=your_linear_graphql_api_key
OUTLINE_API_KEY=your_outline_api_key
OUTLINE_URL=https://your-internal-outline-domain.com

# ─── SSH Credentials ─────────────────────────────────────
PARKEE_SSH_USER=support
PARKEE_SSH_PASS=your_ssh_password

# ─── Google Sheets (Deployment) ──────────────────────────
GSHEET_DEPLOY_ID=your_spreadsheet_id
GSHEET_DEPLOY_GID=your_sheet_gid

# ─── CMS Database (Settlement) ───────────────────────────
CMS_DB_HOST=your_cms_db_host
CMS_DB_PORT=5432
CMS_DB_USER=your_db_user
CMS_DB_PASS=your_db_password
CMS_DB_NAME=your_db_name

# ─── Vault & Distribution ────────────────────────────────
GASAK_VAULT_URL=http://10.70.0.110:9002
GASAK_DIST_URL=http://10.70.0.110:9001
GASAK_DIST_TOKEN=your_distribution_token

# ─── Teleport Fallback ───────────────────────────────────
TELEPORT_ROLES=fallback_role_if_tsh_not_detected
TELEPORT_USER=fallback_user_if_tsh_not_detected
```

---

## Distribution & Auto-Update

### Distribution Server

GASAK didistribusikan secara internal melalui HTTP distribution server yang berjalan di dalam jaringan ZeroTier. Server menyediakan:

| Endpoint | Deskripsi |
| --- | --- |
| `GET /` | Install script |
| `GET /gasak` | Binary terbaru |
| `GET /status` | Server status (JSON) |
| `GET /clients` | Client tracking (JSON) |
| `GET /checksums.sha256` | File checksums |
| `GET /logs` | Server activity logs |
| `GET /getenv?token=xxx` | Encrypted vault payload (auth required) |

### Auto-Update Mechanism

Setiap kali dijalankan, GASAK akan melakukan pengecekan versi ke file `version.txt` di server distribusi. Jika ditemukan versi baru, aplikasi secara otomatis:

1. Mengunduh binary baru
2. Mengganti dirinya sendiri (*self-replace binary*)
3. Mensinkronkan seluruh script pendukung dari server
4. Keluar dari proses untuk meminta pengguna menjalankan ulang

Ini memastikan seluruh tim di lapangan selalu menggunakan versi toolchain terbaru tanpa koordinasi manual.

### Vault Re-registration

Jika vault tidak valid atau expired, jalankan:

```bash
reinstall-vault
```

Tool ini akan generate keypair baru, registrasi ke vault server, dan mengunduh kredensial terenkripsi.

---

## Security

- **Encrypted Secrets** — Semua kredensial sensitif dienkripsi menggunakan hybrid RSA-OAEP (key envelope) + AES-256-GCM (payload). Tidak ada data rahasia yang di-hardcode dalam binary.
- **Per-Client Key Encryption** — Setiap instalasi memiliki RSA keypair unik. Vault server mengenkripsi payload menggunakan public key client — hanya client yang bersangkutan yang bisa mendekripsi.
- **Token-Based Auth** — Distribution server menggunakan token autentikasi untuk akses endpoint sensitif.
- **Role-Based Access** — Menu dan aksi disaring berdasarkan role Teleport pengguna saat startup.

---

## Ownership & License

**Proprietary Software** — Hak Cipta Milik **PT Inovasi Anak Indonesia (Parkee)**.

Seluruh hak dilindungi undang-undang. Penggunaan, penyalinan, distribusi, dan modifikasi kode ini di luar kepentingan operasional internal perusahaan harus mendapatkan izin tertulis dari pihak manajemen.

---

<p align="center">
  <sub>Built with care by the Parkee TSE Team</sub>
</p>
