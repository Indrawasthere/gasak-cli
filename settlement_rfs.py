import csv
import os
import re
import subprocess
import sys
from urllib.parse import urlparse


# ==========================================
# 0. Auto-Install Dependencies
# ==========================================
def check_and_install_packages():
    """Mengecek dan menginstal package otomatis jika belum ada"""
    packages = {"psycopg2": "psycopg2-binary", "requests": "requests"}
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

# ==========================================
# 1. Import Library Utama & Konfigurasi
# ==========================================
import os
import shutil  # Modul bawaan Python untuk mengambil ukuran terminal

import psycopg2
import requests

DB_HOST = os.environ.get("CMS_DB_HOST", "")
DB_PORT = os.environ.get("CMS_DB_PORT", "5432")
DB_USER = os.environ.get("CMS_DB_USER", "")
DB_PASSWORD = os.environ.get("CMS_DB_PASS", "")
DB_NAME = os.environ.get("CMS_DB_NAME", "")

if not all([DB_HOST, DB_USER, DB_PASSWORD, DB_NAME]):
    print(
        "❌ Error: CMS DB credentials belum di-set. Pastiin .env lu udah ada CMS_DB_HOST, CMS_DB_USER, CMS_DB_PASS, CMS_DB_NAME."
    )
    sys.exit(1)

DOWNLOAD_DIR = "downloaded_files"
REPORT_FILE = "Laporan_Eskalasi.txt"

if not os.path.exists(DOWNLOAD_DIR):
    os.makedirs(DOWNLOAD_DIR)

# ==========================================
# 2. Queries
# ==========================================
# Query untuk Task 1: Compare
QUERY_COMPARE = """
select
    distinct csh.settlement_file_url,
    csh.ok_response_url,
    csh.nok_response_url,
    csh.settlement_history_status,
    csp.settlement_status
from cloud_settlement_payment csp
left join cloud_settlement_history csh on csp.settlement_history_id = csh.id
where csp.deleted_at isnull
    and csp.settlement_type = 'STI'
    and csp.settlement_status = 'PENDING'
    and csh.settlement_history_status = 'DONE'
    and csp.transaction_date between %s and %s
group by
    csh.settlement_file_url,
    csh.ok_response_url,
    csh.nok_response_url,
    csh.settlement_history_status,
    csp.settlement_status;
"""

# Query untuk Task 2: FS (Export CSV)
QUERY_EXPORT_CSV = """
select
    distinct cast((csh.created_at at time zone 'Asia/Jakarta') as date) as uploadedDate,
    concat(csh.base_file_name, '.txt') as filename,
    csh.settlement_type as settlementType,
    csh.bank,
    count(1) as countData
from cloud_settlement_payment csp
left join cloud_settlement_history csh on csp.settlement_history_id = csh.id
where csp.deleted_at isnull
    and csp.settlement_type = 'STI'
    and csp.settlement_status = 'PENDING'
    and csh.settlement_history_status = 'UPLOAD'
    and csp.transaction_date between %s and %s
group by
     cast((csh.created_at at time zone 'Asia/Jakarta') as date),
     csh.settlement_type,
     csh.bank,
     csh.base_file_name
order by uploadedDate;
"""

# Query untuk Task 2: FS (Download URL)
QUERY_DOWNLOAD_FILES_FS = """
select
    distinct csh.settlement_file_url,
    csh.ok_response_url,
    csh.nok_response_url,
    csh.settlement_history_status
from cloud_settlement_payment csp
inner join cloud_settlement_history csh on csp.settlement_history_id = csh.id
where csp.deleted_at isnull
    and csp.settlement_type = 'STI'
    and csp.settlement_status = 'PENDING'
    and csh.settlement_history_status = 'UPLOAD'
    and csp.transaction_date between %s and %s
group by
    csh.settlement_file_url,
    csh.ok_response_url,
    csh.nok_response_url,
    csh.settlement_history_status;
"""


# ==========================================
# 3. Core Functions (Download & Utilities)
# ==========================================
def download_file(url):
    """Fungsi universal untuk mengunduh file dari URL"""
    if not url:
        return None

    try:
        parsed_url = urlparse(url)
        filename = os.path.basename(parsed_url.path) or "unknown_file.txt"
        save_path = os.path.join(DOWNLOAD_DIR, filename)

        if os.path.exists(save_path):
            print(f"[SKIP] File sudah ada: {filename}")
            return save_path

        print(f"[DOWNLOAD] Mengunduh: {filename}...")
        response = requests.get(url, stream=True, timeout=30)
        response.raise_for_status()

        with open(save_path, "wb") as file:
            for chunk in response.iter_content(chunk_size=8192):
                if chunk:
                    file.write(chunk)

        print(f"[SUCCESS] Tersimpan di {save_path}")
        return save_path

    except Exception as e:
        print(f"[FAILED] Gagal mengunduh {url}\n         Error: {e}")
        return None


