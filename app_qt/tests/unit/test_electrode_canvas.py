"""Tests for ElectrodeCanvas (lightweight geometry / state)."""

from __future__ import annotations

from unittest.mock import MagicMock

import pytest
from PySide6.QtCore import QPointF

from dbs_annotator.config_electrode_models import ContactState
from dbs_annotator.models.electrode_viewer import ElectrodeCanvas


@pytest.mark.gui
def test_electrode_canvas_defaults(qtbot, qapp):
    c = ElectrodeCanvas()
    qtbot.addWidget(c)
    c.resize(200, 400)
    assert c.calculate_scale() == 20
    assert c.get_contact_at_pos(QPointF(0, 0)) is None
    assert c.get_ring_at_pos(QPointF(0, 0)) is None
    assert c.is_case_at_pos(QPointF(0, 0)) is False


@pytest.mark.gui
def test_electrode_canvas_export_mode_scale(qtbot, qapp):
    c = ElectrodeCanvas()
    qtbot.addWidget(c)
    c.resize(200, 400)
    c.set_export_mode(True)
    assert c.export_mode is True
    from dbs_annotator.config_electrode_models import MEDTRONIC_3387

    c.set_model(MEDTRONIC_3387)
    s = c.calculate_scale()
    assert 0 < s <= 80


@pytest.mark.gui
def test_cycle_contact_and_case(qtbot, qapp):
    c = ElectrodeCanvas()
    qtbot.addWidget(c)
    from dbs_annotator.config_electrode_models import MEDTRONIC_3387

    c.set_model(MEDTRONIC_3387)
    cb = MagicMock()
    c.validation_callback = cb
    c.cycle_contact_state((0, 0))
    assert cb.called
    c.cycle_case_state()
    assert cb.call_count >= 2


@pytest.mark.gui
def test_set_ring_state_noop_without_directional_model(qtbot, qapp):
    c = ElectrodeCanvas()
    qtbot.addWidget(c)
    from dbs_annotator.config_electrode_models import MEDTRONIC_3387

    c.set_model(MEDTRONIC_3387)
    c.set_ring_state(0, ContactState.ANODIC)  # non-directional model -> early return
