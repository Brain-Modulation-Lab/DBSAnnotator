"""Tests for dbs_annotator.logging_config."""

import logging
import sys
from unittest.mock import patch

import pytest
from PySide6.QtCore import QMessageLogContext, QStandardPaths, QtMsgType

import dbs_annotator.logging_config as lc


@pytest.fixture(autouse=True)
def reset_logging_config_state():
    saved = (lc._configured, lc._log_file_path, lc._crash_log_file)
    root = logging.getLogger()
    saved_handlers = root.handlers[:]
    root.handlers.clear()
    yield
    root.handlers[:] = saved_handlers
    lc._configured, lc._log_file_path, lc._crash_log_file = saved


def test_safe_exc_info_with_none_value():
    assert lc._safe_exc_info(ValueError, None, None) == (None, None, None)


def test_safe_exc_info_with_exception():
    try:
        raise ValueError("x")
    except ValueError:
        t, v, tb = sys.exc_info()
        assert t is not None
        out = lc._safe_exc_info(t, v, tb)
        assert out[0] is ValueError
        assert str(out[1]) == "x"


def test_setup_bootstrap_logging_adds_handler_when_empty():
    lc.setup_bootstrap_logging()
    root = logging.getLogger()
    assert root.handlers


def test_install_exception_hooks_sets_hooks():
    import threading

    lc._install_exception_hooks()
    assert callable(sys.excepthook)
    assert threading.excepthook is not None


def test_setup_logging_creates_log_file(qapp, tmp_path, monkeypatch):
    monkeypatch.setattr(
        QStandardPaths,
        "writableLocation",
        lambda _loc: str(tmp_path),
    )
    lc._configured = False
    lc._log_file_path = None
    lc._crash_log_file = None

    log_path = lc.setup_logging(qapp)
    assert log_path.name == "dbs-annotator.log"
    assert log_path.parent.name == "logs"
    root = logging.getLogger()
    assert root.handlers

    same = lc.setup_logging(qapp)
    assert same == log_path


def test_qt_message_handler_levels(qapp, tmp_path, monkeypatch):
    """Exercise qt_handler branches installed by setup_logging."""
    monkeypatch.setattr(
        QStandardPaths,
        "writableLocation",
        lambda _loc: str(tmp_path),
    )
    lc._configured = False
    lc._log_file_path = None
    lc._crash_log_file = None

    installed = []

    def capture(handler):
        installed.append(handler)

    with patch(
        "dbs_annotator.logging_config.qInstallMessageHandler", side_effect=capture
    ):
        lc.setup_logging(qapp)

    assert installed, "message handler should be installed"
    handler = installed[-1]
    ctx = QMessageLogContext()
    for mode in (
        QtMsgType.QtDebugMsg,
        QtMsgType.QtInfoMsg,
        QtMsgType.QtWarningMsg,
        QtMsgType.QtCriticalMsg,
        QtMsgType.QtFatalMsg,
    ):
        handler(mode, ctx, "hello")
