# GASAK CLI

---

## Overview

**GASAK CLI** adalah platform otomasi internal berbasis terminal yang dibangun menggunakan Go, dirancang khusus untuk merapikan alur kerja Technical Support Engineering (TSE) di lingkungan PT Inovasi Anak Indonesia (Parkee).

Sebelum adanya GASAK, tim lapangan mengandalkan serangkaian script bash terfragmentasi, sesi SSH manual, dan utility Python ad-hoc untuk mengelola lebih dari 700 lokasi parkir lapangan. Pendekatan lama tersebut rawan error, inkonsisten antar engineer, dan sulit dimaintain pada skala besar.

GASAK menggantikan fragmentasi tersebut dengan CLI terstruktur yang mengenali role pengguna (*role-aware*) dan menerapkan prosedur operasional standar secara konsisten di seluruh lingkungan jaringan overlay ZeroTier.

---

## Problem Statement & Solution

### Problem Statement

Parkee mengoperasikan sistem manajemen parkir di 700+ lokasi lapangan, di mana masing-masing menjalankan instance Parkee Agent yang terhubung melalui jaringan ZeroTier. Proses maintenance, peluncuran, dan diagnostik agen sebelumnya menghadapi kendala berupa:

* SSH manual ke tiap mesin secara individual hanya untuk mengecek versi agent.
* Melakukan copy-paste IP address dari Google Sheets secara manual ke terminal.
* Menjalankan script bash tanpa versi, tanpa validasi, ataupun error handling yang jelas.
* Tidak adanya access control (seluruh script bisa diakses oleh semua engineer tanpa memandang role).
* Pengambilan file log memerlukan command SCP manual tanpa kemampuan menjelajahi direktori (*file browsing*).

### Solution

GASAK didistribusikan sebagai satu binary Go tunggal kepada seluruh engineer TSE melalui HTTP distribution server internal via ZeroTier. Fitur-fitur desain utamanya meliputi:

* **Single Binary Distribution:** Tidak memerlukan runtime dependencies di target machine, sangat krusial untuk launching di skala besar pada lingkungan Linux yang heterogen.
* **Role-Based Access Control (RBAC):** Menu dan aksi disaring berdasarkan deteksi role Teleport saat startup (L1 Support memiliki akses fitur yang lebih terbatas dibandingkan L2).
* **Subprocess Launcher Pattern:** Tool dengan event loop eksternal (seperti Superfile atau Python GUI) dijalankan sebagai subprocess untuk menjaga stabilitas TUI utama.
* **Environment-Based Configuration:** Semua kredensial sensitif dimuat dari file `.env` menggunakan `godotenv`, tidak ada data rahasia yang di-hardcode dalam binary.

---

## Core Capabilities

### Tembak Agent (Agent Deployment)

Mengorkestrasi peluncuran penuh Parkee Agent ke lokasi lapangan dalam 5 tahapan sekuensial yang tervalidasi:

1. **File Sync:** Sinkronisasi file JAR, aset suara, dan dependensi dari server pusat ke lokasi target via SSH (`rsync`).
2. **Remote Config Pull:** Mengambil file `server.properties` dari target via SCP sebagai base configuration.
3. **Local Config Override:** Memperbarui key spesifik host (seperti *serverHost, dbHost, wsHost, kafkaHost, redisHost, minio endpoint, nama database, dan kredensial*) di atas konfigurasi remote base.
4. **Post-Write Verification:** Membaca ulang konfigurasi yang telah ditulis untuk memvalidasi setiap key sesuai dengan nilai yang diharapkan sebelum mengeksekusi proses.
5. **Agent Launch:** Menjalankan JVM dengan flag akselerasi GPU via `nohup`, serta memonitor startup log untuk mendeteksi pola sukses/gagal dengan timeout 60 detik.

### Location Operations

