# SYSTEM ARCHITECTURE DESIGN & TECHNICAL DOCUMENTATION

**Project:** GASAK CLI Toolchain — Phase 1: In-House DevOps Automation Engine

**Author:** Muhammad Fadlan Hafiz

**Target Role/Audience:** Technical Support Engineer L1/L2, Systems & Automation Engineers

**Document Type:** Technical Architecture Documentation, Feature Catalog, and Deployment Reference

**Version:** v1.1.12 (Production)

---

## 1. Executive Summary

GASAK (Go Automated Support Automation Kit) adalah CLI-based DevOps toolchain yang dirancang untuk menstandarisasi dan mengotomasikan seluruh workflow Technical Support Engineer (TSE) dalam mengelola 700+ node Parkee di seluruh Indonesia. Tool ini mengeliminasi kebutuhan akan SSH manual repetitif, mengurangi risiko human error akibat typo command destruktif, serta menyatukan seluruh utilitas lapangan ke dalam satu binary terpusat yang terdistribusi secara otomatis.

Arsitektur GASAK mengawinkan binary Go (core CLI) dengan ekosistem Python helper scripts, terdistribusi melalui HTTP server internal, dan terintegrasi penuh dengan ZeroTier VPN serta Teleport SSH untuk akses terenkripsi ke seluruh node lapangan. Seluruh komponen berjalan secara self-contained — binary utama memiliki kemampuan self-update, lokasi data di-cache secara lokal dari Google Sheets, dan kredensial diinjeksi melalui file `.env` yang di-generate otomatis saat instalasi.

Model ini mengubah operasi support dari pendekatan reaktif (SSH manual, ketik command satu per satu) menjadi pendekatan terstandardisasi dan terukur — di mana satu klik menu di terminal menggantikan belasan langkah manual yang sebelumnya rentan terhadap kesalahan.

## 2. System Architecture & Tech Stack

### Architecture Diagram

```
+------------------------------------------------------------------------------------+
|                          USER / TSE (L1 & L2)                                     |
+------------------------------------------------------------------------------------+
        |                                        |
        v Terminal (local laptop)                v Terminal (local laptop)
+--------------------+              +-----------------------------+
|   GASAK BINARY     |              |   HELPER PYTHON SCRIPTS    |
|   (main.go)        |              |   - deploy_parkee.py       |
|                    |              |   - settlement_rfs.py      |
|   Go + charmbracelet             |   - decode_and_merge.py     |
|   huh / lipgloss / glamour       |   - log_cleaner.py (tkinter)|
+--------------------+              +-----------------------------+
        |                                        |
        | exec.Command()                         | exec.Command()
        v                                        v
+---------------------------------------------------------------+
|                  DISTRIBUTION SERVER (serve.sh)               |
|                  10.70.0.110:9001                             |
|                  Python HTTP + Whitelist Security             |
+---------------------------------------------------------------+
        |                                        |
        v curl / scp                             v ZeroTier VPN
+--------------------+              +-----------------------------+
|   INSTALLER        |              |   TARGET NODES (700+)      |
|   (install.sh)     |              |   - Server Main             |
|   8-step flow      |              |   - Gate PCs (pm/pk)        |
|   APT + PIP + Shell|              |   - parkee-agent            |
+--------------------+              |   - Watersheep / Fisherman  |
                                    +-----------------------------+
                                              |
                                    +---------+---------+
                                    |                   |
                              +-----------+      +-----------+
                              | Teleport  |      | ZeroTier  |
                              | (tsh)     |      | VPN LAN   |
                              +-----------+      +-----------+
```

### Component Breakdown

#### Core Binary (main.go)

Binary Go single-file yang dikompilasi menjadi executable statis. Bertanggung jawab atas seluruh UI interaktif (menu selection via `charmbracelet/huh`), rendering terminal (via `charmbracelet/lipgloss` dan `charmbracelet/glamour`), orchestrasi SSH/SCP ke target nodes, dan manajemen distribusi file. Binary ini bersifat self-updating — pada setiap startup, ia memeriksa versi terbaru dari server distribusi dan mengganti dirinya sendiri secara otomatis jika tersedia versi baru.

