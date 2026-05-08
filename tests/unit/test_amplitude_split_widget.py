"""Unit tests for AmplitudeSplitWidget split persistence behavior."""

from PySide6.QtWidgets import QLineEdit

from dbs_annotator.ui.amplitude_split_widget import AmplitudeSplitWidget


def test_set_amplitude_from_split_for_two_cathodes(qtbot, qapp):
    amp_edit = QLineEdit()
    amp_edit.setText("4.0")
    widget = AmplitudeSplitWidget(amp_edit)
    qtbot.addWidget(widget)

    widget.update_cathodes(["E1a", "E1b"])
    widget.set_amplitude_from_split("3.0_1.0")

    assert widget.get_percentages()["E1a"] == 75.0
    assert widget.get_percentages()["E1b"] == 25.0


def test_set_amplitude_from_split_for_grouped_directional_segments(qtbot, qapp):
    amp_edit = QLineEdit()
    amp_edit.setText("6.0")
    widget = AmplitudeSplitWidget(amp_edit)
    qtbot.addWidget(widget)

    widget.update_cathodes(["E1"], is_single_grouped_directional=True)
    widget.set_amplitude_from_split("3.0_2.0_1.0")

    pcts = widget.get_percentages()
    assert pcts["E1a"] == 50.0
    assert pcts["E1b"] == 33.3
    assert pcts["E1c"] == 16.7