* **Location Lookup:** Browser lokasi interaktif dengan pencarian fuzzy (*fuzzy search*) mencakup Unicode code, nama lokasi, dan ZeroTier IP menggunakan data dari cached Google Sheets CSV (1-hour TTL).
* **Direct SSH:** Membuka sesi SSH langsung dari lokasi yang dipilih dengan auto-load kredensial dari environment variables.
* **Concurrent Version Checker:** Melakukan pengecekan versi secara paralel (Manifest JAR Agent, WS actuator `/info`, FS actuator `/info`) dengan timeout 3 detik per endpoint. Mendukung mass version checking multi-lokasi sekaligus menggunakan input Unicode yang dipisahkan spasi.

### Log Management

* **Log Fetcher:** Menjelajahi dan mengunduh file log jarak jauh dari 6 source (Watersheep, Fisherman, Syslog, PostgreSQL, Parkee Agent log dir, dan Parkee Agent tmp dir) langsung ke direktori lokal `~/Downloads/logs/<UNICODE>/`. Transportasi otomatis disesuaikan: L2 menggunakan `tsh scp` (Teleport), sedangkan L1 menggunakan `sshpass scp` langsung via IP ZeroTier.
* **Log Cutter:** Tool GUI berbasis Python untuk menyaring file log berukuran besar berdasarkan rentang tanggal (*date-range*). Mendukung multi-format timestamp detection, pembuatan backup otomatis sebelum proses, dan menyediakan 20-line preview sebelum eksekusi.

### Knowledge Base & Issue Tracking

* **Outline Search:** Pencarian full-text ke dokumentasi internal Parkee via Outline API, dirender langsung dalam format markdown yang rapi di terminal.
* **Linear Search:** Integrasi GraphQL untuk mencari isu/tiket di Linear lengkap dengan tampilan prioritas, status, assignee, dan metadata tim secara inline.

---

## Role-Based Access Control Matrix

GASAK mendeteksi role pengguna saat startup melalui parsing output `tsh status` (dengan fallback ke env `TELEPORT_ROLES` / `TELEPORT_USER` untuk konteks otomatisasi/CI).

| Feature | L1 Support | L2 & Other Roles |
| --- | --- | --- |
| Login Teleport | Ya | Ya |
| Tembak Agent (Deploy) | Ya | Ya |
| Location Lookup & Fuzzy Search | Ya | Ya |
| Potong Log (Log Cutting) | Ya | Ya |
| Ambil Log (Log Fetcher) | Ya | Ya |
| Search Outline Docs | Ya | Ya |
| Search Linear Issues | Ya | Ya |
| Central v2 (SSH to Central) | Tidak | Ya |
| Superfile (File Manager) | Tidak | Ya |
| Crush Integration | Tidak | Ya |
| GLPI | Tidak | Ya |
| PostgreSQL Log Access | Tidak | Ya |

---

## Architecture & Tech Stack

```text
gasak (Go binary)
│
├── TUI Layer (Charmbracelet: huh, lipgloss, glamour)
│   ├── Main menu (role-filtered)
│   ├── Location selector (fuzzy search, Google Sheets cache)
│   └── Sub-menus (SSH, version check, log fetch)
│
├── Core Modules
│   ├── Teleport integration (tsh login, tsh ssh, tsh scp)
│   ├── Agent Launcher (deploy_parkee.py subprocess)
│   ├── Log management (log_cleaner.py subprocess, SCP fetch)
│   ├── Version checker (concurrent HTTP + SSH)
│   ├── Knowledge search (Outline API, Linear GraphQL API)
│   └── File manager (Superfile subprocess)
│
└── Distribution Layer
    ├── serve.sh (HTTP dist server @ 10.70.0.110:9001 via ZeroTier)
    ├── install.sh (client-side installer with ZeroTier pre-flight)
    └── Auto-update (version check on every startup, self-replace binary)

```