#### Distribution Server (serve.sh)

Python HTTP server sederhana yang berjalan di port 9001 pada server internal (`10.70.0.110`). Server ini menyajikan seluruh komponen GASAK (binary, installer, scripts, config) kepada client melalui HTTP. Keamanan diimplementasikan melalui whitelist file — hanya file yang terdaftar di dalam whitelist yang boleh diakses. File `.env` (berisi kredensial) **tidak** disajikan ke client — `.env` digenerate di sisi client melalui installer.

#### Installer (install.sh)

Bash script 8-step yang menjalankan seluruh proses instalasi dari nol hingga GASAK siap digunakan. Installer ini bersifat idempotent (aman dijalankan berulang kali) dan non-blocking untuk dependency system — jika APT gagal menginstall suatu package, proses tetap dilanjutkan dengan laporan error di akhir.

#### Helper Scripts (Python)

Empat script Python yang dijalankan sebagai subprocess dari binary utama:
- `deploy_parkee.py` — Tool deployment agent dengan UI rich + questionary + iterfzf
- `settlement_rfs.py` — Tool settlement RFS dengan koneksi PostgreSQL
- `decode_and_merge.py` — Tool decode payment detail via API
- `log_cleaner.py` — GUI log cutter berbasis tkinter

### Tech Stack

| Komponen | Teknologi | Keterangan |
|---|---|---|
| Core Binary | Go 1.x | Single binary, cross-platform |
| UI Framework | charmbracelet/huh, lipgloss, glamour | Interactive forms, styled terminal, markdown rendering |
| Config Loading | joho/godotenv | Auto-load .env file |
| Helper Scripts | Python 3.8+ | psycopg2-binary, requests, questionary, iterfzf, rich, tkinter |
| Distribution | Python HTTP Server | Port 9001, whitelist-based file serving |
| Networking | ZeroTier One | Overlay VPN flat L2, IP 10.70.x.x |
| SSH Access | Teleport (tsh) | Role-based SSH (support / parkee-l2) |
| Backup SSH | sshpass | Direct SSH via password for L1 fallback |
| Location Data | Google Sheets API | CSV export, cached locally with 1-hour TTL |

## 3. Feature Catalog

### 3.1 Core Features (L1 & L2)

#### [1] Auto-Update Engine

Pada setiap startup, binary GASAK melakukan pengecekan versi ke server distribusi (`http://10.70.0.110:9001/version.txt`). Jika versi server berbeda dengan versi yang sedang berjalan, binary akan mengunduh versi baru, mengganti file executable yang sedang aktif, lalu keluar. User kemudian perlu menjalankan ulang GASAK untuk menggunakan versi baru.

**Flow:**
1. GET `version.txt` dari server distribusi
2. Bandingkan dengan `AppVersion` (hardcoded di binary)
3. Jika berbeda: download binary baru dari `http://10.70.0.110:9001/gasak`
4. Hapus executable lama, tulis binary baru, set permission 0755
5. Exit — user jalankan ulang manual

#### [2] Teleport SSH Login

Menjalankan `tsh login` dengan flag `--add-keys-to-agent=no` untuk kompatibilitas dengan OpenSSH. Memungkinkan user login ke Teleport cluster langsung dari menu GASAK tanpa perlu membuka terminal terpisah.

#### [3] Tembak Agent (Parkee Agent Deployment)

Pipeline deployment penuh untuk Parkee Agent ke node lapangan. Menggunakan `deploy_parkee.py` yang menjalankan 5 langkah berurutan:

