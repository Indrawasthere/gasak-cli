#!/usr/bin/env python3
import csv
import os
import re
import subprocess
import sys
from urllib.parse import urlparse


# ==========================================
# 0. Auto-Install Dependencies (Windows Ready)
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
                    f"[!] Gagal menginstal {pip_name}. Silakan install manual: python -m pip install {pip_name}"
                )
                sys.exit(1)


check_and_install_packages()

# ==========================================
# 1. Import Library Utama & Konfigurasi
# ==========================================
import shutil

import psycopg2
import requests

DB_HOST = os.environ.get("CMS_DB_HOST", "")
DB_PORT = os.environ.get("CMS_DB_PORT", "5432")
DB_USER = os.environ.get("CMS_DB_USER", "")
DB_PASSWORD = os.environ.get("CMS_DB_PASS", "")
DB_NAME = os.environ.get("CMS_DB_NAME", "")


# ─── UTILITIES UI ─────────────────────────────────────────────
def print_line(width):
    print("═" * width)


def print_center(text, width):
    print(text.center(width))


def clear_screen():
    # Menyesuaikan perintah clear screen antara Windows (cls) dan Linux (clear)
    os.system("cls" if os.name == "nt" else "clear")


# ─── LOGIC CORE ───────────────────────────────────────────────
def get_query_compare():
    return """
        SELECT
            id, location_id, external_id, amount,
            settlement_status, created_at, updated_at
        FROM cloud_settlement_payment
        WHERE settlement_status = 'STI_REMAPPING_PENDING'
        ORDER BY created_at DESC;
    """


def get_query_fs():
    return """
        SELECT
            id, location_id, external_id, amount,
            settlement_status, created_at, updated_at
        FROM cloud_settlement_payment
        WHERE settlement_status = 'PENDING' AND rfs_status IS NULL
        ORDER BY created_at DESC;
    """


def run_task_compare(cursor):
    terminal_width = shutil.get_terminal_size(fallback=(80, 24)).columns
    print_line(terminal_width)
    print("[*] Mengambil data STI REMAPPING PENDING...")

    try:
        cursor.execute(get_query_compare())
        rows = cursor.fetchall()

        if not rows:
            print("[+] Tidak ada data dengan status STI_REMAPPING_PENDING.")
            return

        filename = "settlement_compare_sti_pending.csv"
        # Ditambahkan encoding='utf-8' dan newline='' agar aman di Windows
        with open(filename, mode="w", newline="", encoding="utf-8") as f:
            writer = csv.writer(f)
            writer.writerow(
                [
                    "ID",
                    "Location ID",
                    "External ID",
                    "Amount",
                    "Status",
                    "Created At",
                    "Updated At",
                ]
            )
            writer.writerows(rows)

        print(f"[+] Berhasil mengexport {len(rows)} data ke file: {filename}")
    except Exception as e:
        print(f"[x] Error saat menjalankan Task 1: {e}")


def run_task_fs(cursor):
    terminal_width = shutil.get_terminal_size(fallback=(80, 24)).columns
    print_line(terminal_width)
    print("[*] Mengambil data Pending Settlement STI (No RFS)...")

    try:
        cursor.execute(get_query_fs())
        rows = cursor.fetchall()

        if not rows:
            print("[+] Tidak ada data Pending Settlement tanpa RFS.")
            return

        filename = "settlement_pending_no_rfs.csv"
        # Ditambahkan encoding='utf-8' dan newline='' agar aman di Windows
        with open(filename, mode="w", newline="", encoding="utf-8") as f:
            writer = csv.writer(f)
            writer.writerow(
                [
                    "ID",
                    "Location ID",
                    "External ID",
                    "Amount",
                    "Status",
                    "Created At",
                    "Updated At",
                ]
            )
            writer.writerows(rows)

        print(f"[+] Berhasil mengexport {len(rows)} data ke file: {filename}")
    except Exception as e:
        print(f"[x] Error saat menjalankan Task 2: {e}")


# ─── MAIN MENU ───────────────────────────────────────────────
def main():
    terminal_width = shutil.get_terminal_size(fallback=(80, 24)).columns

    if not DB_HOST or not DB_USER or not DB_PASSWORD or not DB_NAME:
        print_line(terminal_width)
        print("[!] Environment variable database belum lengkap men!")
        print(
            "[!] Pastikan CMS_DB_HOST, CMS_DB_USER, CMS_DB_PASS, dan CMS_DB_NAME terisi."
        )
        print_line(terminal_width)
        sys.exit(1)

    conn = None
    try:
        print("[*] Connecting ke database CMS Parkee...")
        conn = psycopg2.connect(
            host=DB_HOST,
            port=DB_PORT,
            user=DB_USER,
            password=DB_PASSWORD,
            database=DB_NAME,
        )
        cursor = conn.cursor()
        print("[+] Database connected successfully!")

        while True:
            clear_screen()
            terminal_width = shutil.get_terminal_size(fallback=(80, 24)).columns

            print_line(terminal_width)
            print_center("GASAK SETTLEMENT MODULE FOR WINDOWS", terminal_width)
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

            try:
                pilihan = input(
                    "\nMasukkan pilihan (1/2/3) atau CTRL + C buat cancel men: "
                ).strip()
            except (KeyboardInterrupt, EOFError):
                print("\n[*] Sesi dibatalkan oleh user. Bye men!")
                break

            if pilihan == "1":
                run_task_compare(cursor)
                input("\nTekan ENTER untuk kembali ke menu...")
            elif pilihan == "2":
                run_task_fs(cursor)
                input("\nTekan ENTER untuk kembali ke menu...")
            elif pilihan == "3":
                print("[*] Keluar dari program, take care men!")
                break
            else:
                print("[!] Pilihan tidak valid men. Silakan pilih 1, 2, atau 3.\n")
                time.sleep(2)

    except psycopg2.Error as e:
        print(f"\n[!] Database Error: {e}")
    except Exception as e:
        print(f"\n[!] Unexpected Error: {e}")
    finally:
        if conn:
            cursor.close()
            conn.close()
            print("[*] Koneksi database ditutup.")
            print_line(terminal_width)


if __name__ == "__main__":
    main()
