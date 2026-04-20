"""
Amplitude split widget for per-cathode percentage distribution.

When multiple cathode contacts are active, this widget shows editable
percentage rows below the total amplitude field.  Each row displays the
contact label, an editable percentage, and a read-only computed mA value.
"""

from PySide6.QtCore import Qt
from PySide6.QtGui import QDoubleValidator
from PySide6.QtWidgets import (
    QHBoxLayout,
    QLabel,
    QLineEdit,
    QVBoxLayout,
    QWidget,
)

from ..config_electrode_models import ContactState


class AmplitudeSplitWidget(QWidget):
    """Dynamic per-cathode amplitude percentage rows.

    Parameters
    ----------
    amp_edit : QLineEdit
        The *total* amplitude field that this widget watches.
    parent : QWidget, optional
        Parent widget.
    """

    def __init__(self, amp_edit: QLineEdit, parent=None):
        super().__init__(parent)
        self._amp_edit = amp_edit
        # contact_label -> percentage (float 0-100)
        self._percentages: dict[str, float] = {}
        # ordered list of cathode labels currently displayed
        self._cathode_labels: list[str] = []
        # row widgets: label -> (row_widget, pct_edit, ma_label)
        self._rows: dict[str, tuple[QWidget, QLineEdit, QLabel]] = {}

        self._layout = QVBoxLayout(self)
        self._layout.setContentsMargins(0, 0, 0, 0)
        self._layout.setSpacing(2)

        # Listen to total-amplitude changes to refresh mA values
        self._amp_edit.textChanged.connect(self._refresh_ma_values)

        self.setVisible(False)

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    def update_cathodes(
        self, cathode_labels: list[str], is_single_grouped_directional: bool = False
    ) -> None:
        """Rebuild the rows to match the current set of active cathodes.

        Called by the parent view whenever the electrode canvas changes.

        Parameters
        ----------
        cathode_labels : list[str]
            Ordered list of cathode contact labels (e.g. ``["E1b", "E2a"]``).
            Pass an empty list or a single-element list to hide the widget.
        """
        # Filter out "case" — CASE as cathode does not get a percentage row
        cathode_labels = [lbl for lbl in cathode_labels if lbl.lower() != "case"]

        # Use the passed parameter to determine if this is a single grouped
        # directional contact.

        # Hide widget if no cathodes, or single non-grouped cathode
        if len(cathode_labels) == 0 or (
            len(cathode_labels) == 1 and not is_single_grouped_directional
        ):
            self._clear_rows()
            self._cathode_labels = []
            self._percentages.clear()
            self.setVisible(False)
            return

        # Determine which labels are new / removed
        old_set = set(self._cathode_labels)
        new_set = set(cathode_labels)

        if new_set == old_set and cathode_labels == self._cathode_labels:
            # No change
            return

        # Compute new default percentages
        self._cathode_labels = list(cathode_labels)
        if len(cathode_labels) == 1 and is_single_grouped_directional:
            # For single grouped directional contact, set 100% to enable
            # segment splitting.
            self._percentages[cathode_labels[0]] = 100.0
        else:
            self._redistribute_percentages()

        # Rebuild UI rows
        self._rebuild_rows()
        self.setVisible(True)

    def get_percentages(self) -> dict[str, float]:
        """Return {contact_label: percentage} mapping."""
        return dict(self._percentages)

    def get_amplitude_text(self) -> str:
        """Return the amplitude string for TSV storage.

        - Single or no cathode: returns the total amplitude as-is.
        - Multiple cathodes: returns per-contact mA values joined with ``_``,
          e.g. ``"1.5_1.0"``.
        """
        total_text = self._amp_edit.text().strip()

        # For single or no cathode, return total amplitude
        if len(self._cathode_labels) <= 1:
            return total_text

        # Multiple cathodes - use regular logic
        try:
            total_amp = float(total_text)
        except (ValueError, TypeError):
            return total_text

        parts = []
        for lbl in self._cathode_labels:
            pct = self._percentages.get(lbl, 0.0)
            ma = total_amp * pct / 100.0
            # Format: remove trailing zeros but keep at least one decimal
            formatted = f"{ma:.2f}".rstrip("0").rstrip(".")
            parts.append(formatted)
        return "_".join(parts)

    # ------------------------------------------------------------------
    # Internal helpers
    # ------------------------------------------------------------------

    def _redistribute_percentages(self) -> None:
        """Set equal-split defaults for all current cathodes."""
        n = len(self._cathode_labels)
        if n == 0:
            self._percentages.clear()
            return

        base = round(100.0 / n, 1)
        # Assign base to all but the last; last gets the remainder
        for i, lbl in enumerate(self._cathode_labels):
            if i < n - 1:
                self._percentages[lbl] = base
            else:
                self._percentages[lbl] = round(100.0 - base * (n - 1), 1)

    def _clear_rows(self) -> None:
        """Remove all dynamic row widgets."""
        for lbl in list(self._rows):
            row_w, _, _ = self._rows.pop(lbl)
            self._layout.removeWidget(row_w)
            row_w.deleteLater()

    def _rebuild_rows(self) -> None:
        """Tear down and recreate all percentage rows."""
        self._clear_rows()

        # Check if we have a single grouped contact (E1, E2, etc.)
        if (
            len(self._cathode_labels) == 1
            and len(self._cathode_labels[0]) >= 2
            and self._cathode_labels[0][0] == "E"
            and self._cathode_labels[0][1:].isdigit()
        ):
            # Create segment rows for grouped contact
            self._create_segment_rows_only(self._cathode_labels[0])
        else:
            # Create regular rows for individual contacts/segments
            for i, lbl in enumerate(self._cathode_labels):
                self._create_regular_row(lbl, i)

        self._refresh_ma_values()

    def _create_regular_row(self, lbl: str, index: int) -> None:
        """Create a regular percentage row for a single contact."""
        row_w = QWidget()
        row_layout = QHBoxLayout(row_w)
        row_layout.setContentsMargins(20, 0, 0, 0)
        row_layout.setSpacing(4)

        # Contact label
        name_lbl = QLabel(f"<b>{lbl}</b>")
        name_lbl.setMinimumWidth(40)
        row_layout.addWidget(name_lbl)

        # Percentage edit
        pct_edit = QLineEdit()
        pct_edit.setMaximumWidth(55)
        pct_edit.setAlignment(Qt.AlignmentFlag.AlignRight)
        pct_edit.setValidator(QDoubleValidator(0.0, 100.0, 1))
        pct_edit.setText(f"{self._percentages.get(lbl, 0.0):g}")
        row_layout.addWidget(pct_edit)

        pct_label = QLabel("%")
        row_layout.addWidget(pct_label)

        arrow_lbl = QLabel("->")
        row_layout.addWidget(arrow_lbl)

        # Computed mA label (read-only)
        ma_label = QLabel("")
        ma_label.setMinimumWidth(60)
        ma_label.setStyleSheet("color: #64748b;")
        row_layout.addWidget(ma_label)

        row_layout.addStretch(1)

        is_last = index == len(self._cathode_labels) - 1

        # Connect editing
        if is_last:
            pct_edit.setReadOnly(True)
            pct_edit.setStyleSheet(
                "background: transparent; border: none; color: #64748b;"
            )
        else:
            pct_edit.editingFinished.connect(lambda lbl_=lbl: self._on_pct_edited(lbl_))
            pct_edit.textChanged.connect(
                lambda _text, lbl_=lbl: self._on_pct_text_changed(lbl_)
            )

        self._rows[lbl] = (row_w, pct_edit, ma_label)
        self._layout.addWidget(row_w)

    def _create_segment_rows_only(self, parent_lbl: str) -> None:
        """Create only segment rows for a grouped directional contact (no main row)."""
        seg_labels = ["a", "b", "c"]
        parent_percentage = self._percentages.get(parent_lbl, 0.0)
        segment_percentage = round(
            parent_percentage / 3.0, 1
        )  # Equal split by default, rounded to 1 decimal

        for seg_idx, seg_label in enumerate(seg_labels):
            seg_lbl = f"{parent_lbl}{seg_label}"

            row_w = QWidget()
            row_layout = QHBoxLayout(row_w)
            row_layout.setContentsMargins(
                20, 0, 0, 0
            )  # Regular indentation (not extra)
            row_layout.setSpacing(4)

            # Segment label
            name_lbl = QLabel(f"<b>{seg_lbl}</b>")
            name_lbl.setMinimumWidth(40)
            row_layout.addWidget(name_lbl)

            # Percentage edit (editable for segments)
            pct_edit = QLineEdit()
            pct_edit.setMaximumWidth(55)
            pct_edit.setAlignment(Qt.AlignmentFlag.AlignRight)
            pct_edit.setValidator(QDoubleValidator(0.0, 100.0, 1))
            pct_edit.setText(f"{segment_percentage:g}")
            row_layout.addWidget(pct_edit)

            pct_label = QLabel("%")
            row_layout.addWidget(pct_label)

            arrow_lbl = QLabel("->")
            row_layout.addWidget(arrow_lbl)

            # Computed mA label (read-only)
            ma_label = QLabel("")
            ma_label.setMinimumWidth(60)
            ma_label.setStyleSheet("color: #64748b;")
            row_layout.addWidget(ma_label)

            row_layout.addStretch(1)

            # Store segment percentages
            self._percentages[seg_lbl] = segment_percentage

            # Connect editing for segment rows
            is_last = seg_idx == len(seg_labels) - 1
            if is_last:
                pct_edit.setReadOnly(True)
                pct_edit.setStyleSheet(
                    "background: transparent; border: none; color: #64748b;"
                )
            else:
                pct_edit.editingFinished.connect(
                    lambda lbl_=seg_lbl: self._on_pct_edited(lbl_)
                )
                pct_edit.textChanged.connect(
                    lambda _text, lbl_=seg_lbl: self._on_pct_text_changed(lbl_)
                )

            self._rows[seg_lbl] = (row_w, pct_edit, ma_label)
            self._layout.addWidget(row_w)

    def _on_pct_edited(self, edited_label: str) -> None:
        """Called when user finishes editing a percentage field."""
        self._read_and_rebalance(edited_label)

    def _on_pct_text_changed(self, edited_label: str) -> None:
        """Live update as the user types."""
        self._read_and_rebalance(edited_label)

    def _read_and_rebalance(self, edited_label: str) -> None:
        """Read edited values, auto-complete the last cathode, refresh mA."""
        n = len(self._cathode_labels)
        if n < 2:
            return

        # Read all non-last values
        total_others = 0.0
        for lbl in self._cathode_labels[:-1]:
            row_data = self._rows.get(lbl)
            if not row_data:
                continue
            _, pct_edit, _ = row_data
            try:
                val = float(pct_edit.text())
            except ValueError:
                val = 0.0
            val = max(0.0, min(100.0, val))
            self._percentages[lbl] = val
            total_others += val

        # Clamp: if total_others > 100, scale them down proportionally
        if total_others > 100.0 and total_others > 0:
            scale = 100.0 / total_others
            total_others = 0.0
            for lbl in self._cathode_labels[:-1]:
                self._percentages[lbl] = round(self._percentages[lbl] * scale, 1)
                total_others += self._percentages[lbl]
                row_data = self._rows.get(lbl)
                if row_data:
                    _, pct_edit, _ = row_data
                    pct_edit.blockSignals(True)
                    pct_edit.setText(f"{self._percentages[lbl]:g}")
                    pct_edit.blockSignals(False)

        # Last cathode gets the remainder
        last_lbl = self._cathode_labels[-1]
        remainder = round(max(0.0, 100.0 - total_others), 1)
        self._percentages[last_lbl] = remainder
        last_row = self._rows.get(last_lbl)
        if last_row:
            _, pct_edit, _ = last_row
            pct_edit.blockSignals(True)
            pct_edit.setText(f"{remainder:g}")
            pct_edit.blockSignals(False)

        self._refresh_ma_values()

    def _refresh_ma_values(self) -> None:
        """Recompute the mA labels from the total amplitude and percentages."""
        try:
            total_amp = float(self._amp_edit.text())
        except (ValueError, TypeError):
            total_amp = 0.0

        # Update all rows (both main contacts and segments)
        for lbl in list(self._rows.keys()):
            row_data = self._rows.get(lbl)
            if not row_data:
                continue
            _, _, ma_label = row_data
            pct = self._percentages.get(lbl, 0.0)
            ma_val = total_amp * pct / 100.0
            ma_label.setText(f"{ma_val:.2f} mA")

    def update_main_amplitude_from_split(self, split_text: str) -> None:
        """Update the main amplitude field to show the sum of split values.

        When loading a file with split amplitude (e.g., "2.5_2.5"),
        this method calculates the sum and updates the main field.
        """
        if not split_text or "_" not in split_text:
            return

        try:
            parts = split_text.split("_")
            total = sum(float(p) for p in parts if p.strip())
            # Format without unnecessary decimal places
            if total.is_integer():
                self._amp_edit.setText(str(int(total)))
            else:
                self._amp_edit.setText(f"{total:.1f}".rstrip("0").rstrip("."))
        except (ValueError, TypeError):
            pass

    def set_amplitude_from_split(self, split_text: str) -> None:
        """Set amplitude from split values and update percentages.

        When loading a file with split amplitude (e.g., "2.5_2.5"),
        this method:
        1. Updates the main amplitude field to show the sum
        2. Updates the percentage distribution to match the split
        """
        if not split_text or "_" not in split_text:
            return

        # Update main amplitude field
        self.update_main_amplitude_from_split(split_text)

        # Parse split values and update percentages
        try:
            parts = split_text.split("_")
            values = [float(p) for p in parts if p.strip()]
            total = sum(values)

            if len(values) != len(self._cathode_labels):
                # Mismatch between number of values and cathodes - use equal split
                self._redistribute_percentages()
                return

            # Calculate percentages based on split values
            for i, lbl in enumerate(self._cathode_labels):
                if i < len(values):
                    pct = (values[i] / total * 100.0) if total > 0 else 0.0
                    self._percentages[lbl] = round(pct, 1)

            # Update the UI rows
            self._rebuild_rows()

        except (ValueError, TypeError):
            # If parsing fails, use equal split
            self._redistribute_percentages()