1. **Sync Files** — rsync JAR production, sound files, dan dependencies dari remote ke local `/opt/app/agent/parkee-agent/`
2. **Pull Remote Config** — SCP `server.properties` dari node target sebagai base config
3. **Override Local Config** — Modify key tertentu (serverHost, dbHost, wsHost, kafkaHost, redisHost, minio.endpoint, fisherman.host, db, username, password) dengan value lokalisasi
4. **Launch Agent** — Kill proses existing, jalankan JVM dengan GPU flags (`-Dprism.forceGPU=true`, `-Dsun.java2d.opengl=true`) via nohup di background
5. **Wait Startup Verification** — Monitor log file secara real-time dengan regex pattern matching untuk mendeteksi startup success (HikariPool connected, Application started) atau fatal error (Exception, Address already in use)

**Fitur tambahan:**
- Fuzzy search lokasi via iterfzf
- Concurrent version check (Agent via SSH MANIFEST.MF, WS via Actuator :9005, FS via Actuator :8888)
- Ping statistics sebelum deploy
- Post-write verification untuk server.properties
- Sensitive key masking pada diff display

#### [4] Location Lookup

Sistem pencarian lokasi yang terintegrasi dengan Google Sheets sebagai master data. Fitur ini menyediakan dropdown interaktif dengan fuzzy search, serta opsi untuk melakukan pengecekan version secara massal.

**Sub-fitur:**

**[4a] Location Search & Detail Menu**
- Load data dari Google Sheets CSV (cache 1 jam di `~/.cache/parkee/master_loc.csv`)
- Dropdown interaktif via `huh` dengan filtering
- Menu detail lokasi: SSH ke lokasi, Check Live Version (concurrent)

**[4b] Mass Version Checker**
- Input multiple unicode (spasi-separated, contoh: `016 012 014`)
- Concurrent version check untuk setiap lokasi (3 goroutines: Agent + WS + FS)
- Agent version: SSH ke node, ekstrak `Implementation-Version` dari JAR MANIFEST.MF
- WS version: HTTP GET ke `http://<IP>:9005/actuator/info`
- FS version: HTTP GET ke `http://<IP>:8888/actuator/info`

#### [5] Potong Log (Log Cleaner)

GUI desktop application berbasis tkinter untuk filtering log berdasarkan rentang waktu. Mendukung 4 format timestamp (default, ISO, compact, slash). Fitur backup otomatis sebelum proses, opsi orphan line retention, dan real-time status bar.

**Dependencies:** python3-tk (via APT only)

#### [6] Ambil Log (Fetch Log)

Sistem penarikan log multi-sumber dengan role-based access control. Mendukung dua jalur akses: langsung dari server main, atau melalui 2-hop SCP dari gate PC.

**Sumber Log:**

| Sumber | Path | Tipe | Akses |
|---|---|---|---|
| [Server] Watersheep | /var/log/agent/watersheep | Directory | L1 & L2 |
| [Server] Fisherman | /var/log/agentweebhook | Directory | L1 & L2 |
| [Server] Syslog | /var/log/syslog | Single File | L1 & L2 |
| [Server] PostgreSQL | /var/log/postgresql | Directory | L2 Only |
| [Agent] Parkee Agent (/var/log/agent/parkee-agent) | /var/log/agent/parkee-agent | Directory | L1 & L2 (2-hop) |
| [Agent] Parkee Agent (/var/tmp/application) | /var/tmp/application | Directory | L1 & L2 (2-hop) |

**2-Hop SCP Flow (Gate PC Logs):**

```
GASAK (laptop)
    |
    | 1. SSH ke server main, query PostgreSQL
    |    SELECT DISTINCT ON (user_pc) user_pc, ip_address
    |    FROM core_user_activity
    |    WHERE user_pc LIKE '%<unicode>%'
    |
    v
Server Main (10.70.x.x)
    |
    | 2. Server main SCP dari gate PC ke /tmp/<filename>
    |    sshpass -p 'pc<unicode>client' scp <gate_user>@<gate_ip>:<path> /tmp/
    |
    v
Server Main /tmp/<filename>
    |
    | 3. GASAK SCP dari server main ke laptop lokal
    |    ~/Downloads/logs/<UNICODE>/<gate_user>/<filename>
    |
    v
Laptop (Local)
    |
    | 4. Cleanup /tmp/<filename> di server main
    v
Selesai
```

