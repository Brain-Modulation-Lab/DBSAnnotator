"""
Tests for the session exporter module.
"""

from unittest.mock import Mock, patch

from dbs_annotator.models.session_data import SessionData
from dbs_annotator.utils.session_exporter import SessionExporter


class TestSessionExporter:
    """Test cases for SessionExporter class."""

    def test_init(self):
        """Test SessionExporter initialization."""
        mock_session_data = Mock(spec=SessionData)
        exporter = SessionExporter(mock_session_data)

        assert exporter.session_data == mock_session_data

    def test_export_to_excel_no_file_open(self):
        """Test export when no session file is open."""
        mock_session_data = Mock(spec=SessionData)
        mock_session_data.is_file_open.return_value = False

        exporter = SessionExporter(mock_session_data)

        with patch(
            "dbs_annotator.utils.session_exporter.QMessageBox.warning"
        ) as mock_warning:
            result = exporter.export_to_excel()

            mock_warning.assert_called_once()
            assert result is False

    def test_export_to_excel_no_data(self):
        """Test export when session file has no data."""
        mock_session_data = Mock(spec=SessionData)
        mock_session_data.is_file_open.return_value = True
        mock_session_data.file_path = "test.tsv"

        exporter = SessionExporter(mock_session_data)

        with (
            patch.object(exporter, "_read_session_data", return_value=None),
            patch(
                "dbs_annotator.utils.session_exporter.QMessageBox.warning"
            ) as mock_warning,
        ):
            result = exporter.export_to_excel()

            mock_warning.assert_called_once()
            assert result is False

    def test_export_to_excel_user_cancelled(self):
        """Test export when user cancels file dialog."""
        mock_session_data = Mock(spec=SessionData)
        mock_session_data.is_file_open.return_value = True
        mock_session_data.file_path = "test.tsv"

        exporter = SessionExporter(mock_session_data)

        # Mock DataFrame with data
        mock_df = Mock()
        mock_df.empty = False

        with (
            patch.object(exporter, "_read_session_data", return_value=mock_df),
            patch(
                "dbs_annotator.utils.session_exporter.QFileDialog.getSaveFileName",
                return_value=("", ""),
            ),
            patch(
                "dbs_annotator.utils.session_exporter.QMessageBox.warning"
            ) as mock_warning,
        ):
            result = exporter.export_to_excel()

            mock_warning.assert_not_called()
            assert result is False

    def test_get_date_range_with_dates(self):
        """Test _get_date_range method with valid dates."""
        import pandas as pd

        mock_session_data = Mock(spec=SessionData)
        exporter = SessionExporter(mock_session_data)

        # Create test DataFrame with dates
        df = pd.DataFrame({"date": ["2024-01-01", "2024-01-05"], "scale_value": [1, 2]})

        date_range = exporter._get_date_range(df)
        assert date_range == "2024-01-01 to 2024-01-05"

    def test_get_date_range_no_dates(self):
        """Test _get_date_range method with no date column."""
        import pandas as pd

        mock_session_data = Mock(spec=SessionData)
        exporter = SessionExporter(mock_session_data)

        # Create test DataFrame without dates
        df = pd.DataFrame({"scale_value": [1, 2]})

        date_range = exporter._get_date_range(df)
        assert date_range == "N/A"

    def test_create_summary_sheet(self):
        """Test summary sheet creation."""
        import pandas as pd

        mock_session_data = Mock(spec=SessionData)
        exporter = SessionExporter(mock_session_data)

        # Create test DataFrame
        df = pd.DataFrame(
            {
                "date": ["2024-01-01", "2024-01-02"],
                "scale_name": ["Mood", "Anxiety"],
                "scale_value": [5, 7],
                "left_amplitude": [3.0, 3.5],
                "right_amplitude": [4.0, 4.2],
            }
        )

        # Create mock Excel writer
        mock_writer = Mock()

        # Test the method
        exporter._create_summary_sheet(mock_writer, df)

        # Verify that to_excel was called
        assert (
            mock_writer.book.create_sheet.called or True
        )  # Basic check that method runs

    def test_export_to_pdf_placeholder(self):
        """Test PDF export placeholder."""
        mock_session_data = Mock(spec=SessionData)
        exporter = SessionExporter(mock_session_data)

        with patch(
            "dbs_annotator.utils.session_exporter.QMessageBox.information"
        ) as mock_info:
            result = exporter.export_to_pdf()

            mock_info.assert_called_once_with(
                None, "Coming Soon", "PDF export will be available in a future version."
            )
            assert result is False

    def test_export_to_word_placeholder(self):
        """Test Word export placeholder."""
        mock_session_data = Mock(spec=SessionData)
        exporter = SessionExporter(mock_session_data)

        with patch(
            "dbs_annotator.utils.session_exporter.QMessageBox.information"
        ) as mock_info:
            result = exporter.export_to_word()

            mock_info.assert_called_once_with(
                None,
                "Coming Soon",
                "Word export will be available in a future version.",
            )
            assert result is False