def get_date_input():
    """Fungsi bantuan untuk meminta input tanggal dari user"""
    print("\n--- Filter Tanggal Transaksi ---")
    start_date = input("Masukkan Tanggal Awal (YYYY-MM-DD): ").strip()
    end_date = input("Masukkan Tanggal Akhir (YYYY-MM-DD): ").strip()
    return start_date, end_date


# ==========================================
# 4. Task 1: Download & Compare
# ==========================================
def compare_settlement_data(settlement_path, ok_path, nok_path, row_index, report_file):
    print(f"\n--- Memulai Compare Data Baris ke-{row_index} ---")

    def read_file_lines(filepath):
        if filepath and os.path.exists(filepath):
            with open(filepath, "r", encoding="utf-8", errors="ignore") as f:
                return [line.strip() for line in f.readlines() if line.strip()]
        return []

    settlement_data = read_file_lines(settlement_path)
    ok_data = read_file_lines(ok_path)
    nok_data = read_file_lines(nok_path)

    if not settlement_data:
        print("[-] Data Settlement kosong atau file gagal dibaca. Melewati compare.")
        return

    def ok_response_matches(record, ok_text):
        pattern = re.compile(
            re.escape(record) + r"\s*(?:[\|\t,;:]?\s*)?00\s*-\s*Accepted",
            re.IGNORECASE,
        )
        return bool(pattern.search(ok_text))

    ada_list, tidak_ada_list = [], []
    ok_text = "\n".join(ok_data)
    nok_text = "\n".join(nok_data)

    total_lines = len(settlement_data)

    if total_lines >= 3:
        body_data = settlement_data[1:-1]
    elif total_lines == 2:
        print(
            "[!] Peringatan: File Settlement hanya memiliki 2 baris (Header & Footer). Transaksi kosong."
        )
        body_data = []
    else:
        print(
            "[!] Peringatan: File Settlement hanya memiliki 1 baris. Transaksi kosong."
        )
        body_data = []

    for record in body_data:
        if ok_response_matches(record, ok_text) or record in nok_text:
            ada_list.append(record)
        else:
            tidak_ada_list.append(record)

    with open(report_file, "a", encoding="utf-8") as rep:
        rep.write(f"=== HASIL COMPARE BARIS KE-{row_index} ===\n")
        rep.write(f"File Settlement : {settlement_path}\n")
        rep.write(f"Total Baris File: {total_lines} (Termasuk Header & Footer)\n")
        rep.write(f"Total Data Transaksi (Body): {len(body_data)} baris\n\n")

        if tidak_ada_list:
            msg = f"[STATUS: TIDAK ADA / FORMAT INVALID] Ditemukan {len(tidak_ada_list)} data di Settlement yang TIDAK COCOK dengan file Response.\n>> ACTION: Eskalasi ke Pihak External (STI).\n"
            print(msg)
            rep.write(msg)
            rep.write("Sample Data yang hilang / invalid (Max 5):\n")
            for item in tidak_ada_list[:5]:
                rep.write(f" - {item}\n")
        else:
            if len(body_data) > 0:
                msg = f"[STATUS: ADA] Semua ({len(ada_list)}) data transaksi Settlement valid & diterima (00 - Accepted).\n>> ACTION: Eskalasi Tim Internal.\n"
            else:
                msg = "[STATUS: KOSONG] Tidak ada data transaksi untuk dicompare.\n"
            print(msg)
            rep.write(msg)
        rep.write("\n==========================================\n\n")


def run_task_compare(cursor):
    start_date, end_date = get_date_input()
    if not start_date or not end_date:
        print("Error: Tanggal harus diisi!")
        return

    if os.path.exists(REPORT_FILE):
        os.remove(REPORT_FILE)

    print(f"\n[*] Menjalankan query Task Compare ({start_date} s/d {end_date})...")
    cursor.execute(QUERY_COMPARE, (start_date, end_date))
    records = cursor.fetchall()

    if not records:
        print("[-] Tidak ada data ditemukan untuk parameter tanggal tersebut.")
        return

    print(f"[+] Ditemukan {len(records)} baris data.\n")

    for index, row in enumerate(records):
        row_idx = index + 1
        print(f"\n[{row_idx}/{len(records)}] --- Proses Unduh File ---")
        path_settlement = download_file(row[0])
        path_ok = download_file(row[1])
        path_nok = download_file(row[2])

        compare_settlement_data(
            path_settlement, path_ok, path_nok, row_idx, REPORT_FILE
        )

    print(f"\n[*] Proses Selesai! Rangkuman eskalasi: {REPORT_FILE}")