**Destination:** `~/Downloads/logs/<UNICODE>/` (direct) atau `~/Downloads/logs/<UNICODE>/<gate_user>/` (2-hop)

#### [7] Settlement RFS

Tool untuk analisis dan perbandingan data settlement STI (Standard Transaction Interface) dari database PostgreSQL. Menggunakan `settlement_rfs.py` dengan 2 mode operasi:

**[7a] Download & Compare Data Settlement**
- Query data settlement dengan status PENDING dan history DONE
- Download file settlement, OK response, dan NOK response dari cloud storage
- Bandingkan setiap record: apakah ada di OK response (00 - Accepted) atau tidak
- Generate laporan eskalasi ke `Laporan_Eskalasi.txt`
- Decision tree: ADA (eskalasi internal) vs TIDAK ADA (eskalasi eksternal ke STI)

**[7b] Download FS & Export CSV**
- Query data settlement dengan status UPLOAD
- Export metadata ke CSV (uploaded date, filename, settlement type, bank, count)
- Download file settlement dan response files

**Database:** PostgreSQL via environment variables (`CMS_DB_HOST`, `CMS_DB_PORT`, `CMS_DB_USER`, `CMS_DB_PASS`, `CMS_DB_NAME`)

#### [8] Settlement Decode

Tool untuk melihat detail data payment melalui API Parkee. Menggunakan `decode_and_merge.py` dengan flow:

1. Input API token (disimpan di `~/.parkee_token.json` selama 30 hari)
2. Input Location ID (angka)
3. Input External IDs (comma-separated)
4. Looping request POST ke `https://ms.parkee.app/cloud-settlement/v1/cloud-settlement-payment/decode`
5. Export hasil ke `merged_results_<location_id>.json`

### 3.2 L2-Only Features

#### [9] Central v2

SSH langsung ke `parkee-agent-central` via Teleport. Hanya tersedia untuk user dengan role L2 (bukan support).

#### [10] Superfile (spf)

Integrasi dengan terminal file manager Superfile. Menyediakan dropdown path untuk navigasi cepat ke direktori agent:
- Agent JAR Dir: `/opt/app/agent/parkee-agent/`
- Agent Log Dir: `/home/parkee/logs/`
- Agent Config Dir: `/opt/app/agent/`
- Home Downloads / Home Documents
- Custom path input

#### [11] Search Outline Docs

Pencarian dokumen di Outline wiki (`docs.sistemparkiran.com`) menggunakan API. Menampilkan hasil dalam format markdown (via glamour renderer) dengan collection info dan URL.

**API:** POST `https://docs.sistemparkiran.com/api/documents.search` dengan Bearer token.

#### [12] Search Linear Issues

Pencarian issue di Linear project management menggunakan GraphQL API. Menampilkan hasil dengan priority badge (Urgent/High/Medium/Low), team, status, assignee, dan URL.

**API:** POST `https://api.linear.app/graphql` dengan GraphQL query `searchIssues`.

### 3.3 Role-Based Access Control

| Fitur | L1 (support) | L2 (parkee-l2) |
|---|---|---|
| Login Teleport | Yes | Yes |
| Central v2 | No | Yes |
| Tembak Agent | Yes | Yes |
| Location Lookup | Yes | Yes |
| Potong Log | Yes | Yes |
| Ambil Log | Yes (minus PostgreSQL) | Yes (all) |
| Settlement RFS | Yes | Yes |
| Settlement Decode | Yes | Yes |
| Superfile | No | Yes |
| Search Outline | No | Yes |
| Search Linear | No | Yes |

Role detection dilakukan melalui parsing output `tsh status` (membaca field `Roles:`) atau dari environment variable `TELEPORT_ROLES`. Jika role mengandung string `support`, user dikategorikan sebagai L1. Selain itu, user dikategorikan sebagai L2.