def get_cathode_labels(canvas) -> list[str]:
    """Extract ordered cathode contact labels from an ElectrodeCanvas.

    Returns a list like ``["E1b", "E2a"]``.  ``"case"`` is included if the
    case is cathodic (but the widget will filter it out).
    """
    model = canvas.model
    if not model:
        return []

    labels: list[str] = []

    if canvas.case_state == ContactState.CATHODIC:
        labels.append("case")

    if model.is_directional:
        for contact_idx in range(model.num_contacts):
            # Check if this contact level is directional (has segments)
            is_contact_directional = model.is_level_directional(contact_idx)

            if is_contact_directional:
                # This contact has segments - check individual segments
                seg_states = [
                    canvas.contact_states.get((contact_idx, seg), ContactState.OFF)
                    for seg in range(3)
                ]
                if all(s == ContactState.CATHODIC for s in seg_states):
                    # All segments are cathodic - show as ring contact (no
                    # segment suffix).
                    labels.append(f"E{contact_idx}")
                    continue
                seg_labels = ["a", "b", "c"]
                for seg, seg_state in enumerate(seg_states):
                    if seg_state == ContactState.CATHODIC:
                        labels.append(f"E{contact_idx}{seg_labels[seg]}")
            else:
                # This contact is a ring contact - no segments
                state = canvas.contact_states.get((contact_idx, 0), ContactState.OFF)
                if state == ContactState.CATHODIC:
                    labels.append(f"E{contact_idx}")
    else:
        # Non-directional model - all contacts are ring contacts
        for contact_idx in range(model.num_contacts):
            state = canvas.contact_states.get((contact_idx, 0), ContactState.OFF)
            if state == ContactState.CATHODIC:
                labels.append(f"E{contact_idx}")

    return labels
