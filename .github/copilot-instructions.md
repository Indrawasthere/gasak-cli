# Instruksi Copilot untuk repositori GASAK CLI

Ringkasan singkat: file ini menjelaskan perintah build/test/lint yang tersedia, arsitektur tingkat-tinggi, dan konvensi khusus repo agar sesi Copilot/AI lebih efektif.

1) Perintah build, test, dan lint
- Build (dari root repo):
  - go build -o gasak .
- Menjalankan binary lokal:
  - ./gasak
- Menjalankan server distribusi (untuk testing distribusi):
  - ./serve.sh  # butuh akses jaringan ZeroTier
- Menjalankan installer (uji alur unduh/instal):
  - ./install.sh  # jalankan di lingkungan yang aman

Testing
- Saat ini tidak ada test Go bawaan di repo. Untuk menambahkan/menjalankan test:
  - Semua package: go test ./...
  - Satu package: go test ./path/to/package
  - Satu test spesifik: go test ./path/to/package -run TestName

Linting
- Static checks: go vet ./...
- Jika tersedia: golangci-lint run

2) Arsitektur tingkat-tinggi (big picture)
- Single-binary Go TUI
  - main.go membangun terminal UI (Charmbracelet) dan menjadi entrypoint utama.
- Modul inti (di dalam binary)
  - Role detection (Teleport `tsh` parsing, fallback TELEPORT_ROLES/TELEPORT_USER dari .env).
  - Launcher subprocess: tugas kompleks/GUI didelegasikan ke script Python (mis. deploy_parkee.py, log_cleaner.py) yang dijalankan sebagai subprocess.
  - Version/check & auto-update: mekanisme membandingkan versi lokal dengan serve-dist/version.txt dan melakukan self-replace bila perlu.
- Tool pendukung (Python)
  - Log cutter/GUI dan flow deployment tetap di Python agar UI Go tetap ringan dan stabil.
- Konfigurasi lingkungan
  - Nilai sensitif dimuat dari .env (godotenv) atau disuntik via mekanisme vault yang dimiliki aplikasi; hindari hardcode secrets.

3) Konvensi kunci (repo-specific)
- Role-aware feature gating
  - Semua fitur yang mengakses resource sensitif (deploy, fetch logs, akses DB) harus memeriksa peran pengguna (L1 vs L2) menggunakan pola yang sama seperti di main.go (tsh -> env fallback).
- Subprocess launcher pattern
  - Script Python di-bundle dalam distribusi; panggil sebagai subprocess dari Go dan biarkan mereka mewarisi environment dari proses induk.
- Single-binary distribution
  - Hindari menambah runtime dependency yang harus diinstal pada mesin target kecuali dibundel di server distribusi.
- Network & transport
  - ZeroTier overlay IP untuk SSH/SCP pada L1; Teleport (`tsh scp`/`tsh ssh`) untuk L2. Pastikan kode memilih transport berdasarkan role.
- Versioning & release flow
  - `serve-dist/` (serve.sh, version.txt, binary, companion scripts) adalah sumber kebenaran untuk auto-update. Update version.txt dan binary secara bersamaan saat rilis.

4) Integrasi file lain & catatan penting
- Periksa README.md untuk detail operasional yang lengkap.
- File utama untuk referensi saat menambah fitur:
  - main.go
  - deploy_parkee.py
  - log_cleaner.py
  - serve.sh, install.sh, version.txt

5) Pemeriksaan konfigurasi AI/assisten lain
- Tidak ditemukan file konfigurasi asisten AI khusus (CLAUDE.md, .cursorrules, AGENTS.md, .windsurfrules, CONVENTIONS.md, dsb.) di repo ini.

6) Petunjuk singkat untuk Copilot/AI
- Saat menyarankan perubahan yang menyentuh deploy/credentials: jangan menyarankan hardcode credential atau menaruh secret di .env tanpa proses vault.
- Sebutkan dampak terhadap distribusi single-binary bila menambahkan dependensi baru dan sertakan langkah bundling ke serve-dist + update install.sh.

Selesai. Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>
