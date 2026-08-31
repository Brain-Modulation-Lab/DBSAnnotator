"""Tests for dbs_annotator.__main__.main."""

from unittest.mock import MagicMock, patch

from dbs_annotator.__main__ import main


def test_main_returns_exec_code():
    mock_app = MagicMock()
    mock_app.exec.return_value = 0
    mock_window = MagicMock()
    with (
        patch("dbs_annotator.__main__.setup_bootstrap_logging"),
        patch("dbs_annotator.__main__.setup_logging"),
        patch("dbs_annotator.__main__.QApplication", return_value=mock_app),
        patch("dbs_annotator.__main__.WizardWindow", return_value=mock_window),
        patch("dbs_annotator.__main__.get_theme_manager") as gtm,
    ):
        mgr = MagicMock()
        mgr.get_current_theme.return_value = MagicMock()
        gtm.return_value = mgr
        assert main() == 0
        mock_window.show.assert_called_once()
        mock_app.exec.assert_called_once()


def test_main_theme_failure_still_builds_window():
    mock_app = MagicMock()
    mock_app.exec.return_value = 0
    mock_window = MagicMock()
    with (
        patch("dbs_annotator.__main__.setup_bootstrap_logging"),
        patch("dbs_annotator.__main__.setup_logging"),
        patch("dbs_annotator.__main__.QApplication", return_value=mock_app),
        patch("dbs_annotator.__main__.WizardWindow", return_value=mock_window),
        patch("dbs_annotator.__main__.get_theme_manager") as gtm,
    ):
        mgr = MagicMock()
        mgr.apply_theme.side_effect = OSError("theme")
        mgr.get_current_theme.return_value = MagicMock()
        gtm.return_value = mgr
        assert main() == 0


def test_main_fatal_startup_returns_1():
    with (
        patch("dbs_annotator.__main__.setup_bootstrap_logging"),
        patch(
            "dbs_annotator.__main__.QApplication",
            side_effect=RuntimeError("no qt"),
        ),
    ):
        assert main() == 1
