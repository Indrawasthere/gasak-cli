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
            "authorization": f"Bearer {token}",
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


TOKEN_CACHE_PATH = Path.home() / ".parkee_token.json"
CACHE_MAX_DAYS = 30


def load_saved_token(max_age_days=CACHE_MAX_DAYS):
    try:
        if not TOKEN_CACHE_PATH.exists():
            return None
        with open(TOKEN_CACHE_PATH, "r", encoding="utf-8") as fh:
            obj = json.load(fh)
        token = obj.get("token")
        saved_at = int(obj.get("saved_at", 0))
        if not token:
            return None
        age = time.time() - saved_at
        if age <= max_age_days * 86400:
            return token
        # expired
        try:
            TOKEN_CACHE_PATH.unlink()
        except Exception:
            pass
        return None
    except Exception:
        return None


def save_token(token):
    try:
        TOKEN_CACHE_PATH.write_text(
            json.dumps({"token": token, "saved_at": int(time.time())}), encoding="utf-8"
        )
        try:
            TOKEN_CACHE_PATH.chmod(0o600)
        except Exception:
            pass
    except Exception:
        pass


def clear_saved_token():
    try:
        if TOKEN_CACHE_PATH.exists():
            TOKEN_CACHE_PATH.unlink()
    except Exception:
        pass


# Fungsi untuk mencetak garis sepanjang layar
def print_line(width):
    print("=" * width)


# Fungsi untuk mencetak teks rata tengah
def print_center(text, width):
    print(text.center(width))


parser = argparse.ArgumentParser(
    description="Script Decode / Melihat Detail Data Payment"
)
parser.add_argument(
    "--clear-token",
    action="store_true",
    help="Hapus token cache yang tersimpan dan keluar",
)
args = parser.parse_args()

if args.clear_token:
    clear_saved_token()
    print("[*] Token cache dihapus. Jalankan ulang script untuk memasukkan token baru.")
    sys.exit(0)


def safe_input(prompt):
    """Wrapper input() yang handle Ctrl+C dan Ctrl+D dengan clean exit signal."""
    try:
        return input(prompt).strip()
    except KeyboardInterrupt:
        raise KeyboardInterrupt
    except EOFError:
        raise EOFError


def run_decode_session():
    # Mendapatkan lebar terminal pengguna secara realtime
    terminal_width = shutil.get_terminal_size(fallback=(80, 24)).columns

    # ==========================================
    # MENAMPILKAN FORM
    # ==========================================
    print_line(terminal_width)
    print_center("Settlement Decode — Parkee GASAK", terminal_width)
    print_line(terminal_width)

    # 1. Ambil atau minta API Token (disimpan sampai 30 hari)
    TOKEN = load_saved_token()
    if TOKEN:
        print("[*] Menggunakan token yang tersimpan (maks. 30 hari).")
        print("[*] Ketik 'ganti' kalau mau ganti token.")
        maybe = safe_input("Token [enter untuk lanjut / ketik 'ganti']: ").lower()
        if maybe == "ganti":
            clear_saved_token()
            TOKEN = None

    if not TOKEN:
        while True:
            TOKEN = safe_input("Masukkan API Token atau CTRL + D buat cancel men: ")
            if not TOKEN:
                print("❌ Error: API Token tidak boleh kosong. Coba lagi.")
                continue
            break
        save_token(TOKEN)
        print("[*] Token disimpan untuk penggunaan selanjutnya (maks. 30 hari).")
    print_line(terminal_width)

    # 2. Prompt untuk Location ID (hanya angka)
    while True:
        location_id = safe_input("Masukkan Location ID (hanya angka): ")
        if not location_id:
            print("❌ Error: Location ID tidak boleh kosong.")
            continue
        if not location_id.isdigit():
            print("❌ Error: Location ID harus berupa angka saja. Silakan coba lagi.")
            continue
        break

    # 3. Prompt untuk External IDs
    raw_external_ids = safe_input(
        "Masukkan External ID (pisahkan dengan koma, contoh: 123, 456, 789): "
    )

    # Membersihkan dan memisahkan input External ID
    external_ids = [eid.strip() for eid in raw_external_ids.split(",") if eid.strip()]

    if not external_ids:
        print("❌ Error: External ID tidak valid atau kosong.")
        return

    # Batasan Agar Rapih Di Terminal
    print_line(terminal_width)

    print(f"\nMenyiapkan penarikan data untuk Location ID: {location_id}")
    print(f"Total antrean External ID: {len(external_ids)}\n")

    results = []

    # 4. Looping request API
    for external_id in external_ids:
        print(f"Processing External ID {external_id}...", end=" ")

        try:
            data = fetch_decode_data(API_URL, TOKEN, location_id, external_id)
            results.append(data)
            print("✅ Sukses")
        except Exception as e:
            print(f"❌ Gagal ({e})")

    # Batasan Agar Rapih Di Terminal
    print_line(terminal_width)

    # 5. Export ke file JSON dengan nama sesuai Location ID
    safe_location_id = sanitize_filename(location_id)
    output_file = f"merged_results_{safe_location_id}.json"

    with open(output_file, "w") as f:
        json.dump(results, f, indent=2)

    print(
        f"\n✅ Proses selesai! File '{output_file}' berhasil dibuat dengan {len(results)} record valid."
    )
    print_line(terminal_width)


def main():
    while True:
        try:
            run_decode_session()
        except (KeyboardInterrupt, EOFError):
            # Ctrl+C atau Ctrl+D di tengah sesi — jangan kabur ke terminal
            terminal_width = shutil.get_terminal_size(fallback=(80, 24)).columns
            print()
            print_line(terminal_width)
            print("  [!] Sesi di-interrupt.")
            print_line(terminal_width)

        # ── Post-session menu ──────────────────────────────────
        terminal_width = shutil.get_terminal_size(fallback=(80, 24)).columns
        print()
        print("  Mau ngapain lagi men?")
        print("  [1] Decode lagi")
        print("  [2] Balik ke GASAK")
        print()

        try:
            choice = safe_input("  Pilihan (1/2): ")
        except (KeyboardInterrupt, EOFError):
            # Ctrl+C atau Ctrl+D pas di menu — exit clean ke GASAK
            print()
            print("  Takecare men...")
            sys.exit(0)

        if choice == "1":
            print()
            continue
        else:
            print()
            print("  Takecare men...")
            sys.exit(0)


if __name__ == "__main__":
    main()
