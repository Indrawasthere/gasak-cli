#!/usr/bin/env python3
"""
Parkee Log Cutter - Modern UI Edition
"""

import os
import re
import shutil
import threading
import tkinter as tk
from datetime import datetime
from pathlib import Path
from tkinter import filedialog, messagebox, ttk


class ModernLogKeeper:
    """Parkee Log Cutter"""

    TIMESTAMP_PATTERNS = {
        "default": r"\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}",
        "iso": r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}",
        "compact": r"\d{4}\d{2}\d{2} \d{2}:\d{2}:\d{2}",
        "slash": r"\d{2}/\d{2}/\d{4} \d{2}:\d{2}:\d{2}",
    }

    def __init__(self):
        self.root = tk.Tk()
        self.root.title("Log Cutter • UI Version")
        self.root.geometry("1000x700")
        self.root.minsize(900, 600)

        # Color palette (Tailwind-inspired)
        self.colors = {
            "bg": "#0f172a",  # slate-900
            "surface": "#1e293b",  # slate-800
            "surface2": "#334155",  # slate-700
            "accent": "#3b82f6",  # blue-500
            "accent_hover": "#2563eb",
            "success": "#10b981",  # emerald-500
            "warning": "#f59e0b",  # amber-500
            "error": "#ef4444",  # red-500
            "text": "#f1f5f9",  # slate-100
            "text_secondary": "#94a3b8",
            "border": "#334155",
        }

        self.root.configure(bg=self.colors["bg"])
        self.file_path = ""
        self.processing = False

        self._setup_styles()
        self._build_ui()

    def _setup_styles(self):
        """Setup custom styles for ttk widgets"""
        style = ttk.Style()
        style.theme_use("clam")

        # Custom button style
        style.configure(
            "Accent.TButton",
            background=self.colors["accent"],
            foreground="white",
            borderwidth=0,
            focuscolor="none",
            font=("Roboto", 10, "bold"),
        )
        style.map(
            "Accent.TButton", background=[("active", self.colors["accent_hover"])]
        )

        # Custom entry style
        style.configure(
            "Modern.TEntry",
            fieldbackground=self.colors["surface"],
            foreground=self.colors["text"],
            borderwidth=1,
            relief="solid",
        )

    def _build_ui(self):
        """Parkee Log Cutter"""

        # Header dengan gradien efek
        header = tk.Frame(self.root, bg=self.colors["surface"], height=80)
        header.pack(fill=tk.X, pady=(0, 20))
        header.pack_propagate(False)

        # Title dan subtitle
        title_frame = tk.Frame(header, bg=self.colors["surface"])
        title_frame.pack(pady=15)

        tk.Label(
            title_frame,
            text="Parkee Log Cutter",
            font=("Roboto", 20, "bold"),
            bg=self.colors["surface"],
            fg=self.colors["text"],
        ).pack()

        tk.Label(
            title_frame,
            text="Gasak Version",
            font=("Roboto", 10),
            bg=self.colors["surface"],
            fg=self.colors["text_secondary"],
        ).pack()

        # Main container dengan card-style
        main_container = tk.Frame(self.root, bg=self.colors["bg"])
        main_container.pack(fill=tk.BOTH, expand=True, padx=30, pady=10)

        # Left panel - Controls
        left_panel = tk.Frame(main_container, bg=self.colors["surface"], relief=tk.FLAT)
        left_panel.pack(side=tk.LEFT, fill=tk.BOTH, expand=True, padx=(0, 15))

        # File selection card
        self._create_card(left_panel, "File Selection", 0)
        self._create_file_selector(left_panel)

        # Datetime range card
        self._create_card(left_panel, "Datetime Range", 1)
        self._create_datetime_picker(left_panel)

        # Options card
        self._create_card(left_panel, "Options", 2)
        self._create_options(left_panel)

        # Process button
        self.process_btn = tk.Button(
            left_panel,
            text="Process Log",
            command=self._start_processing,
            bg=self.colors["success"],
            fg="white",
            font=("Roboto", 12, "bold"),
            relief=tk.FLAT,
            cursor="hand2",
            height=2,
        )
        self.process_btn.pack(fill=tk.X, pady=(20, 10), padx=20)

        # Right panel - Preview
        right_panel = tk.Frame(
            main_container, bg=self.colors["surface"], relief=tk.FLAT
        )
        right_panel.pack(side=tk.RIGHT, fill=tk.BOTH, expand=True)

        tk.Label(
            right_panel,
            text="Log Preview",
            font=("Roboto", 12, "bold"),
            bg=self.colors["surface"],
            fg=self.colors["text"],
        ).pack(anchor="w", padx=15, pady=(15, 5))

        # Preview text area dengan scroll
        preview_frame = tk.Frame(right_panel, bg=self.colors["surface2"])
        preview_frame.pack(fill=tk.BOTH, expand=True, padx=15, pady=(0, 15))

        self.preview_text = tk.Text(
            preview_frame,
            wrap=tk.WORD,
            bg=self.colors["surface2"],
            fg=self.colors["text"],
            font=("Consolas", 9),
            relief=tk.FLAT,
            padx=10,
            pady=10,
        )
        self.preview_text.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)

        scrollbar = tk.Scrollbar(preview_frame, command=self.preview_text.yview)
        scrollbar.pack(side=tk.RIGHT, fill=tk.Y)
        self.preview_text.config(yscrollcommand=scrollbar.set)

        # Status bar modern
        self.status_bar = tk.Label(
            self.root,
            text="● Ready",
            bg=self.colors["surface"],
            fg=self.colors["text_secondary"],
            font=("Roboto", 9),
            anchor="w",
            padx=20,
            pady=10,
        )
        self.status_bar.pack(side=tk.BOTTOM, fill=tk.X)

        # Progress bar
        self.progress = ttk.Progressbar(
            self.root, mode="indeterminate", style="Accent.Horizontal.TProgressbar"
        )

    def _create_card(self, parent, title, row):
        """Helper untuk membuat card-style frame"""
        card = tk.Frame(parent, bg=self.colors["surface2"], relief=tk.FLAT)
        card.pack(fill=tk.X, pady=10, padx=20)

        tk.Label(
            card,
            text=title,
            font=("Roboto", 11, "bold"),
            bg=self.colors["surface2"],
            fg=self.colors["accent"],
        ).pack(anchor="w", padx=15, pady=(15, 10))

        return card

    def _create_file_selector(self, parent):
        """Modern file selector"""
        frame = tk.Frame(parent, bg=self.colors["surface2"])
        frame.pack(fill=tk.X, padx=15, pady=(0, 15))

        self.file_btn = tk.Button(
            frame,
            text="Choose File",
            command=self.choose_file,
            bg=self.colors["accent"],
            fg="white",
            font=("Roboto", 10),
            relief=tk.FLAT,
            cursor="hand2",
            padx=20,
            pady=8,
        )
        self.file_btn.pack(side=tk.LEFT, padx=(0, 15))

        self.file_label = tk.Label(
            frame,
            text="No file selected",
            bg=self.colors["surface2"],
            fg=self.colors["text_secondary"],
            font=("Roboto", 9),
            anchor="w",
        )
        self.file_label.pack(side=tk.LEFT, fill=tk.X, expand=True)

    def _create_datetime_picker(self, parent):
        """Modern datetime inputs"""
        frame = tk.Frame(parent, bg=self.colors["surface2"])
        frame.pack(fill=tk.X, padx=15, pady=(0, 15))

        # Start
        tk.Label(
            frame,
            text="Start",
            bg=self.colors["surface2"],
            fg=self.colors["text"],
            font=("Roboto", 9, "bold"),
        ).pack(anchor="w")

        self.start_entry = tk.Entry(
            frame,
            bg=self.colors["surface"],
            fg=self.colors["text"],
            insertbackground=self.colors["accent"],
            font=("Roboto", 10),
            relief=tk.FLAT,
            highlightthickness=1,
            highlightcolor=self.colors["accent"],
            highlightbackground=self.colors["border"],
        )
        self.start_entry.insert(0, "2026-05-14 00:00:00")
        self.start_entry.pack(fill=tk.X, pady=(5, 10))

        # End
        tk.Label(
            frame,
            text="End",
            bg=self.colors["surface2"],
            fg=self.colors["text"],
            font=("Roboto", 9, "bold"),
        ).pack(anchor="w")

        self.end_entry = tk.Entry(
            frame,
            bg=self.colors["surface"],
            fg=self.colors["text"],
            insertbackground=self.colors["accent"],
            font=("Roboto", 10),
            relief=tk.FLAT,
            highlightthickness=1,
            highlightcolor=self.colors["accent"],
            highlightbackground=self.colors["border"],
        )
        self.end_entry.insert(0, "2026-05-14 23:59:59")
        self.end_entry.pack(fill=tk.X, pady=(5, 0))

    def _create_options(self, parent):
        """Modern options with toggle styling"""
        frame = tk.Frame(parent, bg=self.colors["surface2"])
        frame.pack(fill=tk.X, padx=15, pady=(0, 15))

        self.keep_orphans = tk.BooleanVar(value=False)
        self.create_backup = tk.BooleanVar(value=True)

        # Orphan lines toggle
        orphan_btn = tk.Checkbutton(
            frame,
            text="Keep orphan lines (without timestamp)",
            variable=self.keep_orphans,
            bg=self.colors["surface2"],
            fg=self.colors["text"],
            selectcolor=self.colors["surface2"],
            activebackground=self.colors["surface2"],
            font=("Roboto", 9),
            cursor="hand2",
        )
        orphan_btn.pack(anchor="w", pady=5)

        # Backup toggle
        backup_btn = tk.Checkbutton(
            frame,
            text="Create backup before processing",
            variable=self.create_backup,
            bg=self.colors["surface2"],
            fg=self.colors["text"],
            selectcolor=self.colors["surface2"],
            activebackground=self.colors["surface2"],
            font=("Roboto", 9),
            cursor="hand2",
        )
        backup_btn.pack(anchor="w", pady=5)

        # Timestamp format selector
        tk.Label(
            frame,
            text="Timestamp Format",
            bg=self.colors["surface2"],
            fg=self.colors["text_secondary"],
            font=("Roboto", 9),
        ).pack(anchor="w", pady=(10, 5))

        self.format_var = tk.StringVar(value="default")
        format_combo = ttk.Combobox(
            frame,
            textvariable=self.format_var,
            values=list(self.TIMESTAMP_PATTERNS.keys()),
            state="readonly",
            font=("Roboto", 9),
        )
        format_combo.pack(fill=tk.X)
        format_combo.bind("<<ComboboxSelected>>", self._on_format_change)

    def _on_format_change(self, event=None):
        """Handle format change"""
        self.pattern_type = self.format_var.get()

    def choose_file(self):
        """File selection with preview"""
        file_path = filedialog.askopenfilename(
            title="Select Log File",
            filetypes=[
                ("Log files", "*.log"),
                ("Text files", "*.txt"),
                ("All files", "*.*"),
            ],
        )

        if file_path:
            self.file_path = file_path
            file_size = os.path.getsize(file_path)
            size_mb = file_size / (1024 * 1024)
            size_str = (
                f"{size_mb:.2f} MB" if size_mb > 1 else f"{file_size / 1024:.2f} KB"
            )

            self.file_label.config(
                text=f"{Path(file_path).name} ({size_str})", fg=self.colors["success"]
            )
            self._update_status(f"Loaded: {Path(file_path).name}")
            self._load_preview()

    def _load_preview(self):
        """Load first 20 lines for preview"""
        if not self.file_path:
            return

        try:
            with open(self.file_path, "r", encoding="utf-8", errors="ignore") as f:
                lines = []
                for i, line in enumerate(f):
                    if i >= 20:
                        lines.append("... (preview truncated)")
                        break
                    lines.append(line.rstrip())

            self.preview_text.delete(1.0, tk.END)
            self.preview_text.insert(1.0, "\n".join(lines))
        except Exception as e:
            self.preview_text.delete(1.0, tk.END)
            self.preview_text.insert(1.0, f"Preview error: {str(e)}")

    def _start_processing(self):
        """Start processing in separate thread"""
        if self.processing:
            return

        if not self.file_path:
            messagebox.showerror("Error", "Please select a log file first")
            return

        # Validate datetime
        try:
            self.start_time = datetime.strptime(
                self.start_entry.get(), "%Y-%m-%d %H:%M:%S"
            )
            self.end_time = datetime.strptime(self.end_entry.get(), "%Y-%m-%d %H:%M:%S")

            if self.start_time > self.end_time:
                messagebox.showerror("Error", "Start time must be before end time")
                return
        except ValueError:
            messagebox.showerror(
                "Error", "Invalid datetime format. Use: YYYY-MM-DD HH:MM:SS"
            )
            return

        self.processing = True
        self.process_btn.config(
            state=tk.DISABLED, text="Processing...", bg=self.colors["warning"]
        )
        self.progress.pack(side=tk.BOTTOM, fill=tk.X, padx=30, pady=(0, 10))
        self.progress.start(10)

        thread = threading.Thread(target=self._process_log)
        thread.start()

    def _process_log(self):
        """Actual log processing"""
        try:
            pattern_type = self.format_var.get()
            pattern_regex = re.compile(self.TIMESTAMP_PATTERNS[pattern_type])

            kept_lines = []
            kept_count = 0
            deleted_count = 0
            orphan_count = 0

            # Count total lines for progress (optional)
            total_lines = 0
            with open(self.file_path, "r", encoding="utf-8", errors="ignore") as f:
                total_lines = sum(1 for _ in f)

            processed = 0
            with open(self.file_path, "r", encoding="utf-8", errors="ignore") as f:
                for line in f:
                    processed += 1
                    if processed % 10000 == 0:
                        self._update_status(
                            f"Processing... {processed}/{total_lines} lines"
                        )

                    timestamp_str = None
                    match = pattern_regex.search(line)
                    if match:
                        timestamp_str = match.group(0)

                    if timestamp_str:
                        try:
                            # Try different formats
                            log_time = None
                            for fmt in [
                                "%Y-%m-%d %H:%M:%S",
                                "%Y-%m-%dT%H:%M:%S",
                                "%d/%m/%Y %H:%M:%S",
                            ]:
                                try:
                                    log_time = datetime.strptime(timestamp_str, fmt)
                                    break
                                except:
                                    continue

                            if (
                                log_time
                                and self.start_time <= log_time <= self.end_time
                            ):
                                kept_lines.append(line)
                                kept_count += 1
                            else:
                                deleted_count += 1
                        except:
                            deleted_count += 1
                    else:
                        if self.keep_orphans.get():
                            kept_lines.append(line)
                            orphan_count += 1
                        else:
                            deleted_count += 1

            # Save output
            base_name = os.path.basename(self.file_path)
            filename, ext = os.path.splitext(base_name)
            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")

            # Backup
            if self.create_backup.get():
                backup_path = f"{filename}_BACKUP_{timestamp}{ext}"
                backup_full = os.path.join(os.path.dirname(self.file_path), backup_path)
                shutil.copy2(self.file_path, backup_full)
                self._update_status(f"Backup created: {backup_path}")

            # Save filtered log
            output_filename = f"{filename}_FILTERED_{timestamp}{ext}"
            output_path = os.path.join(os.path.dirname(self.file_path), output_filename)

            with open(output_path, "w", encoding="utf-8") as f:
                f.writelines(kept_lines)

            # Show result
            self.root.after(
                0,
                self._show_result,
                kept_count,
                deleted_count,
                orphan_count,
                output_filename,
            )

        except Exception as e:
            self.root.after(0, self._show_error, str(e))
        finally:
            self.root.after(0, self._reset_ui)

    def _show_result(self, kept, deleted, orphan, filename):
        """Show success dialog"""
        self.progress.stop()
        self.progress.pack_forget()

        result_msg = (
            f"Processing Complete!\n\n"
            f"Statistics:\n"
            f"  • Kept: {kept} lines\n"
            f"  • Deleted: {deleted} lines\n"
            f"  • Orphans: {orphan} lines\n\n"
            f"Output: {filename}"
        )

        messagebox.showinfo("Success", result_msg)
        self._update_status(f"Complete! Saved {kept} lines to {filename}")

    def _show_error(self, error_msg):
        """Show error dialog"""
        self.progress.stop()
        self.progress.pack_forget()
        messagebox.showerror("Processing Error", f"Failed to process log:\n{error_msg}")
        self._update_status(f"Error: {error_msg}")

    def _reset_ui(self):
        """Reset UI after processing"""
        self.processing = False
        self.process_btn.config(
            state=tk.NORMAL, text="Process Log", bg=self.colors["success"]
        )

    def _update_status(self, message):
        """Update status bar"""
        self.root.after(0, lambda: self.status_bar.config(text=f"● {message}"))

    def run(self):
        """Run the application"""
        self.root.mainloop()


if __name__ == "__main__":
    app = ModernLogKeeper()
    app.run()
