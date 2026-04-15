"""
Longitudinal report exporter for Clinical DBS Annotator.

Combines data from multiple annotation TSV files and generates a unified
longitudinal report in Word or PDF format, with best-entry highlighting
based on user-selected scale optimization preferences.
"""

import logging
import os
import re
import tempfile
from datetime import datetime

import pandas as pd
from docx import Document
from docx.document import Document as DocumentType
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.oxml import OxmlElement
from docx.oxml.ns import qn
from docx.shared import Inches, Pt, RGBColor
from PySide6.QtCore import Qt, QTimer
from PySide6.QtWidgets import QFileDialog, QMessageBox, QWidget

from .. import __app_name__, __version__
from ..config import PLACEHOLDERS
from ..config_electrode_models import ELECTRODE_MODELS, MANUFACTURERS, ContactState

logger = logging.getLogger(__name__)


class LongitudinalExporter:
    """Generate longitudinal reports from multiple annotation TSV files."""

    def __init__(self):
        self.scale_optimization_prefs: list = []
        self.clinical_scale_prefs: list = []

    def set_scale_optimization_prefs(self, prefs: list) -> None:
        """Set scale optimization preferences for best-entry highlighting."""
        self.scale_optimization_prefs = prefs or []

    def set_clinical_scale_prefs(self, prefs: list | None) -> None:
        """Set clinical scale optimization preferences."""
        self.clinical_scale_prefs = prefs or []

    # ------------------------------------------------------------------
    # Public export API
    # ------------------------------------------------------------------

    def export_to_word(
        self, file_paths: list[str], parent: QWidget | None = None, sections=None
    ) -> bool:
        """Export longitudinal report to Word format."""
        try:
            default_name = self._generate_filename(file_paths, ".docx")
            start_dir = os.path.dirname(file_paths[0]) if file_paths else ""
            start_path = (
                os.path.join(start_dir, default_name) if start_dir else default_name
            )

            file_path, _ = QFileDialog.getSaveFileName(
                parent,
                "Export Longitudinal Report",
                start_path,
                "Word Files (*.docx);;All Files (*)",
            )
            if not file_path:
                return False
            if not file_path.endswith(".docx"):
                file_path += ".docx"

            ok = self._build_report(file_paths, file_path, sections=sections)
            if not ok:
                QMessageBox.warning(
                    parent, "No Data", "No session data found in the loaded files."
                )
                return False

            self._show_transient_message(
                parent, "Export Completed", f"Report saved:\n{file_path}"
            )
            return True
        except Exception:
            logger.exception("Failed to export longitudinal report to Word")
            QMessageBox.critical(
                parent, "Export Error", "Failed to export report.\nSee log for details."
            )
            return False

    def export_to_pdf(
        self, file_paths: list[str], parent: QWidget | None = None, sections=None
    ) -> bool:
        """Export longitudinal report to PDF (via intermediate Word)."""
        try:
            default_name = self._generate_filename(file_paths, ".pdf")
            start_dir = os.path.dirname(file_paths[0]) if file_paths else ""
            start_path = (
                os.path.join(start_dir, default_name) if start_dir else default_name
            )

            pdf_path, _ = QFileDialog.getSaveFileName(
                parent,
                "Export Longitudinal Report",
                start_path,
                "PDF Files (*.pdf);;All Files (*)",
            )
            if not pdf_path:
                return False
            if not pdf_path.endswith(".pdf"):
                pdf_path += ".pdf"

            docx_tmp = os.path.splitext(pdf_path)[0] + "_tmp.docx"
            ok = self._build_report(file_paths, docx_tmp, sections=sections)
            if not ok:
                QMessageBox.warning(
                    parent, "No Data", "No session data found in the loaded files."
                )
                return False

            try:
                self._convert_docx_to_pdf(docx_tmp, pdf_path)
            finally:
                try:
                    os.unlink(docx_tmp)
                except Exception:
                    logger.warning(
                        "Failed to remove temporary Word file after PDF export: %s",
                        docx_tmp,
                        exc_info=True,
                    )

            self._show_transient_message(
                parent, "Export Completed", f"Report saved:\n{pdf_path}"
            )
            self._open_file(pdf_path)
            return True
        except Exception:
            logger.exception("Failed to export longitudinal report to PDF")
            QMessageBox.critical(
                parent, "Export Error", "Failed to export report.\nSee log for details."
            )
            return False

    @staticmethod
    def _open_file(path: str) -> None:
        """Open a file with the system default application."""
        try:
            import subprocess
            import sys

            if sys.platform == "win32":
                os.startfile(path)  # noqa: S606
            elif sys.platform == "darwin":
                subprocess.Popen(["open", path])  # noqa: S603
            else:
                subprocess.Popen(["xdg-open", path])  # noqa: S603
        except Exception:
            pass

    # ------------------------------------------------------------------
    # Report building
    # ------------------------------------------------------------------

    def _build_report(
        self, file_paths: list[str], out_path: str, sections=None
    ) -> bool:
        """Read all files, merge, and build the Word document."""

        # Sort files chronologically by earliest date+time in each file
        def get_file_datetime(path):
            try:
                df = pd.read_csv(path, sep="\t")
                if "date" in df.columns and "time" in df.columns:
                    # Combine date and time to create datetime for sorting
                    df["datetime"] = pd.to_datetime(
                        df["date"] + " " + df["time"], errors="coerce"
                    )
                    valid_times = df["datetime"].dropna()
                    if not valid_times.empty:
                        return valid_times.min()  # Use earliest time in file
                # Fallback to filename date if available
                basename = os.path.basename(path)
                import re

                date_match = re.search(r"ses-(\d{8})", basename)
                if date_match:
                    date_str = date_match.group(1)
                    return pd.to_datetime(date_str, format="%Y%m%d")
                # If no date info available, return a very old date to put it at the end
                return pd.Timestamp("1900-01-01")
            except Exception:
                logger.warning(
                    "Failed to derive datetime from file, using fallback ordering: %s",
                    path,
                    exc_info=True,
                )
                return pd.Timestamp("1900-01-01")

        # Sort files from oldest to newest
        file_paths = sorted(file_paths, key=get_file_datetime)

        frames = []
        read_failures = 0
        for path in file_paths:
            try:
                df = pd.read_csv(path, sep="\t")
                # Tag each row with its source file for traceability
                df["_source_file"] = os.path.basename(path)
                frames.append(df)
            except Exception:
                read_failures += 1
                logger.warning(
                    "Could not read longitudinal input file: %s", path, exc_info=True
                )

        if read_failures:
            logger.warning(
                "Longitudinal report input read summary: total_files=%d read_failures=%d loaded=%d",
                len(file_paths),
                read_failures,
                len(frames),
            )

        if not frames:
            return False

        df_all = pd.concat(frames, ignore_index=True)
        if df_all.empty:
            return False

        df_all = self._normalize_block_id(df_all)

        # Split initial vs session rows
        if "is_initial" in df_all.columns:
            df_all["is_initial"] = (
                pd.to_numeric(df_all["is_initial"], errors="coerce")
                .fillna(0)
                .astype(int)
            )
            df_all[df_all["is_initial"] == 1]
            df_session = df_all[df_all["is_initial"] == 0]
        else:
            df_all.iloc[0:0]
            df_session = df_all

        doc = Document()
        section = doc.sections[0]
        section.left_margin = Inches(0.5)
        section.right_margin = Inches(0.5)
        section.top_margin = Inches(0.75)
        section.bottom_margin = Inches(0.75)

        # Title
        title = doc.add_heading("Longitudinal DBS Report", 0)
        title.alignment = WD_ALIGN_PARAGRAPH.CENTER

        doc.add_paragraph(
            f"Generated on: {datetime.now().astimezone().strftime('%Y-%m-%d %H:%M:%S')}"
            f" by {__app_name__} v{__version__}"
        )

        # Patient info (from first file)
        patient_id = self._extract_patient_id(file_paths)
        if patient_id:
            doc.add_paragraph(f"Patient ID: {patient_id}")

        doc.add_paragraph(f"Files included: {len(file_paths)}")
        for fp in file_paths:
            doc.add_paragraph(f"  {os.path.basename(fp)}")

        doc.add_paragraph("")

        # Determine which sections to include (default: sessions_overview + session_data children)
        all_keys = [
            "sessions_overview",
            "session_data",
            "session_data_graph",
            "session_data_table",
            "electrode_config",
            "programming_summary",
        ]
        if sections is not None:
            active = set(sections)
        else:
            # Default: sessions_overview + both session_data children
            active = {"sessions_overview", "session_data_graph"}

        # Render in the defined order
        for key in all_keys:
            if key not in active:
                continue
            if key == "sessions_overview":
                doc.add_paragraph("")
                self._add_sessions_overview(doc, df_all, file_paths)
            if key == "session_data":
                # Treat parent as both children
                doc.add_paragraph("")
                doc.add_heading("Session Data", level=1)
                self._add_scales_timeline_chart(doc, df_session, file_paths)
                self._add_longitudinal_data_table(
                    doc,
                    df_session,
                    file_paths,
                    include_chart=False,
                    include_heading=False,
                )
            elif key == "session_data_graph":
                # Handle graph separately - add heading first
                doc.add_paragraph("")
                doc.add_heading("Session Data", level=1)
                self._add_scales_timeline_chart(doc, df_session, file_paths)
            elif key == "session_data_table":
                # Handle table separately - add heading first if graph not selected
                doc.add_paragraph("")
                doc.add_heading("Session Data", level=1)
                self._add_longitudinal_data_table(
                    doc,
                    df_session,
                    file_paths,
                    include_chart=False,
                    include_heading=False,
                )
                doc.add_paragraph("")
            if key == "electrode_config":
                doc.add_paragraph("")
                self._add_electrode_config_section(doc, df_all, file_paths)
            if key == "programming_summary":
                doc.add_paragraph("")
                self._add_programming_summary(doc, df_all, file_paths)

        doc.save(out_path)
        return True

    # ------------------------------------------------------------------
    # Report sections
    # ------------------------------------------------------------------

    def _add_sessions_overview(
        self, doc: DocumentType, df: pd.DataFrame, file_paths: list[str]
    ) -> None:
        """Add a summary table listing each session file with date and entry count."""
        doc.add_heading("Sessions Overview", level=1)
        self._add_clinical_scales_timeline_chart(doc, df, file_paths)

        headers = ["#", "File", "Date", "Entries", "Clinical scales", "Values"]
        table = doc.add_table(rows=1 + len(file_paths), cols=len(headers))
        table.style = "Table Grid"
        table.autofit = False

        # Column widths - use full page width
        section = doc.sections[0]
        page_w = (
            section.page_width - section.left_margin - section.right_margin
        ) / 914400
        base_w = {
            "#": 0.25,
            "File": 2.0,
            "Date": 1.0,
            "Entries": 0.7,
            "Clinical scales": 1.2,
            "Values": 1.0,
        }
        widths = [base_w.get(h, 0.8) for h in headers]
        # Adjust the "Values" column to fill remaining space
        values_idx = headers.index("Values")
        used = sum(w for j, w in enumerate(widths) if j != values_idx)
        widths[values_idx] = max(1.0, page_w - used)

        w_twips = [Inches(max(0.25, w)) for w in widths]
        for row in table.rows:
            for ci, cell in enumerate(row.cells):
                cell.width = w_twips[ci]

        for i, h in enumerate(headers):
            cell = table.rows[0].cells[i]
            cell.text = h
            for p in cell.paragraphs:
                for run in p.runs:
                    run.bold = True

        for idx, fp in enumerate(file_paths):
            row_cells = table.rows[idx + 1].cells
            basename = os.path.basename(fp)
            row_cells[0].text = str(idx + 1)
            row_cells[1].text = basename

            sub_df = (
                df[df["_source_file"] == basename]
                if "_source_file" in df.columns
                else df
            )
            date_str = ""
            if "date" in sub_df.columns and not sub_df.empty:
                dates = sub_df["date"].dropna().unique()
                if len(dates) > 0:
                    date_str = ", ".join(str(d) for d in sorted(dates))
            row_cells[2].text = date_str

            session_rows = sub_df
            if "is_initial" in sub_df.columns:
                session_rows = sub_df[sub_df["is_initial"] == 0]

            # Count unique block_ids (entries)
            if "block_id" in session_rows.columns:
                unique_entries = session_rows["block_id"].nunique()
            else:
                unique_entries = len(session_rows)
            row_cells[3].text = str(unique_entries)

            # Collect scales from is_initial=1 rows with highest block_id per file
            scale_pairs = []
            if "scale_name" in sub_df.columns and "scale_value" in sub_df.columns:
                # Filter for is_initial=1 only (baseline)
                baseline_df = sub_df.copy()
                if "is_initial" in baseline_df.columns:
                    baseline_df = baseline_df[
                        pd.to_numeric(baseline_df["is_initial"], errors="coerce")
                        .fillna(0)
                        .astype(int)
                        == 1
                    ]

                if not baseline_df.empty and "block_id" in baseline_df.columns:
                    try:
                        baseline_df["block_id_num"] = pd.to_numeric(
                            baseline_df["block_id"], errors="coerce"
                        )
                        max_block = baseline_df["block_id_num"].max()

                        # Get ALL rows with the highest block_id (there could be multiple)
                        max_block_rows = baseline_df[
                            baseline_df["block_id_num"] == max_block
                        ]

                        # Collect all scale pairs from these rows
                        all_scales = {}
                        for _, row in max_block_rows.iterrows():
                            sn = str(row.get("scale_name", "") or "").strip()
                            sv = str(row.get("scale_value", "") or "").strip()

                            if sn and sv:
                                sn_lines = [
                                    s.strip() for s in sn.split("\n") if s.strip()
                                ]
                                sv_lines = [
                                    s.strip() for s in sv.split("\n") if s.strip()
                                ]

                                # Store scales, keeping first non-NaN value per scale name
                                for name, val in zip(sn_lines, sv_lines, strict=False):
                                    if val != "NaN" and val.strip() != "NaN":
                                        if name not in all_scales:
                                            all_scales[name] = val

                        # Convert to list of tuples
                        scale_pairs = list(all_scales.items())
                    except Exception:
                        scale_pairs = []

            row_cells[4].text = (
                "\n".join(p[0] for p in scale_pairs) if scale_pairs else ""
            )
            row_cells[5].text = (
                "\n".join(p[1] for p in scale_pairs) if scale_pairs else ""
            )

    def _add_electrode_config_section(
        self, doc: DocumentType, df_all: pd.DataFrame, file_paths: list[str]
    ) -> None:
        """Add per-file electrode configuration (Initial / Final, Left / Right).

        Each file gets its own heading and a 4-column table matching the
        single-session report layout.  A page break separates consecutive files.
        """
        if df_all is None or df_all.empty:
            return
        if "electrode_model" not in df_all.columns:
            return
        if "_source_file" not in df_all.columns:
            return

        doc.add_heading("Electrode Configurations", level=1)

        from docx.enum.text import WD_BREAK

        any_rendered = False
        for _fp_idx, fp in enumerate(file_paths):
            basename = os.path.basename(fp)
            sub = df_all[df_all["_source_file"] == basename].copy()
            if sub.empty:
                continue

            if "is_initial" in sub.columns:
                sub["is_initial"] = (
                    pd.to_numeric(sub["is_initial"], errors="coerce")
                    .fillna(0)
                    .astype(int)
                )
                df_init = sub[sub["is_initial"] == 1]
                df_final = sub[sub["is_initial"] == 0]
            else:
                df_init = sub.iloc[0:0]
                df_final = sub

            if df_init.empty and df_final.empty:
                continue

            # Pick representative rows
            init_row = self._pick_latest_row(df_init) if not df_init.empty else None
            final_row = self._pick_latest_row(df_final) if not df_final.empty else None

            model_name = ""
            for candidate in (final_row, init_row):
                if candidate is not None:
                    m = str(candidate.get("electrode_model", "") or "").strip()
                    if m:
                        model_name = m
                        break
            if not model_name:
                continue

            # Page break before each file except the first
            if any_rendered:
                para = doc.add_paragraph()
                para.add_run().add_break(WD_BREAK.PAGE)

            any_rendered = True

            # File sub-heading
            label = basename.replace("_events.tsv", "").replace(".tsv", "")
            doc.add_heading(label, level=2)

            manufacturer = self._get_manufacturer_for_model(model_name)
            if manufacturer:
                doc.add_paragraph(f"Electrode model: {manufacturer} | {model_name}")
            else:
                doc.add_paragraph(f"Electrode model: {model_name}")

            # Helper to extract contact strings from a row
            def _contacts(row, side):
                if row is None:
                    return "", ""
                anode = str(row.get(f"{side}_anode", "") or "")
                cathode = str(row.get(f"{side}_cathode", "") or "")
                return anode, cathode

            i_la, i_lc = _contacts(init_row, "left")
            i_ra, i_rc = _contacts(init_row, "right")
            f_la, f_lc = _contacts(final_row, "left")
            f_ra, f_rc = _contacts(final_row, "right")

            # Render PNGs
            tmp_files = []
            init_model = (
                str(init_row.get("electrode_model", "") or model_name)
                if init_row is not None
                else model_name
            )
            final_model = (
                str(final_row.get("electrode_model", "") or model_name)
                if final_row is not None
                else model_name
            )

            png_init_l = (
                self._render_electrode_png(init_model, i_la, i_lc)
                if init_row is not None
                else None
            )
            png_init_r = (
                self._render_electrode_png(init_model, i_ra, i_rc)
                if init_row is not None
                else None
            )
            png_final_l = (
                self._render_electrode_png(final_model, f_la, f_lc)
                if final_row is not None
                else None
            )
            png_final_r = (
                self._render_electrode_png(final_model, f_ra, f_rc)
                if final_row is not None
                else None
            )

            for p in (png_init_l, png_init_r, png_final_l, png_final_r):
                if p:
                    tmp_files.append(p)

            # 4-column x 4-row table: Init L | Init R | Final L | Final R
            t = doc.add_table(rows=4, cols=4)
            t.autofit = False

            # Set column widths to use full page width
            section = doc.sections[0]
            page_w = (
                section.page_width - section.left_margin - section.right_margin
            ) / 914400
            col_w = page_w / 4
            w_twips = Inches(col_w)
            for row in t.rows:
                for cell in row.cells:
                    cell.width = w_twips

            # Remove borders
            tbl = t._tbl
            tblPr = tbl.tblPr if tbl.tblPr is not None else tbl._add_tblPr()  # noqa: N806
            borders = OxmlElement("w:tblBorders")
            for bname in ("top", "left", "bottom", "right", "insideH", "insideV"):
                b = OxmlElement(f"w:{bname}")
                b.set(qn("w:val"), "none")
                b.set(qn("w:sz"), "0")
                b.set(qn("w:space"), "0")
                b.set(qn("w:color"), "auto")
                borders.append(b)
            tblPr.append(borders)

            # Row 0: "Initial Settings" (merged 0-1) | "Final Settings" (merged 2-3)
            for merged_start, merged_end, heading_text in [
                (0, 1, "Initial Settings"),
                (2, 3, "Final Settings"),
            ]:
                cell = t.cell(0, merged_start).merge(t.cell(0, merged_end))
                cell.text = heading_text
                for p in cell.paragraphs:
                    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
                    for run in p.runs:
                        run.bold = True

            # Row 1: Left | Right | Left | Right
            for col, txt in enumerate(["Left", "Right", "Left", "Right"]):
                t.cell(1, col).text = txt
                for p in t.cell(1, col).paragraphs:
                    p.alignment = WD_ALIGN_PARAGRAPH.CENTER

            # Row 2: config text
            configs = [
                (i_la, i_lc),
                (i_ra, i_rc),
                (f_la, f_lc),
                (f_ra, f_rc),
            ]
            for col, (anode, cathode) in enumerate(configs):
                t.cell(2, col).text = f"+{anode}\n-{cathode}".strip()
                for p in t.cell(2, col).paragraphs:
                    p.alignment = WD_ALIGN_PARAGRAPH.CENTER

            # Row 3: electrode images
            png_list = [png_init_l, png_init_r, png_final_l, png_final_r]
            for col, png in enumerate(png_list):
                cell = t.cell(3, col)
                cell.text = ""
                p = cell.paragraphs[0]
                p.alignment = WD_ALIGN_PARAGRAPH.CENTER
                if png:
                    run = p.add_run()
                    try:
                        run.add_picture(png, width=Inches(1.15))
                    except Exception:
                        logger.debug(
                            "Failed adding electrode image to report table: %s",
                            png,
                            exc_info=True,
                        )
                        pass

            # Cleanup temp PNG files
            for pth in tmp_files:
                try:
                    os.unlink(pth)
                except Exception:
                    logger.debug(
                        "Failed to delete temporary electrode image: %s",
                        pth,
                        exc_info=True,
                    )

            doc.add_paragraph("")

    def _add_programming_summary(
        self, doc: DocumentType, df_all: pd.DataFrame, file_paths: list[str]
    ) -> None:
        """Add a per-session programming summary table."""
        if df_all is None or df_all.empty:
            return
        if "_source_file" not in df_all.columns:
            return

        doc.add_heading("Programming Summary", level=1)

        headers = [
            "Session",
            "Configurations",
            "Amplitude (L)",
            "Amplitude (R)",
            "Frequency (L)",
            "Frequency (R)",
            "Pulse Width (L)",
            "Pulse Width (R)",
        ]
        rows_data = []

        for fp in file_paths:
            basename = os.path.basename(fp)
            sub = df_all[df_all["_source_file"] == basename]
            if sub.empty:
                continue

            if "is_initial" in sub.columns:
                sub_sess = sub[
                    pd.to_numeric(sub["is_initial"], errors="coerce")
                    .fillna(0)
                    .astype(int)
                    == 0
                ]
            else:
                sub_sess = sub

            label = basename.replace("_events.tsv", "").replace(".tsv", "")

            sub_n = self._normalize_block_id(sub_sess)
            n_configs = (
                sub_n["block_id"].nunique() if "block_id" in sub_n.columns else 0
            )

            def _range_str(series, unit=""):
                vals = pd.to_numeric(series, errors="coerce").dropna()
                if vals.empty:
                    return "N/A"
                mn, mx = vals.min(), vals.max()
                if mn == mx:
                    return f"{mn:.1f}{unit}" if unit else f"{mn:g}"
                return f"{mn:.1f}–{mx:.1f}{unit}" if unit else f"{mn:g}–{mx:g}"

            amp_l = _range_str(sub_sess.get("left_amplitude", pd.Series()), " mA")
            amp_r = _range_str(sub_sess.get("right_amplitude", pd.Series()), " mA")
            freq_l = _range_str(sub_sess.get("left_stim_freq", pd.Series()), " Hz")
            freq_r = _range_str(sub_sess.get("right_stim_freq", pd.Series()), " Hz")
            pw_l = _range_str(sub_sess.get("left_pulse_width", pd.Series()), " µs")
            pw_r = _range_str(sub_sess.get("right_pulse_width", pd.Series()), " µs")

            rows_data.append(
                [label, str(n_configs), amp_l, amp_r, freq_l, freq_r, pw_l, pw_r]
            )

        if not rows_data:
            doc.add_paragraph("No programming data available.")
            return

        table = doc.add_table(rows=1 + len(rows_data), cols=len(headers))
        table.style = "Table Grid"

        # Column widths - use full page width
        section = doc.sections[0]
        page_w = (
            section.page_width - section.left_margin - section.right_margin
        ) / 914400
        base_w = {
            "Session": 2.0,
            "Configurations": 0.8,
            "Amplitude (L)": 1.2,
            "Amplitude (R)": 1.2,
            "Frequency (L)": 1.2,
            "Frequency (R)": 1.2,
            "Pulse Width (L)": 1.2,
            "Pulse Width (R)": 1.2,
        }
        widths = [base_w.get(h, 1.0) for h in headers]
        # Adjust the last column to fill remaining space
        last_idx = len(headers) - 1
        used = sum(w for j, w in enumerate(widths) if j != last_idx)
        widths[last_idx] = max(1.0, page_w - used)

        w_twips = [Inches(max(0.25, w)) for w in widths]
        for row in table.rows:
            for idx, cell in enumerate(row.cells):
                cell.width = w_twips[idx]

        for i, h in enumerate(headers):
            cell = table.rows[0].cells[i]
            cell.text = h
            for p in cell.paragraphs:
                for run in p.runs:
                    run.bold = True

        for r_idx, row_vals in enumerate(rows_data):
            for c_idx, val in enumerate(row_vals):
                table.rows[r_idx + 1].cells[c_idx].text = val

        doc.add_paragraph("")

    def _add_longitudinal_data_table(
        self,
        doc: DocumentType,
        df_session: pd.DataFrame,
        file_paths: list[str] | None = None,
        include_chart: bool = True,
        include_heading: bool = True,
    ) -> None:
        """Add the main longitudinal data table with green highlighting.

        Args:
            doc: Word document
            df_session: Session data DataFrame
            file_paths: List of file paths for chart generation
            include_chart: Whether to include the scales timeline chart
            include_heading: Whether to include the "Session Data" heading
        """
        if include_heading:
            doc.add_heading("Session Data", level=1)
        if include_chart and file_paths:
            self._add_scales_timeline_chart(doc, df_session, file_paths)

        if df_session is None or df_session.empty:
            doc.add_paragraph("No session data available.")
            return

        lateral_df = self._create_lateral_table(df_session)
        if lateral_df.empty:
            doc.add_paragraph("No session data available.")
            return

        # Ensure date column is present (populated inside _create_lateral_table)
        if "date" not in lateral_df.columns:
            lateral_df["date"] = ""

        columns_to_exclude = [
            "time",
            "onset",
            "block_id",
            "session_ID",
            "source",
            "is_initial",
            "electrode_model",
            "_source_file",
            "_global_entry_id",
        ]
        display_cols = [c for c in lateral_df.columns if c not in columns_to_exclude]

        lateral_cols = [
            "date",
            "laterality",
            "frequency",
            "anode",
            "cathode",
            "amplitude",
            "pulse_width",
        ]
        common_cols = ["group_ID", "scale_name", "scale_value", "notes"]

        lateral_cols = [c for c in lateral_cols if c in display_cols]
        common_cols = [c for c in common_cols if c in display_cols]
        ordered = lateral_cols + common_cols

        if not ordered:
            doc.add_paragraph("No displayable columns found.")
            return

        table = doc.add_table(rows=lateral_df.shape[0] + 1, cols=len(ordered))
        table.style = "Table Grid"
        table.autofit = False

        # Column widths
        section = doc.sections[0]
        page_width = int(section.page_width or 0)
        left_margin = int(section.left_margin or 0)
        right_margin = int(section.right_margin or 0)
        page_w = (page_width - left_margin - right_margin) / 914400
        base_w = {
            "date": 0.65,
            "laterality": 0.25,
            "group_ID": 0.35,
            "frequency": 0.45,
            "anode": 0.45,
            "cathode": 0.60,
            "amplitude": 0.60,
            "pulse_width": 0.50,
            "scale_name": 1.00,
            "scale_value": 0.55,
        }
        widths = [base_w.get(c, 0.5) for c in ordered]
        if "notes" in ordered:
            ni = ordered.index("notes")
            used = sum(w for j, w in enumerate(widths) if j != ni)
            widths[ni] = max(1.5, page_w - used)

        w_twips = [Inches(max(0.25, w)) for w in widths]
        for row in table.rows:
            for idx, cell in enumerate(row.cells):
                cell.width = w_twips[idx]

        # Header
        for i, col in enumerate(ordered):
            cell = table.rows[0].cells[i]
            cell.text = self._column_header(col)
            for p in cell.paragraphs:
                for run in p.runs:
                    run.bold = True

        # Find best / second-best entries
        best_ids, second_ids = self._find_best_and_second_best(lateral_df)

        prev_entry_id = None
        for i, (_, row) in enumerate(lateral_df.iterrows()):
            row_cells = table.rows[i + 1].cells

            entry_id = row.get("_global_entry_id", None)
            if best_ids and entry_id in best_ids:
                self._highlight_cells(row_cells, "best")
            elif second_ids and entry_id in second_ids:
                self._highlight_cells(row_cells, "second")

            # Separator between entries
            if (
                prev_entry_id is not None
                and entry_id != prev_entry_id
                and row.get("laterality") == "L"
            ):
                for cell in row_cells:
                    self._set_cell_border_top(cell, sz=24)
            prev_entry_id = entry_id

            for j, col in enumerate(ordered):
                val = row.get(col, "")
                cell_text = str(val) if pd.notna(val) else ""
                if col in ("frequency", "pulse_width"):
                    try:
                        v = float(val)
                        cell_text = str(int(v)) if v == int(v) else str(v)
                    except ValueError, TypeError:
                        pass

                if col in common_cols and row.get("laterality") == "R" and i > 0:
                    prev_cell = table.rows[i].cells[j]
                    prev_cell.merge(row_cells[j])
                    row_cells[j].text = ""
                elif col == "cathode" and "_" in cell_text:
                    # Multi-contact cathode: show stacked with Total label
                    contacts = cell_text.replace("_", "\n")
                    row_cells[j].text = contacts + "\nTotal"
                elif col == "amplitude" and "_" in cell_text:
                    # Multi-contact amplitude: show stacked values with total
                    parts = cell_text.split("_")
                    try:
                        # Validate all parts are numbers and calculate total
                        values = [float(p) for p in parts]
                        total = sum(values)
                        total_str = f"{total:.2f}".rstrip("0").rstrip(".")
                        row_cells[j].text = "\n".join(parts) + f"\n{total_str}"
                    except ValueError, TypeError:
                        row_cells[j].text = cell_text
                else:
                    row_cells[j].text = cell_text

        # Legend
        self._add_table_legend(doc, best_ids, second_ids)

    def _add_scales_timeline_chart(
        self,
        doc: Document,
        df_session: pd.DataFrame,
        file_paths: list[str],
    ) -> None:
        """Add a timeline chart of session scale trends across all files.

        X-axis labels: ``{date}_{block_ID}_{run_ID}``
        """
        from .report_chart_utils import add_chart_to_doc, build_scales_chart

        if df_session is None or df_session.empty:
            return
        if (
            "scale_name" not in df_session.columns
            or "scale_value" not in df_session.columns
        ):
            return

        scale_data, x_ticks = self._collect_session_scale_data(df_session, file_paths)
        if not scale_data:
            return

        png = build_scales_chart(
            scale_data,
            self.scale_optimization_prefs,
            title="Session Scale Trends",
            x_label="Session Block",
            y_label="Scale Value",
            x_ticks=x_ticks,
            rotate_x_ticks=True,
        )
        add_chart_to_doc(doc, png)

    def _add_clinical_scales_timeline_chart(
        self,
        doc: Document,
        df_all: pd.DataFrame,
        file_paths: list[str],
    ) -> None:
        """Add a timeline chart of clinical (baseline) scale trends.

        For each source file, takes only the latest block_ID rows with
        is_initial == 1 and plots one value per file per scale.
        No aggregated General Index line is drawn for clinical scales.
        X-axis labels: ``{date}_{run_ID}``
        """
        from .report_chart_utils import add_chart_to_doc, build_scales_chart

        if df_all is None or df_all.empty:
            return
        if "is_initial" not in df_all.columns:
            return

        scale_data, x_ticks = self._collect_clinical_scale_data(df_all, file_paths)
        if not scale_data:
            return

        png = build_scales_chart(
            scale_data,
            self.clinical_scale_prefs,
            title="Clinical Scale Trends",
            x_label="Session",
            y_label="Scale Value",
            x_ticks=x_ticks,
            show_general_index=False,
            rotate_x_ticks=True,
        )
        add_chart_to_doc(doc, png)

    def _collect_clinical_scale_data(
        self,
        df_all: pd.DataFrame,
        file_paths: list[str],
    ) -> tuple[dict[str, dict[int, float]], list[tuple[int, str]]]:
        """Collect clinical scale values using latest block_ID with is_initial=1 per file.

        X-tick labels: ``{date}_{run_ID}``

        Returns:
            (scale_data, x_ticks)
        """
        import math as _math

        if df_all is None or df_all.empty:
            return {}, []
        required = {"scale_name", "scale_value", "_source_file", "is_initial"}
        if not required.issubset(df_all.columns):
            return {}, []

        df_clin = df_all.copy()
        df_clin["is_initial"] = (
            pd.to_numeric(df_clin["is_initial"], errors="coerce").fillna(0).astype(int)
        )
        df_clin = df_clin[df_clin["is_initial"] == 1]
        if df_clin.empty:
            return {}, []

        if "block_id" in df_clin.columns:
            df_clin["block_id"] = pd.to_numeric(
                df_clin["block_id"], errors="coerce"
            ).fillna(0)
        else:
            df_clin["block_id"] = 0

        # Build ordered source list (files already sorted earliest→latest)
        sources = [os.path.basename(fp) for fp in file_paths]
        source_idx = {s: i for i, s in enumerate(sources)}

        scale_data: dict[str, dict[int, float]] = {}
        tick_labels: list[str] = []

        for src in sources:
            sidx = source_idx[src]
            df_src = df_clin[df_clin["_source_file"] == src]

            # Build tick label: {date}_{run_ID} - always add tick even if no data
            date_str = self._extract_date_from_source(df_all, src)
            run_id = self._extract_run_from_filename(src)
            tick_labels.append(f"{date_str}_{run_id}" if run_id else date_str)

            if df_src.empty:
                # No clinical scales for this file - leave data blank
                continue

            max_bid = df_src["block_id"].max()
            df_latest = df_src[df_src["block_id"] == max_bid]

            for _, row in df_latest.iterrows():
                sname = str(row.get("scale_name", "") or "").strip()
                sval = str(row.get("scale_value", "") or "").strip()
                if not sname or not sval:
                    continue
                try:
                    val = float(sval)
                except ValueError:
                    continue
                if _math.isnan(val):
                    continue
                scale_data.setdefault(sname, {})[sidx] = val

        # Return tick labels even if no scale data (shows empty ticks)
        x_ticks = [(i, lbl) for i, lbl in enumerate(tick_labels)]
        return scale_data, x_ticks

    def _collect_session_scale_data(
        self,
        df_session: pd.DataFrame,
        file_paths: list[str],
    ) -> tuple[dict[str, dict[int, float]], list[tuple[int, str]]]:
        """Collect all session scale values across files, one point per block per file.

        X-tick labels: ``{date}_{run_ID}``

        Returns:
            (scale_data, x_ticks)
        """
        import math as _math

        if df_session is None or df_session.empty:
            return {}, []
        if (
            "scale_name" not in df_session.columns
            or "scale_value" not in df_session.columns
            or "_source_file" not in df_session.columns
        ):
            return {}, []

        # Ensure block_id is numeric
        df = df_session.copy()
        if "block_id" in df.columns:
            df["block_id"] = pd.to_numeric(df["block_id"], errors="coerce").fillna(0)
        else:
            df["block_id"] = 0

        # Build ordered (source, block_id) pairs as the x-axis
        sources = [os.path.basename(fp) for fp in file_paths]
        point_keys: list[tuple[str, float]] = []  # (source_file, block_id)
        tick_labels: list[str] = []

        for src in sources:
            df_src = df[df["_source_file"] == src]
            if df_src.empty:
                continue
            date_str = self._extract_date_from_source(df, src)
            run_id = self._extract_run_from_filename(src)

            blocks = sorted(df_src["block_id"].unique())
            for i, bid in enumerate(blocks):
                point_keys.append((src, bid))
                bid_str = str(int(bid)) if bid == int(bid) else str(bid)
                if i == 0:
                    # First block: full label {date}_{run_id}_{block_id}
                    parts = [date_str]
                    if run_id:
                        parts.append(run_id)
                    parts.append(bid_str)
                    tick_labels.append("_".join(parts))
                else:
                    # Subsequent blocks: only block_id
                    tick_labels.append(bid_str)

        if not point_keys:
            return {}, []

        key_idx = {k: i for i, k in enumerate(point_keys)}

        scale_data: dict[str, dict[int, float]] = {}
        for (src, bid), idx in key_idx.items():
            df_block = df[(df["_source_file"] == src) & (df["block_id"] == bid)]
            for _, row in df_block.iterrows():
                sname = str(row.get("scale_name", "") or "").strip()
                sval = str(row.get("scale_value", "") or "").strip()
                if not sname or not sval:
                    continue
                try:
                    val = float(sval)
                except ValueError:
                    continue
                if _math.isnan(val):
                    continue
                # If multiple rows for same scale in same block, keep last
                scale_data.setdefault(sname, {})[idx] = val

        if not scale_data:
            return {}, []

        x_ticks = [(i, lbl) for i, lbl in enumerate(tick_labels)]
        return scale_data, x_ticks

    @staticmethod
    def _extract_date_from_source(df: pd.DataFrame, source_file: str) -> str:
        """Extract the date string for a given source file."""
        sub = df[df["_source_file"] == source_file]
        if "date" in sub.columns and not sub.empty:
            dates = sub["date"].dropna().unique()
            if len(dates) > 0:
                return str(sorted(dates)[0])
        # Fallback: extract from filename
        match = re.search(r"ses-(\d{8})", source_file)
        if match:
            return match.group(1)
        return "unknown"

    @staticmethod
    def _extract_run_from_filename(filename: str) -> str:
        """Extract run-XX from a BIDS-style filename."""
        match = re.search(r"run-(\d+)", filename)
        return f"run{match.group(1)}" if match else ""

    # ------------------------------------------------------------------
    # Data helpers
    # ------------------------------------------------------------------

    def _create_lateral_table(self, df: pd.DataFrame) -> pd.DataFrame:
        """Create lateral (L/R) table structure similar to SessionExporter."""
        if df.empty:
            return df

        df = self._normalize_block_id(df)

        # Sort by source file (chronological order) and block_id (ascending)
        if "_source_file" in df.columns:
            df = df.sort_values(by=["_source_file", "block_id"], ascending=[True, True])
        elif "block_id" in df.columns:
            df = df.sort_values(by=["block_id"], ascending=True)

        # Create a global entry id combining source file + block_id
        if "_source_file" in df.columns and "block_id" in df.columns:
            df["_global_entry_id"] = (
                df["_source_file"] + "_" + df["block_id"].astype(str)
            )
        elif "block_id" in df.columns:
            df["_global_entry_id"] = df["block_id"].astype(str)
        else:
            df["_global_entry_id"] = range(len(df))

        groups = df.groupby("_global_entry_id", sort=False, dropna=False)
        lateral_data = []

        for entry_id, block_df in groups:
            first = block_df.iloc[0]

            # Collect scales (filter out NaN values)
            scale_pairs = []
            seen = set()
            for _, r in block_df.iterrows():
                sn = str(r.get("scale_name", "") or "").strip()
                sv = str(r.get("scale_value", "") or "").strip()

                # Skip if scale value is NaN or empty
                if not sv or sv == "NaN" or sv.strip() == "NaN":
                    continue

                if sn and (sn, sv) not in seen:
                    seen.add((sn, sv))
                    scale_pairs.append((sn, sv))

            combined_sn = "\n".join(p[0] for p in scale_pairs) if scale_pairs else ""
            combined_sv = "\n".join(p[1] for p in scale_pairs) if scale_pairs else ""

            source_label = (
                str(first.get("_source_file", ""))
                .replace("_events.tsv", "")
                .replace(".tsv", "")
            )
            date_val = str(first.get("date", "") or "")

            common = {
                "_global_entry_id": entry_id,
                "source": source_label,
                "date": date_val,
                "program_ID": first.get("program_ID") or first.get("group_ID", ""),
                "scale_name": combined_sn,
                "scale_value": combined_sv,
                "notes": first.get("notes", ""),
            }

            lat_map = {
                "left_stim_freq": "frequency",
                "left_cathode": "cathode",
                "left_anode": "anode",
                "left_amplitude": "amplitude",
                "left_pulse_width": "pulse_width",
                "right_stim_freq": "frequency",
                "right_cathode": "cathode",
                "right_anode": "anode",
                "right_amplitude": "amplitude",
                "right_pulse_width": "pulse_width",
            }

            left = dict(common)
            right = dict(common)
            left["laterality"] = "L"
            right["laterality"] = "R"

            for col, generic in lat_map.items():
                if col.startswith("left_"):
                    left[generic] = first.get(col, "")
                else:
                    right[generic] = first.get(col, "")

            lateral_data.append(left)
            lateral_data.append(right)

        return pd.DataFrame(lateral_data)

    def _find_best_and_second_best(self, lateral_df: pd.DataFrame) -> tuple:
        """Find entry IDs with the best and second-best scores."""
        if lateral_df is None or lateral_df.empty:
            return [], []
        if "_global_entry_id" not in lateral_df.columns:
            return [], []
        if (
            "scale_name" not in lateral_df.columns
            or "scale_value" not in lateral_df.columns
        ):
            return [], []

        try:
            pref_lookup = {}
            for pref in self.scale_optimization_prefs:
                if len(pref) >= 5:
                    name, _, _, mode, custom_val = pref
                    pref_lookup[name.strip().lower()] = (mode, custom_val)

            df_l = lateral_df[lateral_df.get("laterality", "") == "L"].copy()
            if df_l.empty:
                df_l = lateral_df.drop_duplicates(subset=["_global_entry_id"]).copy()

            scores = {}
            for _, row in df_l.iterrows():
                eid = row.get("_global_entry_id")
                if eid is None:
                    continue
                names = str(row.get("scale_name", "") or "").split("\n")
                values = str(row.get("scale_value", "") or "").split("\n")

                total = 0.0
                has_val = False
                import math as _math

                for i, vl in enumerate(values):
                    vl = vl.strip()
                    if not vl:
                        continue
                    try:
                        val = float(vl)
                    except ValueError:
                        continue
                    if _math.isnan(val):
                        continue
                    sn = names[i].strip().lower() if i < len(names) else ""
                    mode, cv = pref_lookup.get(sn, ("min", ""))
                    if mode == "ignore":
                        continue
                    has_val = True
                    if mode in ("low", "min"):
                        total += val
                    elif mode in ("high", "max"):
                        total -= val
                    elif mode == "custom":
                        try:
                            total += abs(val - float(cv))
                        except ValueError:
                            total += val
                if has_val:
                    scores[eid] = total

            if not scores:
                return [], []

            unique = sorted(set(scores.values()))
            best = [eid for eid, s in scores.items() if s == unique[0]]
            second = (
                [eid for eid, s in scores.items() if s == unique[1]]
                if len(unique) > 1
                else []
            )
            return best, second
        except Exception:
            logger.exception("Failed to rank best/second-best longitudinal entries")
            return [], []

    # ------------------------------------------------------------------
    # Formatting / utility helpers
    # ------------------------------------------------------------------

    @staticmethod
    def _get_manufacturer_for_model(model_name: str) -> str:
        """Return the manufacturer string for a given electrode model name."""
        if not model_name:
            return ""
        for manufacturer, models in (MANUFACTURERS or {}).items():
            try:
                if model_name in models:
                    return str(manufacturer)
            except Exception:
                continue
        return ""

    def _render_electrode_png(
        self,
        model_name: str,
        anode_text: str,
        cathode_text: str,
        target_size_px: tuple = (440, 900),
    ) -> str | None:
        """Render electrode configuration to a temporary PNG file."""
        try:
            from PySide6.QtGui import QColor as _QColor
            from PySide6.QtGui import QPixmap

            from ..models import ElectrodeCanvas

            model = ELECTRODE_MODELS.get(model_name)
            if not model:
                return None

            canvas = ElectrodeCanvas()
            canvas.set_model(model)
            canvas.resize(*target_size_px)
            try:
                canvas.set_export_mode(True)
            except Exception:
                pass

            # Apply contact states
            canvas.contact_states.clear()
            canvas.case_state = ContactState.OFF

            def apply_tokens(text: str, state: int) -> None:
                if not text:
                    return
                for token in str(text).split("_"):
                    token = token.strip()
                    if not token:
                        continue
                    if token == "case":
                        canvas.case_state = state
                        continue
                    if token.startswith("E") and len(token) >= 2:
                        try:
                            if token[-1].isalpha():
                                idx = int(token[1:-1])
                                seg_map = {"a": 0, "b": 1, "c": 2}
                                seg_char = token[-1].lower()
                                if seg_char in seg_map:
                                    canvas.contact_states[(idx, seg_map[seg_char])] = (
                                        state
                                    )
                            else:
                                idx = int(token[1:])
                                if model.is_directional:
                                    for seg in range(3):
                                        canvas.contact_states[(idx, seg)] = state
                                else:
                                    canvas.contact_states[(idx, 0)] = state
                        except Exception:
                            continue

            apply_tokens(anode_text, ContactState.ANODIC)
            apply_tokens(cathode_text, ContactState.CATHODIC)
            canvas.update()

            pixmap = QPixmap(canvas.size())
            pixmap.fill(Qt.white)
            canvas.render(pixmap)

            # Crop white borders
            image = pixmap.toImage()
            white_rgb = _QColor(Qt.white).rgb()
            left, top, right, bottom = image.width(), image.height(), 0, 0
            for y in range(image.height()):
                for x in range(image.width()):
                    if image.pixel(x, y) != white_rgb:
                        left = min(left, x)
                        top = min(top, y)
                        right = max(right, x)
                        bottom = max(bottom, y)
            if right > left and bottom > top:
                margin = 20
                left = max(0, left - margin)
                top = max(0, top - margin)
                right = min(image.width() - 1, right + margin)
                bottom = min(image.height() - 1, bottom + margin)
                cropped = pixmap.copy(left, top, right - left + 1, bottom - top + 1)
            else:
                cropped = pixmap

            tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".png")
            tmp.close()
            cropped.save(tmp.name, "PNG")
            return tmp.name
        except Exception:
            logger.exception("Failed to render electrode image for report")
            return None

    @staticmethod
    def _pick_latest_row(df: pd.DataFrame):
        """Return the row with the highest block_id, or the last row if unavailable."""
        if df is None or df.empty:
            return None
        for col in ("block_id", "block_ID", "blockId", "blockID"):
            if col in df.columns:
                try:
                    numeric = pd.to_numeric(df[col], errors="coerce")
                    max_val = numeric.max()
                    if pd.notna(max_val):
                        return df.loc[numeric == max_val].iloc[-1]
                except Exception:
                    pass
        return df.iloc[-1]

    @staticmethod
    def _normalize_block_id(df: pd.DataFrame) -> pd.DataFrame:
        if df is None or df.empty or "block_id" in df.columns:
            return df
        for c in ("block_ID", "blockId", "blockID"):
            if c in df.columns:
                return df.rename(columns={c: "block_id"})
        return df

    @staticmethod
    def _column_header(col: str) -> str:
        m = {
            "source": "#",
            "date": "Date",
            "scale_name": PLACEHOLDERS.get("scale_name", "Scale"),
            "scale_value": PLACEHOLDERS.get("scale_value", "Value"),
            "frequency": PLACEHOLDERS.get("frequency", "Freq"),
            "anode": "+",
            "cathode": "-",
            "amplitude": PLACEHOLDERS.get("amplitude", "Amp"),
            "pulse_width": PLACEHOLDERS.get("pulse_width", "PW"),
            "group_ID": "Grp",
            "laterality": "",
        }
        return m.get(col, col.replace("_", " ").title())

    @staticmethod
    def _extract_patient_id(file_paths: list[str]) -> str:
        for fp in file_paths:
            m = re.search(r"sub-([^_]+)", os.path.basename(fp))
            if m:
                return m.group(1)
        return ""

    @staticmethod
    def _generate_filename(file_paths: list[str], ext: str) -> str:
        today = datetime.now().astimezone().strftime("%Y%m%d")
        pid = LongitudinalExporter._extract_patient_id(file_paths)
        if pid:
            return f"sub-{pid}_longitudinal-report_{today}{ext}"
        return f"longitudinal-report_{today}{ext}"

    def _highlight_cells(self, row_cells, intensity: str = "best") -> None:
        color = "96D2A0" if intensity == "best" else "C8EBCD"
        for cell in row_cells:
            try:
                shd = OxmlElement("w:shd")
                shd.set(qn("w:fill"), color)
                cell._tc.get_or_add_tcPr().append(shd)
            except Exception:
                pass

    @staticmethod
    def _set_cell_border_top(cell, sz=12):
        try:
            tcPr = cell._tc.get_or_add_tcPr()  # noqa: N806
            borders = OxmlElement("w:tcBorders")
            top = OxmlElement("w:top")
            top.set(qn("w:val"), "single")
            top.set(qn("w:sz"), str(sz))
            top.set(qn("w:space"), "0")
            top.set(qn("w:color"), "000000")
            borders.append(top)
            tcPr.append(borders)
        except Exception:
            pass

    def _add_table_legend(
        self, doc: DocumentType, best_ids: list, second_ids: list
    ) -> None:
        if not best_ids and not second_ids:
            return

        doc.add_paragraph()

        legend = doc.add_paragraph()
        legend.add_run("Legend: ").bold = True
        if best_ids:
            r = legend.add_run("■ ")
            r.font.color.rgb = RGBColor(0x96, 0xD2, 0xA0)
            legend.add_run("Optimal entry    ")
        if second_ids:
            r = legend.add_run("■ ")
            r.font.color.rgb = RGBColor(0xC8, 0xEB, 0xCD)
            legend.add_run("Second-best entry")

        if self.scale_optimization_prefs:
            tp = doc.add_paragraph()
            tp.add_run("Scale targets: ").bold = True
            parts = []
            for pref in self.scale_optimization_prefs:
                if len(pref) >= 5:
                    name, smin, smax, mode, cv = pref
                    if mode == "ignore":
                        continue
                    elif mode == "min":
                        parts.append(f"{name}: min")
                    elif mode == "max":
                        parts.append(f"{name}: max")
                    elif mode == "custom":
                        parts.append(f"{name}: {cv}")
            if parts:
                tp.add_run("; ".join(parts))
                for run in tp.runs:
                    run.font.size = Pt(9)

        disc = doc.add_paragraph()
        dr = disc.add_run(
            "Note: The highlighted rows are derived exclusively from the recorded "
            "session scale values and represent a computational ranking intended "
            "solely as a reference. This color-coded indication does not constitute "
            "clinical guidance."
        )
        dr.font.size = Pt(9)
        dr.font.italic = True

    def _show_transient_message(
        self, parent, title: str, text: str, msecs: int = 2000
    ) -> None:
        msg = QMessageBox(parent)
        msg.setIcon(QMessageBox.Information)
        msg.setWindowTitle(title)
        msg.setText(text)
        msg.setStandardButtons(QMessageBox.NoButton)
        msg.setWindowModality(Qt.NonModal)
        msg.show()

        timer = QTimer(msg)
        timer.setSingleShot(True)

        def _close():
            try:
                msg.accept()
            except Exception:
                pass

        timer.timeout.connect(_close)
        timer.start(max(0, int(msecs)))

    def _convert_docx_to_pdf(self, docx_path: str, pdf_path: str) -> None:
        """Convert Word → PDF using the same strategy as SessionExporter."""
        import shutil
        import subprocess

        errors = []

        try:
            from docx2pdf import convert as _convert

            _convert(docx_path, pdf_path)
            if os.path.exists(pdf_path):
                return
        except Exception as e:
            errors.append(f"docx2pdf: {e}")

        try:
            abs_d = os.path.abspath(docx_path).replace("'", "''")
            abs_p = os.path.abspath(pdf_path).replace("'", "''")
            ps = (
                "$w = New-Object -ComObject Word.Application; "
                "$w.Visible = $false; "
                f"$d = $w.Documents.Open('{abs_d}'); "
                f"$d.SaveAs2('{abs_p}', 17); "
                "$d.Close(); $w.Quit()"
            )
            subprocess.run(
                ["powershell", "-NoProfile", "-Command", ps],
                check=True,
                capture_output=True,
                timeout=60,
            )
            if os.path.exists(pdf_path):
                return
        except Exception as e:
            errors.append(f"Word COM: {e}")

        soffice = shutil.which("soffice")
        if soffice:
            try:
                out_dir = os.path.dirname(os.path.abspath(pdf_path))
                subprocess.run(
                    [
                        soffice,
                        "--headless",
                        "--convert-to",
                        "pdf",
                        "--outdir",
                        out_dir,
                        os.path.abspath(docx_path),
                    ],
                    check=True,
                    capture_output=True,
                    timeout=60,
                )
                lo_out = os.path.join(
                    out_dir, os.path.splitext(os.path.basename(docx_path))[0] + ".pdf"
                )
                if lo_out != pdf_path and os.path.exists(lo_out):
                    shutil.move(lo_out, pdf_path)
                if os.path.exists(pdf_path):
                    return
            except Exception as e:
                errors.append(f"LibreOffice: {e}")

        raise RuntimeError(
            "Could not convert to PDF:\n"
            + "\n".join(errors)
            + "\n\nPlease export to Word and convert manually."
        )