## 4. Data Flow & Integration Points

### 4.1 Location Data Pipeline

```
Google Sheets (Spreadsheet ID: 1A0ce374...)
    |
    | HTTP GET (CSV export, gid=463772829)
    v
GASAK Binary
    |
    | Write ke ~/.cache/parkee/master_loc.csv (TTL: 1 jam)
    v
Local Cache File
    |
    | CSV parse: Unicode, Nama Lokasi, IP Zerotier
    | Filter: IP tidak kosong
    v
[]Location slice (in-memory)
    |
    +---> Location Lookup (dropdown + detail menu)
    +---> Mass Version Checker
    +---> Fetch Log (pilih lokasi target)
    +---> Tembak Agent (via deploy_parkee.py)
```

### 4.2 Gate PC Query Flow

```
GASAK Binary
    |
    | SSH ke server main (support@<IP> atau tsh ssh)
    |
    | Query PostgreSQL via psql heredoc:
    |   SELECT DISTINCT ON (user_pc) user_pc, ip_address
    |   FROM core_user_activity
    |   WHERE lower(user_pc) LIKE '%%' || (SELECT lower(unique_code) FROM location) || '%%'
    |     AND deleted_at IS NULL
    |     AND action_type = 'LOGIN'
    |     AND created_at >= NOW() - INTERVAL '31 days'
    |   ORDER BY user_pc, created_at DESC;
    |
    v
Parse output: user_pc | ip_address (pipe-delimited)
    |
    | Filter IP: ambil yang diawali "10." (ZeroTier)
    |             fallback ke IP pertama
    v
[]GateInfo slice (UserPC, IP)
    |
    | Password pattern: pc<unicode>client
    v
Gate selection dropdown
    |
    +---> List files di gate (2-hop SSH)
    +---> SCP file dari gate (2-hop SCP)
```

### 4.3 Version Check Flow

```
IP Target
    |
    +---> Agent Version (goroutine 1)
    |       SSH ke node, jalankan:
    |       unzip -p /mnt/shared/production/parkee-agent-production.jar
    |         META-INF/MANIFEST.MF 2>/dev/null
    |         | grep 'Implementation-Version'
    |         | cut -d: -f2 | tr -d ' \r '
    |
    +---> WS Version (goroutine 2)
    |       HTTP GET http://<IP>:9005/actuator/info
    |       Parse JSON: .build.version
    |
    +---> FS Version (goroutine 3)
    |       HTTP GET http://<IP>:8888/actuator/info
    |       Parse JSON: .build.version
    |
    v
Channel sink (3 results)
    |
    | Clean prefix "v", display
    v
Agent=vX.Y.Z / WS=vX.Y.Z / FS=vX.Y.Z
```

## 5. Distribution & Deployment Architecture

### 5.1 Distribution Server

HTTP server yang menjalankan `serve.sh` di port 9001. Menggunakan Python `http.server` dengan custom handler yang menerapkan whitelist-based file access.

**Whitelist (file yang boleh diakses client):**

| File | Tipe | Keterangan |
|---|---|---|
| gasak | Binary | CLI executable utama |
| install.sh | Bash | Installer script |
| serve.sh | Bash | Distribution server script |
| deploy_parkee.py | Python | Agent deployment tool |
| log_cleaner.py | Python | Log cleaner GUI |
| settlement_rfs.py | Python | Settlement RFS tool |
| decode_and_merge.py | Python | Settlement decode tool |
| version.txt | Text | Versi terkini (untuk auto-update check) |
| server.properties | Properties | Template config |

**File yang TIDAK di-serve:** `.env` (kredensial sensitif)

### 5.2 Installation Flow (install.sh)

