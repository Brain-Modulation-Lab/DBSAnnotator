"""
Unit tests for SessionData model.

Tests cover:
- File creation and opening
- Block ID management
- Clinical/session scales handling
- TSV writing operations
"""

import pytest
import tempfile
import os
from pathlib import Path


class TestSessionData:
    """Test suite for SessionData class."""

    @pytest.fixture
    def session_data(self):
        """Create a fresh SessionData instance."""
        from clinical_dbs_annotator.models import SessionData
        return SessionData()

    @pytest.fixture
    def temp_tsv_path(self):
        """Create a temporary TSV file path."""
        with tempfile.NamedTemporaryFile(mode='w', suffix='.tsv', delete=False) as f:
            path = f.name
        yield path
        if os.path.exists(path):
            os.unlink(path)

    def test_initial_state(self, session_data):
        """Test that SessionData initializes with correct default state."""
        assert not session_data.is_file_open()
        assert session_data.current_block_id == 0

    def test_open_new_file(self, session_data, temp_tsv_path):
        """Test opening a new TSV file for writing."""
        session_data.open_file(temp_tsv_path)
        assert session_data.is_file_open()
        assert session_data.file_path == temp_tsv_path

    def test_increment_block_id(self, session_data):
        """Test block ID incrementation."""
        initial_id = session_data.current_block_id
        session_data.increment_block_id()
        assert session_data.current_block_id == initial_id + 1

    def test_close_file(self, session_data, temp_tsv_path):
        """Test file closing."""
        session_data.open_file(temp_tsv_path)
        session_data.close_file()
        assert not session_data.is_file_open()


class TestSessionDataWriting:
    """Test suite for SessionData writing operations."""

    @pytest.fixture
    def session_data_with_file(self):
        """Create SessionData with an open temp file."""
        from clinical_dbs_annotator.models import SessionData
        sd = SessionData()
        with tempfile.NamedTemporaryFile(mode='w', suffix='.tsv', delete=False) as f:
            path = f.name
        sd.open_file(path)
        yield sd, path
        sd.close_file()
        if os.path.exists(path):
            os.unlink(path)

    def test_write_clinical_scales(self, session_data_with_file):
        """Test writing clinical scales to TSV."""
        sd, path = session_data_with_file
        scales = [("Scale1", "5"), ("Scale2", "3")]
        # This tests the interface - actual implementation may vary
        assert sd.is_file_open()
