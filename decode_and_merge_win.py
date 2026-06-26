#!/usr/bin/env python3
import argparse
import json
import os
import shutil
import sys
import time
import urllib.request
from pathlib import Path

API_URL = "https://ms.parkee.app/cloud-settlement/v1/cloud-settlement-payment/decode"


def sanitize_filename(value, fallback="unknown_location"):
    safe_value = "".join(c for c in value if c.isalnum() or c in ("-", "_")).strip()
    return safe_value or fallback


def fetch_decode_data(api_url, token, location_id, external_id):
    payload = json.dumps(
        {
            "locationId": location_id,
            "externalId": external_id,
        }
    ).encode("utf-8")

    req = urllib.request.Request(
        api_url,
        data=payload,
        headers={
            "Content-Type": "application/json",
            "authorization": f"Bed-head Bearer {token}",
        },
        method="POST",
    )

    with urllib.request.urlopen(req, timeout=30) as resp:
        payload_resp = resp.read().decode("utf-8")
        data = json.loads(payload_resp)
        if not isinstance(data, dict):
            raise ValueError("Respon API tidak berbentuk JSON objek yang valid")
        data["externalId"] = external_id
        return data


# Di Windows, Path.home() mengarah otomatis ke C:\Users\<Username>
TOKEN_CACHE_PATH = Path.home() / ".parkee_token.json"
CACHE_MAX_DAYS = 30


def load_saved_token(max_age_days=CACHE_MAX_DAYS):
    try:
        if not TOKEN_CACHE_PATH.exists():
            return None

        # Open dengan encoding utf-8 agar aman dari default Windows encoding
        with open(TOKEN_CACHE_PATH, "r", encoding="utf-8") as f:
            cached = json.load(f)

        mtime = TOKEN_CACHE_PATH.stat().st_mtime
        age_days = (time.time() - mtime) / (24 * 3600)

        if age_days < max_age_days and "token" in cached:
            return cached["token"]
    except Exception:
        pass
    return None


def save_token(token):
    try:
        with open(TOKEN_CACHE_PATH, "w", encoding="utf-8") as f:
            json.dump({"token": token, "saved_at": time.time()}, f)
    except Exception:
        pass


def print_line(width):
    print("═" * width)


def safe_input(prompt=""):
    val = input(prompt)
    if val.strip().lower() in ("exit", "quit"):
        print("  Takecare men...")
        sys.exit(0)
    return val


def run_decode_session():
    terminal_width = shutil.get_terminal_size(fallback=(80, 24)).columns
    print_line(terminal_width)
    print(" 🔓 PARKEE DATA DECODER & MERGER MODULE (Windows Version)")
    print_line(terminal_width)

    # 1. Token Setup
    token = load_saved_token()
    if token:
        print("  [+] Menggunakan cached Bearer token yang tersimpan.")
    else:
        print("  [!] Token belum ada atau expired.")
        token = safe_input("  Masukkan Bearer Token baru: ").strip()
        if not token:
            print("  [x] Token tidak boleh kosong men!")
            return
        save_token(token)

    print()
    location_id = safe_input("  Masukkan Location ID: ").strip()
    if not location_id:
        print("  [x] Location ID wajib diisi!")
        return

    print()
    print("  Masukkan list External ID (Satu per baris).")
    print("  Kalau udah selesai input, tekan ENTER sekali lagi pada baris kosong.")
    print_line(terminal_width)

    external_ids = []
    while True:
        line = safe_input(f"  [{len(external_ids) + 1}] External ID: ").strip()
        if not line:
            break
        external_ids.append(line)

    if not external_ids:
        print("  [!] Gak ada External ID yang lo masukin. Sesi dibatalkan.")
        return

    print_line(terminal_width)
    print(f"  [*] Memulai proses decode untuk {len(external_ids)} item...")
    print_line(terminal_width)

    results = []
    success_count = 0
    fail_count = 0

    for idx, ext_id in enumerate(external_ids, 1):
        print(
            f"  [{idx}/{len(external_ids)}] Processing: {ext_id} -> ",
            end="",
            flush=True,
        )
        try:
            data = fetch_decode_data(API_URL, token, location_id, ext_id)
            results.append(data)
            print("✅ SUCCESS")
            success_count += 1
        except Exception as e:
            print(f"❌ FAILED ({e})")
            fail_count += 1
        time.sleep(0.5)  # Throttle agar aman dari rate limit

    print_line(terminal_width)
    print(f"  Hasil Akhir -> Sukses: {success_count} | Gagal: {fail_count}")

    if not results:
        print("  [x] Gak ada data yang berhasil didécode. File tidak dibuat.")
        return

    # 2. Save Merged Results
    safe_location_id = sanitize_filename(location_id)
    output_file = f"merged_results_{safe_location_id}.json"

    with open(output_file, "w", encoding="utf-8") as f:
        json.dump(results, f, indent=2)

    print(
        f"\n✅ Proses selesai! File '{output_file}' berhasil dibuat dengan {len(results)} record valid."
    )
    print_line(terminal_width)


def main():
    while True:
        try:
            # Jalankan clear screen biar rapi di awal sesi
            os.system("cls" if os.name == "nt" else "clear")
            run_decode_session()
        except (KeyboardInterrupt, EOFError):
            terminal_width = shutil.get_terminal_size(fallback=(80, 24)).columns
            print("\n")
            print_line(terminal_width)
            print("  [!] Sesi di-interrupt oleh user.")
            print_line(terminal_width)

        # ── Post-session menu ──────────────────────────────────
        terminal_width = shutil.get_terminal_size(fallback=(80, 24)).columns
        print()
        print("  Mau ngapain lagi men?")
        print("  [1] Decode lagi")
        print("  [2] Keluar")
        print()

        try:
            choice = safe_input("  Pilihan (1/2): ").strip()
        except (KeyboardInterrupt, EOFError):
            print("\n  Takecare men...")
            sys.exit(0)

        if choice == "1":
            print()
            continue
        else:
            print("  Automation completed. See ya!")
            sys.exit(0)


if __name__ == "__main__":
    main()