```
STEP 1/8 — PREFLIGHT CHECK
    | Deteksi distro, cek koneksi ke server distribusi
    | (BLOCKER: jika server unreachable, installer berhenti)
    v
STEP 2/8 — APT SYSTEM DEPENDENCIES (NON-BLOCKING)
    | Install: python3, python3-pip, python3-tk, python3-venv,
    |          python-is-python3, sshpass, rsync, unzip, curl,
    |          wget, iputils-ping, fzf, lsof, net-tools, git
    | (NON-BLOCKING: APT gagal = lanjut, bukan abort)
    v
STEP 3/8 — CEK PYTHON RUNTIME
    | Validasi Python 3.8+, pip availability
    | (BLOCKER: tanpa Python, tidak ada yang bisa jalan)
    v
STEP 4/8 — SETUP DIREKTORI INSTALL
    | mkdir -p ~/gasak-dist
    v
STEP 5/8 — DOWNLOAD GASAK TOOLCHAIN
    | Download semua komponen dari server distribusi
    | (BLOCKER: jika ada file gagal download, installer berhenti)
    v
STEP 6/8 — SETUP .ENV (CREDENTIALS)
    | Tulis file .env dengan kredensial:
    |   GLPI_URL, OUTLINE_URL, OUTLINE_API_KEY, LINEAR_API_KEY,
    |   PARKEE_SSH_USER, PARKEE_SSH_PASS,
    |   CMS_DB_HOST, CMS_DB_PORT, CMS_DB_USER, CMS_DB_PASS, CMS_DB_NAME
    | Permission: 600 (hanya owner yang bisa baca)
    | Backup .env lama jika ada
    v
STEP 7/8 — INSTALL PYTHON MODULES
    | pip install: psycopg2-binary, requests, questionary, iterfzf, rich
    | Strategi install berlapis: --user --break-system-packages, --break-system-packages, --user, default
    | Verifikasi import semua module
    v
STEP 8/8 — PERMISSIONS, ALIAS & SHELL SETUP
    | Set permission binary (755), .py (644), .env (600)
    | Daftarkan alias 'gasak' ke shell profiles:
    |   ~/.bashrc, ~/.bash_profile, ~/.zshrc, ~/.profile, ~/.config/fish/config.fish
    | Export PATH ~/.local/bin
    | Auto-load .env saat shell start
    v
SELESAI — Summary & reload instruction
```

### 5.3 Auto-Update Mechanism

```
GASAK Binary Startup
    |
    | GET http://10.70.0.110:9001/version.txt (timeout 1 detik)
    v
Bandikan serverVersion vs AppVersion
    |
    +---> Sama = lanjut startup normal
    |
    +---> Berbeda:
            | Download http://10.70.0.110:9001/gasak
            | os.Remove(executable lama)
            | Tulis binary baru + chmod 0755
            | Print instruksi: "source ~/.zshrc atau ~/.bashrc lalu gasak lagi"
            | os.Exit(0)
```

## 6. Technical Dependencies

### APT Packages

| Package | Kegunaan | Bloker? |
|---|---|---|
| python3 | Runtime untuk helper scripts | Ya |
| python3-pip | Package manager Python | Ya |
| python3-tk | GUI toolkit untuk log_cleaner.py | Tidak (fitur log cleaner unavailable) |
| python3-venv | Virtual environment support | Tidak |
| python-is-python3 | Symlink `python` ke `python3` | Tidak |
| sshpass | SSH automation via password | Tidak (fetch log & location lookup unavailable) |
| rsync | File synchronization | Tidak (tembak agent unavailable) |
| unzip | JAR manifest extraction | Tidak |
| curl | HTTP requests | Tidak |
| wget | HTTP requests (fallback) | Tidak |
| iputils-ping | Network diagnostics | Tidak |
| fzf | Fuzzy finder (iterfzf dependency) | Tidak |
| lsof | List open files (port check) | Tidak |
| net-tools | Network utilities | Tidak |
| git | Version control | Tidak |

### Python Modules

