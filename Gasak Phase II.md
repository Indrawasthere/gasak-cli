# SYSTEM ARCHITECTURE DESIGN & DEVELOPMENT BLUEPRINT

**Project:** GASAK Web Version — Phase 2: Automation Portal

**Author:** Muhammad Fadlan Hafiz

**Target Role/Audience:** Senior Technical Support Engineer / Supeng (Systems & Automation Engineers)

**Document Type:** Technical Blueprint, Architecture Design, and Project Deployment Roadmap

## 1. Executive Summary

GASAK Phase 1 berhasil menstandarisasi environment lapangan via CLI. Namun, mengelola 700+ lokasi Parkee secara manual melalui SSH individual menimbulkan bottleneck operasional, tingginya risiko human error (typo command kritis), serta fragmentasi knowledge di tingkat Technical Support Engineer (TSE).

Phase 2 melakukan migrasi dari model CLI statis ke Internal DevOps Portal berbasis web dengan mengawinkan **Budibase** sebagai Dynamic Front-End App Builder dan **Rundeck** sebagai Enterprise Automation Engine. Menggantikan backend OliveTin dengan kombinasi ini memberikan manajemen state yang kuat, Role-Based Access Control (RBAC) granular, penanganan input dinamis tanpa hardcoding, serta visualisasi log response yang aman. Hasil akhirnya adalah sistem _Self-Service Automation_ terkendali yang mentransformasi tim Supeng dari model kerja reaktif menjadi proaktif berbasis data.

## 2. Updated Tech Stack & Tooling

```
+-----------------------------------------------------------------------------------+
|                                  USER / SUPENG                                    |
+-----------------------------------------------------------------------------------+
                                          |
                                          v Browser (HTTPS / ZeroTier Network)
+-----------------------------------------------------------------------------------+
|                           BUDIBASE (Front-End Presentation)                       |
|  - Data Sources: Built-in Data Tables (Caching layer for master_loc.csv)          |
|  - UI Elements: Dynamic Table Blocks, Search Filter, Trigger Action Buttons      |
|  - Variables: Runtime Bindings ({{ Row.IP_Address }})                             |
+-----------------------------------------------------------------------------------+
                                          |
                                          v API Request (POST Payload / argString via Localtunnel)
+-----------------------------------------------------------------------------------+
|                        RUNDECK OPEN SOURCE (Automation Engine)                     |
|  - Authentication: API Token (Admin privileges)                                  |
|  - Variables: Job Options (${option.target_ip})                                  |
|  - Engine Execution: Bash, Core SSH, Ansible Integration                          |
+-----------------------------------------------------------------------------------+
                                          |
                                          v Secure Tunneling (ZeroTier Virtual LAN)
+-----------------------------------------------------------------------------------+
|                             TARGET ENDPOINTS (700+ Nodes)                         |
|  - Linux Nodes / Parkee Gates (Ports: 9005 Actuator, Port 22 SSH)                 |
|  - Core Services: parkee-agent, parkee-ws, parkee-fs                              |
+-----------------------------------------------------------------------------------+
```

### Component Breakdown

- **Front-End Dashboard:** Budibase (Self-hosted via Docker Compose). Berfungsi untuk visualisasi data server, pencarian lokasi, tombol aksi penanganan, dan penyajian status eksekusi.
    
- **Orchestration Engine:** Rundeck Open Source (Community Edition). Berfungsi untuk manajemen antrean eksekusi, penyimpanan SSH Keys aman, eksekusi skrip, dan parsing argumen dinamis.
    
- **Networking Layer:** ZeroTier One. Menyediakan overlay network privat flat L2, memungkinkan Budibase dan Rundeck berkomunikasi dengan seluruh node lapangan menggunakan IP privat IP `10.70.x.x` secara aman tanpa mengekspos port ke internet publik.
    
- **Ingress Proxy (Development Loop):** LocalTunnel / Ngrok. Digunakan untuk bypass proteksi SSRF (Server-Side Request Forgery) internal pada Budibase Container dengan merutekan traffic API secara lokal melalui domain terverifikasi.
    

## 3. Data Architecture & Entity Relationship Diagram (ERD)

Untuk memfasilitasi penanganan lokasi yang dinamis (menggantikan file flat `master_loc.csv`), Budibase menggunakan tabel memori internal berkinerja tinggi sebagai caching layer. Sinkronisasi data diotomatisasi secara berkala dari master data Google Sheets via engine `deploy_parkee_gum.sh`.

### Logical Schema Definition

