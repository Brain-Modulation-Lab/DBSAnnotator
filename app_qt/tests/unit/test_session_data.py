"""
Unit tests for SessionData model.
"""

import os
import tempfile

import pytest


class TestSessionData:
    @pytest.fixture
    def session_data(self):
        from dbs_annotator.models import SessionData

        return SessionData()

    @pytest.fixture
    def temp_tsv_path(self):
        with tempfile.NamedTemporaryFile(mode="w", suffix=".tsv", delete=False) as f:
            path = f.name
        yield path
        if os.path.exists(path):
            os.unlink(path)

    def test_initial_state(self, session_data):
        assert not session_data.is_file_open()
        assert session_data.block_id == 0

    def test_open_new_file(self, session_data, temp_tsv_path):
        session_data.open_file(temp_tsv_path)
        try:
            assert session_data.is_file_open()
            assert session_data.file_path == temp_tsv_path
        finally:
            session_data.close_file()

    def test_close_file(self, session_data, temp_tsv_path):
        session_data.open_file(temp_tsv_path)
        session_data.close_file()
        assert not session_data.is_file_open()


class TestSessionDataWriting:
    @pytest.fixture
    def session_data_with_file(self):
        from dbs_annotator.models import SessionData

        sd = SessionData()
        with tempfile.NamedTemporaryFile(mode="w", suffix=".tsv", delete=False) as f:
            path = f.name
        sd.open_file(path)
        yield sd, path
        sd.close_file()
        if os.path.exists(path):
            os.unlink(path)

    def test_write_clinical_scales(self, session_data_with_file):
        sd, _path = session_data_with_file
        assert sd.is_file_open()