| Module | PIP Package | Digunakan Oleh |
|---|---|---|
| psycopg2 | psycopg2-binary | settlement_rfs.py (PostgreSQL) |
| requests | requests | deploy_parkee.py, settlement_rfs.py (HTTP) |
| questionary | questionary | deploy_parkee.py (Interactive prompts) |
| iterfzf | iterfzf | deploy_parkee.py (Fuzzy search) |
| rich | rich | deploy_parkee.py (Terminal UI) |
| tkinter | python3-tk (APT) | log_cleaner.py (GUI) |

### Go Dependencies

| Module | Kegunaan |
|---|---|
| charmbracelet/huh | Interactive form / select / input |
| charmbracelet/lipgloss | Terminal styling & layout |
| charmbracelet/glamour | Markdown rendering |
| joho/godotenv | .env file loading |

### Network Requirements

| Service | Port | Protocol | Kegunaan |
|---|---|---|---|
| ZeroTier VPN | - | UDP/TUN | Overlay network ke 700+ nodes |
| Teleport (tsh) | 3023, 3024, 3080 | TCP/HTTPS | SSH access terenkripsi |
| Distribution Server | 9001 | HTTP | Binary & file distribution |
| Parkee Agent WS | 9005 | HTTP | Actuator info endpoint |
| Parkee Agent FS | 8888 | HTTP | Actuator info endpoint |
| PostgreSQL | 5432 | TCP | Settlement DB access |
| SSH (standard) | 22 | TCP | Direct node access |

## 7. Security Considerations

### 7.1 Credential Isolation

Seluruh kredensial (API keys, SSH passwords, database credentials) disimpan di file `~/.gasak-dist/.env` dengan permission `0600` — hanya user owner yang dapat membaca file ini. `.env` tidak pernah di-serve ke distribution server dan tidak pernah di-commit ke version control.

### 7.2 Distribution Server Whitelist

HTTP server menerapkan whitelist ketat. Hanya 9 file yang terdaftar di dalam `GasakDistHandler.WHITELIST` yang boleh diakses. Request ke file di luar whitelist menghasilkan `403 Access Denied`. File `.env` **tidak** masuk dalam whitelist.

### 7.3 Sensitive Key Masking

Pada fitur Tembak Agent, 6 kredensial yang dikirim ke node target (password, username, db, credential.information, minio.endpoint, fisherman.host) ditampilkan sebagai `***` di diff display — tidak pernah di-expose ke terminal.

### 7.4 Role-Based Feature Gating

Akses fitur dikontrol berdasarkan role Teleport user. Fitur sensitif (Central v2, Superfile, Search Outline, Search Linear) hanya tersedia untuk L2. PostgreSQL log hanya diakses L2. L1 hanya memiliki akses ke fitur dasar.

### 7.5 SSH Key Management

GASAK menggunakan dua mode SSH:
- **Teleport (tsh):** Untuk user L2, menggunakan certificate-based authentication yang dikelola oleh Teleport cluster
- **sshpass:** Untuk user L1 (fallback), menggunakan password hardcoded `REMOVED_PASSWORD` yang di-inject melalui `.env`

## 8. Operational Impact

### Root Cause Analysis (Masalah Lama vs Solusi GASAK)

**Akar Masalah Operasional:** Tim support sebelumnya harus melakukan SSH manual ke setiap node, mengetik command satu per satu untuk diagnostik, dan secara manual mengelola deployment agent. Proses ini memakan waktu 10-15 menit per lokasi, memiliki risiko typo command destruktif, serta tidak meninggalkan jejak audit yang terstruktur.

**Mitigasi GASAK:** Seluruh workflow diabstraksikan ke dalam menu interaktif terminal. User hanya perlu memilih opsi dari dropdown, memasukkan parameter yang diminta, dan sistem akan melakukan eksekusi secara terstandardisasi. Deployment agent yang sebelumnya memakan waktu 15 menit dengan 8 command manual, kini selesai dalam satu kali eksekusi dengan verifikasi otomatis.

### Impact Metrics Matrix