```
+--------------------------------------------------------------------+
|                         DATATABLE: Server_Nodes                    |
+--------------------------------------------------------------------+
| PK | id                 | UUID / Auto-increment                    |
|    | nama_lokasi        | String (e.g., "pk-xxx")           |
|    | ip_address         | String (IPv4 Format, e.g., "10.70.2.27") |
|    | cluster_region     | String (e.g., "Jakarta-Barat")           |
|    | status_terakhir    | String (e.g., "ONLINE", "OFFLINE")       |
|    | versi_ws           | String (e.g., "1.4.2")                   |
|    | updated_at         | DateTime                                 |
+--------------------------------------------------------------------+
                                  |
                                  | 1
                                  |
                                  | N
+--------------------------------------------------------------------+
|                         DATATABLE: Execution_Logs                  |
+--------------------------------------------------------------------+
| PK | log_id             | UUID                                     |
| FK | node_id            | UUID                                     |
|    | executed_by        | String (User Email / Username)           |
|    | action_type        | String (e.g., "CHECK_WS", "REDEPLOY")    |
|    | execution_status   | String (e.g., "SUCCESS", "FAILED")       |
|    | raw_response       | Long Text / JSON Blob                    |
|    | timestamp          | DateTime                                 |
+--------------------------------------------------------------------+
```

## 4. Automation Workflow & API Payload Specifications

### 4.1 Check WS Version Workflow

Mengambil metadata versi internal dari service running tanpa mematikan aplikasi.

- **HTTP Method:** `POST`
    
- **Endpoint:** `https://<localtunnel-domain>/api/42/job/5c156448-8fcc-4682-877c-3923673eb989/run`
    
- **Headers:**
    
    HTTP
    
    ```
    X-Rundeck-Auth-Token: <ADMIN_API_TOKEN_VALUE>
    Content-Type: application/json
    ```
    

```
*   **Request Body:**
    ```json
    {
      "argString": "-target_ip {{ target_ip }}"
    }
```

- **Rundeck Node Execution Script (`exec`):**
    
    Bash
    
    ```
    curl -s --connect-timeout 3 http://${option.target_ip}:9005/actuator/info | jq -r '.build.version // "Unknown"' || echo "WS Offline"
    ```
    

```

### 4.2 Full Redeployment Pipeline (Stop -> Clear Cache -> Start -> Validate)
Eksekusi terurut untuk perbaikan service macet atau pembaruan konfigurasi.

*   **HTTP Method:** `POST`
*   **Endpoint:** `https://<localtunnel-domain>/api/42/job/<REDEPLOY_JOB_UUID>/run`
*   **Request Body:**
    ```json
{
  "argString": "-target_ip {{ target_ip }}"
}
```

- **Rundeck Step-by-Step Workflow Implementation:**
    
    - **Step 1 (Stop Service):** SSH to target node.
        

ssh -o StrictHostKeyChecking=no admin@${option.target_ip} "sudo systemctl stop parkee-agent"

```
    *   **Step 2 (Clear Temp Cache):**
        ```bash
        ssh -o StrictHostKeyChecking=no admin@${option.target_ip} "rm -rf /opt/app/agent/parkee-agent/tmp/*"
```

```
*   **Step 3 (Start Service):**
    ```bash
```

ssh -o StrictHostKeyChecking=no admin@${option.target_ip} "sudo systemctl start parkee-agent"

```
    *   **Step 4 (Automated Health Validation Pipeline - Asynchronous Wait 10s):**
        ```bash
        sleep 10
        echo "=== RUNNING AUTOMATED POST-DEPLOYMENT HEALTH CHECK ==="
        
        # 1. Systemd State Verification
        STATE=$(ssh -o StrictHostKeyChecking=no admin@${option.target_ip} "systemctl is-active parkee-agent")
        if [ "$STATE" != "active" ]; then
            echo "[FAILED] Systemd state is: $STATE"
            exit 1
        fi
        echo "[SUCCESS] Systemd state: Active"

        # 2. HTTP Actuator Health Verification
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 http://${option.target_ip}:9005/actuator/health)
        if [ "$HTTP_CODE" != "200" ]; then
            echo "[FAILED] App health endpoint returned HTTP $HTTP_CODE"
            exit 1
        fi
        echo "[SUCCESS] App Health: HTTP 200 OK"

        # 3. Critical Log Scanner
        EXCEPTIONS=$(ssh -o StrictHostKeyChecking=no admin@${option.target_ip} "tail -n 50 /var/log/parkee/parkee-agent.log | grep -Ei 'Exception|Error'")
        if [ ! -z "$EXCEPTIONS" ]; then
            echo "[WARNING] Deployment active but critical errors found in log:"
            echo "$EXCEPTIONS"
            exit 0
        fi
        echo "[SUCCESS] Log Scanner: No critical exceptions found."
        echo "=== [SUCCESS] DEPLOYMENT SUCCESS AND STABLE ==="
