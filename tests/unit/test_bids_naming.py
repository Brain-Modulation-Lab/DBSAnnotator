"""
Unit tests for BIDS naming functionality.

Tests cover:
- BIDS filename generation for reports
- Patient/session ID extraction from filenames
"""


class TestBIDSNaming:
    """Test suite for BIDS naming utilities."""

    def test_generate_bids_report_filename_from_events(self):
        """Test converting events.tsv to report.docx."""

        # Mock session data
        class MockSessionData:
            file_path = "sub-01_ses-01_task-percept_acq-20260208_events.tsv"

            def is_file_open(self):
                return True

        from dbs_annotator.utils.session_exporter import SessionExporter

        exporter = SessionExporter(MockSessionData())

        result = exporter._generate_bids_report_filename(".docx")
        assert result == "sub-01_ses-01_task-percept_acq-20260208_report.docx"

    def test_generate_bids_report_filename_pdf(self):
        """Test converting events.tsv to report.pdf."""

        class MockSessionData:
            file_path = "sub-ABC_ses-02_task-percept_acq-20260208_events.tsv"

            def is_file_open(self):
                return True

        from dbs_annotator.utils.session_exporter import SessionExporter

        exporter = SessionExporter(MockSessionData())

        result = exporter._generate_bids_report_filename(".pdf")
        assert result == "sub-ABC_ses-02_task-percept_acq-20260208_report.pdf"

    def test_extract_bids_info_standard(self):
        """Test extracting patient ID and session from BIDS filename."""

        class MockSessionData:
            file_path = "sub-P001_ses-03_task-percept_events.tsv"

            def is_file_open(self):
                return True

        from dbs_annotator.utils.session_exporter import SessionExporter

        exporter = SessionExporter(MockSessionData())

        patient_id, session_num = exporter._extract_bids_info_from_path()
        assert patient_id == "P001"
        assert session_num == "03"

    def test_extract_bids_info_missing_session(self):
        """Test extraction when session is missing."""

        class MockSessionData:
            file_path = "sub-01_task-percept_events.tsv"

            def is_file_open(self):
                return True

        from dbs_annotator.utils.session_exporter import SessionExporter

        exporter = SessionExporter(MockSessionData())

        patient_id, session_num = exporter._extract_bids_info_from_path()
        assert patient_id == "01"
        assert session_num == ""

    def test_fallback_filename_no_bids(self):
        """Test fallback when file is not BIDS format."""

        class MockSessionData:
            file_path = ""

            def is_file_open(self):
                return True

        from dbs_annotator.utils.session_exporter import SessionExporter

        exporter = SessionExporter(MockSessionData())

        result = exporter._generate_bids_report_filename(".docx")
        assert "dbs_session_report_" in result
        assert result.endswith(".docx")