| Metrik Kinerja | Sebelum GASAK (Manual SSH) | Sesudah GASAK (CLI Automation) |
|---|---|---|
| Waktu Deployment Agent | 10 - 15 Menit per server (8+ command manual) | ~60 Detik (satu menu, 5 step otomatis) |
| Risiko Human Error / Typo | Tinggi (akses terminal langsung, command manual) | Minimal (command terenkapsulasi di dalam binary) |
| Kecepatan Version Check | 3 - 5 Menit per lokasi (curl manual ke actuator) | < 5 Detik (concurrent 3 goroutines) |
| Penarikan Log Gate PC | 20+ Menit (SSH manual bertingkat, paste command) | ~30 Detik (2-hop SCP otomatis) |
| Pencarian Dokumen | 5 - 10 Menit (buka browser, login Outline) | < 10 Detik (search langsung dari terminal) |
| Distribusi & Update | Manual copy binary ke tiap mesin | Otomatis (curl installer, self-update binary) |
| Standardisasi Environment | Tidak ada (tiap mesin beda setup) | Terjamin (installer idempotent, .env terpusat) |

### Operational Flow (GASAK Workflow)

1. **Instalasi:** TSE menjalankan `curl -fsSL http://10.70.0.110:9001/install.sh | bash` — seluruh dependency terinstall otomatis dalam satu command.

2. **Startup:** TSE menjalankan `gasak` di terminal. Binary memeriksa update, menampilkan splash screen dengan greeting personal, mendeteksi role Teleport, lalu menampilkan menu utama.

3. **Diagnostik:** TSE memilih "Location Lookup", mencari lokasi target via fuzzy search, lalu memilih "Check Live Version" — sistem secara concurrent mengecek versi Agent, WS, dan FS dalam hitungan detik.

4. **Intervensi:** Jika ditemukan masalah, TSE memilih "Tembak Agent" — sistem mengambil lokasi dari dropdown, melakukan rsync file, pull + override config, launch JVM, dan memverifikasi startup secara otomatis.

5. **Penarikan Log:** TSE memilih "Ambil Log", memilih lokasi dan tipe log, lalu sistem mengambil file log dari server atau gate PC (via 2-hop SCP) dan menyimpannya ke `~/Downloads/logs/`.

6. **Audit:** Setiap operasi mencatat path file log lokal yang dihasilkan, memberikan jejak audit yang dapat di-referensi.

---

## Appendix A: File Structure (~/gasak-dist/)

```
~/gasak-dist/
    .env                    # Kredensial (permission 600)
    gasak                   # Binary utama (permission 755)
    install.sh              # Installer script
    serve.sh                # Distribution server script
    deploy_parkee.py        # Agent deployment tool
    log_cleaner.py          # Log cleaner GUI
    settlement_rfs.py       # Settlement RFS tool
    decode_and_merge.py     # Settlement decode tool
    version.txt             # Versi terkini
    server.properties       # Template config
```

## Appendix B: Menu Structure

```
GASAK v1.1.12
    |
    +-- Login Teleport
    +-- Central v2                        [L2 Only]
    +-- Tembak Agent
    +-- Location Lookup
    |       +-- Search / Select Lokasi
    |       |       +-- SSH ke Lokasi
    |       |       +-- Check Live Version (Agent, WS, FS)
    |       +-- Mass Version Checker (input unicode list)
    +-- Potong Log
    +-- Ambil Log
    |       +-- Pilih Lokasi
    |       +-- Pilih Tipe Log
    |       +-- Download (direct SCP / 2-hop SCP)
    +-- Settlement RFS
    |       +-- Download & Compare
    |       +-- Download FS & Export CSV
    +-- Settlement Decode
    +-- Superfile                          [L2 Only]
    +-- Search Outline Docs                [L2 Only]
    +-- Search Linear Issues               [L2 Only]
    +-- Crush (Under Maintenance)          [L2 Only]
    +-- GLPI (Under Maintenance)           [L2 Only]
    +-- Exit
```