```

## 5. Development & Deployment Plan

Implementasi dibagi menjadi 4 sprint terukur untuk meminimalkan gangguan pada operasional lapangan yang sedang berjalan.

```
+-----------------------------------------------------------------------+
| SPRINT 1: Infrastructure Stabilization (Week 1)                        |
| - Configure Budibase Docker Environment with ALLOW_PRIVATE_IPS         |
| - Map ZeroTier endpoints inside Automation Network                    |
+-----------------------------------------------------------------------+
                                   |
                                   v
+-----------------------------------------------------------------------+
| SPRINT 2: Rundeck Core Job Refactoring (Week 2)                       |
| - Convert hardcoded inline Bash scripts into Tokenized Options        |
| - Configure Admin-level ACL Policies for secure REST API access       |
+-----------------------------------------------------------------------+
                                   |
                                   v
+-----------------------------------------------------------------------+
| SPRINT 3: Integration & Pipeline Binding (Week 3)                     |
| - Create Budibase internal data cache layers                          |
| - Bind Table Rows UI execution triggers to Rundeck POST APIs          |
+-----------------------------------------------------------------------+
                                   |
                                   v
+-----------------------------------------------------------------------+
| SPRINT 4: Validation Engine & Rollout (Week 4)                        |
| - Deploy 10-second automated diagnostic validation post-deployment    |
| - Onboard team Supeng to GASAK Web UI                                 |
+-----------------------------------------------------------------------+
```

### Phase Details

#### Sprint 1: Infrastructure Stabilization & Core Fixes

- Mengonfigurasi `docker-compose.yaml` untuk Budibase agar mengenali variabel lingkungan bypass IP privat secara permanen.
    
- Memastikan routing container `bbapps` dan `bbworker` dapat menjangkau port localtunnel secara konsisten tanpa terblokir sistem keamanan SSRF.
    
- Memasukkan seluruh node target ke dalam satu network ID ZeroTier.
    

#### Sprint 2: Rundeck Core Job Refactoring

- Mengubah seluruh script hardcoded (seperti IP `10.70.2.27`) menjadi parameter tokenized `$option.target_ip`.
    
- Menerapkan penamaan parameter standardisasi `argString` agar mematuhi spesifikasi OpenAPI dari Rundeck.
    
- Membuat API Token khusus dengan akses Role `admin` guna menghindari error `403 Unauthorized`.
    

#### Sprint 3: Front-End UI Construction & API Binding

- Mendesain antar muka web di Budibase menggunakan Slate Dark Theme.
    
- Membuat tabel data internal untuk manajemen visual 700+ IP Lokasi dengan tambahan.
    
- Menghubungkan Event Action `Execute Query` pada komponen button di dalam tabel row untuk menyuntikkan data `{{ Row.IP_Address }}` ke API Target.
    

#### Sprint 4: Automated Validation Engine & Field Production Test

- Menggabungkan 3 parameter cek kesehatan otomatis (Systemd, Actuator Health HTTP, dan Log Scanner `tail -50`) ke dalam pipeline pasca-deploy.
    
- Melakukan uji coba parsial pada 10 gerbang produksi sebagai sampel validasi.
    
- Serah terima sistem kepada tim Supeng untuk eliminasi penggunaan terminal SSH manual.
    

## 6. Business Impact, Root Cause Mitigation & Operational Flow

### Root Cause Analysis (Masalah Lama vs Solusi GASAK Phase 2)

- **Akar Masalah Operasional:** Kegagalan atau lambatnya penanganan isu di lapangan disebabkan oleh tim penangan lini pertama yang terjebak dalam proses diagnostik manual yang repetitif (harus login SSH, navigasi folder, mengetik perintah monitoring log, dan melakukan pengecekan berulang). Hal ini berpotensi memicu kesalahan pengetikan command destruktif seperti `rm -rf` pada direktori aktif atau kekeliruan mematikan Process ID (`kill -9`) pada server produksi yang salah.
    
- **Mitigasi GASAK Phase 2:** Logika eksekusi sepenuhnya diabstraksikan ke dalam kode terenkapsulasi di dalam Rundeck. Budibase mengeliminasi kebutuhan input manual command oleh user, mengubah seluruh proses intervensi manual menjadi transaksi terstandardisasi yang aman (_safe transactional action_).
    

### Operational Flow (The New Supeng Experience)

1. **Deteksi:** Tiket kendala masuk ke sistem antrean Support.
    
2. **Identifikasi:** Supeng membuka Portal GASAK Web Version, menggunakan fitur filter pencarian global untuk menemukan nama lokasi target (misal: "Pk/Pm xxx").
    
3. **Diagnostik Awal:** Supeng menekan tombol `Check WS`. Sistem merutekan request via API, memanggil Rundeck, mengecek status endpoint, dan menampilkan status kesehatan real-time di UI dalam hitungan detik.
    
4. **Eksekusi Solusi:** Jika ditemukan anomali atau versi tidak sesuai, Supeng menekan tombol `GASAK Redeploy`. Sistem secara sekuensial menghentikan layanan, membersihkan cache, memulai ulang aplikasi, dan melakukan pengujian otomatis 10 detik.
    
5. **Konformasi:** Hasil validasi pipa diagnostik (Success/Failed) dimunculkan sebagai output visual di browser. Masalah selesai tanpa membuka terminal CLI.
    

### Impact Metrics Matrix

|**Metrik Kinerja**|**Sebelum GASAK Phase 2 (OliveTin / Manual)**|**Sesudah GASAK Phase 2 (Budibase + Rundeck)**|
|---|---|---|
|**Waktu Eksekusi Patch/Hotfix**|10 – 15 Menit per server (Manual SSH login)|15 Detik (Sekali Klik via API Automation)|
|**Risiko Human Error / Typo**|Tinggi (Akses terminal langsung dengan hak sudo)|0% (Command terkunci di sistem backend)|
|**Kecepatan Diagnostik Kesehatan**|3 - 5 Menit (Manual curl & parsing log)|< 3 Detik (Otomatisasi parsing JSON Actuator)|
|**Audit Log & Akuntabilitas**|Tidak ada histori terpusat penanganan|Tercatat penuh (User, Waktu, Lokasi, Output)|

## 7. Financial & Capacity Planning (Budget Optimization)

Arsitektur yang dirancang mengedepankan efisiensi biaya dengan memanfaatkan skema Open Source Self-Hosted secara optimal guna menghindari pengeluaran lisensi enterprise berlebih.

### Infrastructure & Software Licensing Breakdown

| **Komponen**          | **Spesifikasi / Plan**                                             | **Estimasi Biaya Bulanan**                                                | **Keterangan**                                                                                                                                   |
| --------------------- | ------------------------------------------------------------------ | ------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------ |
| **Budibase Engine**   | Open Source Community Plan (Self-hosted)                           | $0.00 (Gratis)                                                            | Unlimited Users, Unlimited Apps, Unlimited Internal Data Tables. Tidak memerlukan upgrade ke Premium Plan selama di-host mandiri di infra lokal. |
| **Rundeck Engine**    | Open Source Community Edition (Self-hosted)                        | $0.00 (Gratis)                                                            | Fitur ACL, Option Variables, dan Webhook REST API sudah mencukupi untuk kebutuhan otomatisasi internal tim.                                      |
| **ZeroTier Network**  | Built In Company                                                   | $0.00 (Gratis)                                                            | Built In network tools dari perusahaan untuk menjadi base layer network bagi ekosistem GASAK                                                     |
| **Compute Resources** | 1x Dedicated Virtual Machine (Ubuntu Server LTS, 4 vCPU, 8 GB RAM) | Dioptimalkan menggunakan resource server internal internal yang sudah ada | Digunakan untuk menampung container runtime Budibase, instance Rundeck, dan localtunnel service runner.                                          |
| **Total Estimasi**    | **Sistem Mandiri Terpusat**                                        | **Rp 0,- / Bulan**                                                        | **Efisiensi Finansial Maksimal**                                                                                                                 |

### Proyeksi Kebutuhan Upgrade Masa Depan

Jika skala node lapangan berkembang melampaui batas arsitektur dasar, berikut estimasi penyesuaian yang dapat dilakukan tanpa mengorbankan stabilitas sistem:

- **Budibase Enterprise Feature:** Upgrade ke Cloud/Enterprise Plan hanya dibutuhkan jika perusahaan mewajibkan fitur integrasi Single Sign-On (SSO) tingkat lanjut berbasis SAML/OIDC atau audit log kepatuhan korporasi skala besar. Selama kebutuhan hanya berfokus pada efisiensi kerja internal tim Supeng, versi Community Edition sangat andal dan aman untuk dipertahankan.