| Component | Technology | Rationale |
| --- | --- | --- |
| **Core language** | Go | Menghasilkan single binary, startup cepat, tanpa runtime dependencies di target machine. |
| **Terminal UI** | Charmbracelet (`huh`, `lipgloss`, `glamour`) | Framework TUI Go standar produksi untuk antarmuka keyboard-driven yang interaktif. |
| **Deployment tool** | Python (`rich`, `questionary`, `iterfzf`) | Menyediakan flow interaktif yang kaya untuk logika konfigurasi deployment yang kompleks. |
| **Log management** | Python (`tkinter`) | GUI interface untuk memudahkan filtering rentang tanggal pada file log yang besar. |
| **Remote access** | Teleport (`tsh`) / `sshpass` | Enforcing keamanan berbasis role; L2 via Teleport, L1 via direct SSH overlay network. |
| **Network layer** | ZeroTier | Jaringan overlay yang menghubungkan sistem manajemen pusat dengan 700+ lokasi lapangan. |
| **Knowledge Base** | Outline (Self-hosted) | Integrasi API pencarian dokumentasi internal tim. |
| **Issue tracking** | Linear | Integrasi API GraphQL untuk tracking task engineering secara langsung. |

---

## Environment Configuration

Aplikasi memuat konfigurasi sensitif dari file `.env` lokal menggunakan `godotenv`. Buat file `.env` di direktori kerja aplikasi:

```env
LINEAR_API_KEY=your_linear_graphql_api_key
OUTLINE_API_KEY=your_outline_api_key
OUTLINE_URL=https://your-internal-outline-domain.com
GLPI_URL=https://your-glpi-domain.com
TELEPORT_ROLES=fallback_role_if_tsh_not_detected
TELEPORT_USER=fallback_user_if_tsh_not_detected

```

---

## Distribution & Auto-Update

GASAK didistribusikan secara internal melalui HTTP distribution server yang berjalan di dalam jaringan ZeroTier.

### Install Client-Side

Jalankan command berikut di terminal untuk mengunduh dan memasang melalui installer script (dilengkapi dengan pre-flight check konektivitas ZeroTier):

```bash
curl -fsSL http://your-server/install.sh | bash

```

### Auto-Update Mechanism

Setiap kali dijalankan, GASAK akan melakukan pengecekan versi ke file `version.txt` di server distribusi (`10.70.0.110:9001`). Jika ditemukan versi baru, aplikasi secara otomatis mengunduh, mengganti dirinya sendiri (*self-replace binary*), lalu keluar dari proses untuk meminta pengguna menjalankan ulang aplikasi. Ini memastikan seluruh tim di lapangan selalu menggunakan versi toolchain terbaru tanpa koordinasi manual.

---

## Project Repository Structure

### Working Directory (Development/Build environment)

```text
gasak/
├── deploy_dist.sh       # Script otomatisasi build dan push ke server distribusi
├── deploy_parkee.py     # Script Python untuk manajemen deployment dan penulisan config
├── go.mod               # Definisi modul utama Go
├── go.sum               # Checksum dependensi Go
├── log_cleaner.py       # Python GUI utility untuk memotong log berdasarkan date range
├── main.go              # Entry point utama aplikasi GASAK TUI
└── README.md            # Dokumentasi project

```

### Serve Directory (Distribution server environment)

```text
gasak-dist/
├── deploy_parkee.py     # Script pendukung deployment yang diunduh client
├── gasak                # Kompilasi executable binary Go terbaru
├── install.sh           # Installer script untuk client side
├── log_cleaner.py       # Script pendukung log cutting yang diunduh client
├── server.properties    # Base configuration template untuk kebutuhan sinkronisasi
├── serve.sh             # Script untuk menjalankan HTTP distribution server di port 9001
└── version.txt          # File teks penanda versi rilis aktif untuk auto-update

```

---

## Ownership & License

Proprietary Software - Hak Cipta Milik **PT Inovasi Anak Indonesia (Parkee)**.
Seluruh hak dilindungi undang-undang. Penggunaan, penyalinan, distribusi, dan modifikasi kode ini di luar kepentingan operasional internal perusahaan harus mendapatkan izin tertulis dari pihak manajemen.