# ==========================================
# 5. Task 2: Download FS & Export CSV
# ==========================================
def run_task_fs(cursor):
    start_date, end_date = get_date_input()
    if not start_date or not end_date:
        print("Error: Tanggal harus diisi!")
        return

    csv_filename = f"data_settlement_pending_{start_date}_{end_date}.csv"

    # 1. Export CSV
    print("\n[*] Menjalankan query Export CSV...")
    cursor.execute(QUERY_EXPORT_CSV, (start_date, end_date))
    records_csv = cursor.fetchall()

    if records_csv:
        col_names = [desc[0] for desc in cursor.description]
        with open(csv_filename, "w", newline="", encoding="utf-8") as f:
            writer = csv.writer(f)
            writer.writerow(col_names)
            writer.writerows(records_csv)
        print(
            f"[SUCCESS] Berhasil export {len(records_csv)} baris ke '{csv_filename}'."
        )
    else:
        print("[-] Tidak ada data ditemukan untuk Export CSV.")

    # 2. Download Files
    print("\n[*] Menjalankan query URL Download FS...")
    cursor.execute(QUERY_DOWNLOAD_FILES_FS, (start_date, end_date))
    records_dl = cursor.fetchall()

    if not records_dl:
        print("[-] Tidak ada data link ditemukan untuk di-download.")
        return

    print(f"[+] Total data link ditemukan: {len(records_dl)}")
    for idx, row in enumerate(records_dl, start=1):
        print(f"\n--- Memproses Record [{idx}/{len(records_dl)}] ---")
        download_file(row[0])
        download_file(row[1])
        download_file(row[2])

    print("\n[*] Proses Download FS & Export CSV Selesai!")


# ==========================================
# 6. Main Flow & Menu System
# ==========================================
# Fungsi untuk mencetak garis sepanjang layar
def print_line(width):
    print("=" * width)


# Fungsi untuk mencetak teks rata tengah
def print_center(text, width):
    print(text.center(width))


def main():
    conn = None
    try:
        print("[*] Menghubungkan ke database PostgreSQL...")
        conn = psycopg2.connect(
            host=DB_HOST,
            port=DB_PORT,
            user=DB_USER,
            password=DB_PASSWORD,
            dbname=DB_NAME,
        )
        cursor = conn.cursor()
        print("[+] Koneksi database berhasil!\n")

        while True:
            # Mendapatkan lebar terminal pengguna secara realtime
            # Fallback 80 adalah ukuran default jika gagal mendeteksi
            terminal_width = shutil.get_terminal_size(fallback=(80, 24)).columns

            # ==========================================
            # MENAMPILKAN MENU
            # ==========================================
            print_line(terminal_width)
            print_center("PILIH TASK SETTLEMENT ENGINE", terminal_width)
            print_line(terminal_width)
            print_center(
                "1. Download & Compare Data Settlement STI REMAPPING PENDING",
                terminal_width,
            )
            print_center(
                "2. Download FS & Export CSV Pending Settlement STI, Not Have RFS",
                terminal_width,
            )
            print_center("3. Keluar", terminal_width)
            print_line(terminal_width)

            # Input user
            pilihan = input(
                "\nMasukkan pilihan (1/2/3) atau CTRL + D buat cancel men: "
            ).strip()

            if pilihan == "1":
                # run_task_compare(cursor) # Pastikan fungsi ini sudah Anda buat
                print("[*] Menjalankan Task 1...")
                run_task_compare(cursor)
            elif pilihan == "2":
                # run_task_fs(cursor)      # Pastikan fungsi ini sudah Anda buat
                print("[*] Menjalankan Task 2...")
                run_task_fs(cursor)
            elif pilihan == "3":
                print("[*] Keluar dari program. Terima kasih!")
                break
            else:
                print("[!] Pilihan tidak valid. Silakan pilih 1, 2, atau 3.\n")

    except psycopg2.Error as e:
        print(f"\n[!] Database Error: {e}")
    except Exception as e:
        print(f"\n[!] Unexpected Error: {e}")
    finally:
        if conn:
            cursor.close()
            conn.close()
            print("[*] Koneksi ditutup.")
            print_line(terminal_width)


if __name__ == "__main__":
    main()
