#!/usr/bin/env python3
"""
Performance tests for export functionality.

Tests export performance with large datasets.
"""

import sys
import tempfile
import time
import unittest
from pathlib import Path
from unittest.mock import patch

# Add src directory to path
sys.path.insert(0, str(Path(__file__).parent.parent.parent / "src"))

import pandas as pd

from clinical_dbs_annotator.models.session_data import SessionData
from clinical_dbs_annotator.utils.session_exporter import SessionExporter


class TestExportPerformance(unittest.TestCase):
    """Test export performance with large datasets."""

    def setUp(self):
        """Set up performance test environment."""
        # Create large dataset (1000 records)
        self.large_data = []
        for i in range(1000):
            self.large_data.append({
                'date': f'2024-01-{(i % 30) + 1:02d}',
                'time': f'{(i % 24):02d}:{(i % 60):02d}:00',
                'block_id': str((i % 10) + 1),
                'scale_name': ['YBOCS', 'HAM-D', 'BARS'][i % 3],
                'scale_value': str(10 + (i % 40)),
                'stim_freq': '130',
                'left_contact': 'e1-e3',
                'left_amplitude': f'{2.0 + (i % 5):.1f}',
                'left_pulse_width': '60',
                'right_contact': 'e2-e4',
                'right_amplitude': f'{3.0 + (i % 5):.1f}',
                'right_pulse_width': '60',
                'notes': f'Measurement {i+1}'
            })

        # Create temporary TSV file
        self.temp_file = tempfile.NamedTemporaryFile(mode='w', suffix='.tsv', delete=False)
        df = pd.DataFrame(self.large_data)
        df.to_csv(self.temp_file.name, sep='\t', index=False)
        self.temp_file.close()

        # Create session data
        self.session_data = SessionData()
        self.session_data.file_path = self.temp_file.name
        self.exporter = SessionExporter(self.session_data)

    def tearDown(self):
        """Clean up test environment."""
        Path(self.temp_file.name).unlink(missing_ok=True)

    @patch('PyQt5.QtWidgets.QFileDialog.getSaveFileName')
    @patch('PyQt5.QtWidgets.QMessageBox.information')
    def test_excel_export_performance(self, mock_msgbox, mock_file_dialog):
        """Test Excel export performance with large dataset."""
        with tempfile.NamedTemporaryFile(suffix='.xlsx', delete=False) as excel_file:
            excel_path = excel_file.name

        mock_file_dialog.return_value = (excel_path, "Excel Files (*.xlsx)")

        # Measure performance
        start_time = time.time()
        result = self.exporter.export_to_excel()
        end_time = time.time()

        execution_time = end_time - start_time

        self.assertTrue(result)
        self.assertTrue(Path(excel_path).exists())
        self.assertLess(execution_time, 10.0, f"Excel export took too long: {execution_time:.2f}s")
        print(f"Excel export (1000 records): {execution_time:.2f}s")

    @patch('PyQt5.QtWidgets.QFileDialog.getSaveFileName')
    @patch('PyQt5.QtWidgets.QMessageBox.information')
    def test_word_export_performance(self, mock_msgbox, mock_file_dialog):
        """Test Word export performance with large dataset."""
        with tempfile.NamedTemporaryFile(suffix='.docx', delete=False) as word_file:
            word_path = word_file.name

        mock_file_dialog.return_value = (word_path, "Word Files (*.docx)")

        # Measure performance
        start_time = time.time()
        result = self.exporter.export_to_word()
        end_time = time.time()

        execution_time = end_time - start_time

        self.assertTrue(result)
        self.assertTrue(Path(word_path).exists())
        self.assertLess(execution_time, 15.0, f"Word export took too long: {execution_time:.2f}s")
        print(f"Word export (1000 records): {execution_time:.2f}s")

    @patch('PyQt5.QtWidgets.QFileDialog.getSaveFileName')
    @patch('PyQt5.QtWidgets.QMessageBox.information')
    def test_pdf_export_performance(self, mock_msgbox, mock_file_dialog):
        """Test PDF export performance with large dataset."""
        with tempfile.NamedTemporaryFile(suffix='.pdf', delete=False) as pdf_file:
            pdf_path = pdf_file.name

        mock_file_dialog.return_value = (pdf_path, "PDF Files (*.pdf)")

        # Measure performance
        start_time = time.time()
        result = self.exporter.export_to_pdf()
        end_time = time.time()

        execution_time = end_time - start_time

        self.assertTrue(result)
        self.assertTrue(Path(pdf_path).exists())
        self.assertLess(execution_time, 20.0, f"PDF export took too long: {execution_time:.2f}s")
        print(f"PDF export (1000 records): {execution_time:.2f}s")


class TestExportMemory(unittest.TestCase):
    """Test export memory usage."""

    def setUp(self):
        """Set up memory test environment."""
        # Create medium dataset (100 records)
        self.medium_data = []
        for i in range(100):
            self.medium_data.append({
                'date': f'2024-01-{(i % 30) + 1:02d}',
                'time': f'{(i % 24):02d}:{(i % 60):02d}:00',
                'block_id': str((i % 10) + 1),
                'scale_name': ['YBOCS', 'HAM-D', 'BARS'][i % 3],
                'scale_value': str(10 + (i % 40)),
                'stim_freq': '130',
                'left_contact': 'e1-e3',
                'left_amplitude': f'{2.0 + (i % 5):.1f}',
                'left_pulse_width': '60',
                'right_contact': 'e2-e4',
                'right_amplitude': f'{3.0 + (i % 5):.1f}',
                'right_pulse_width': '60',
                'notes': f'Measurement {i+1}'
            })

    def test_memory_usage_during_export(self):
        """Test memory usage doesn't grow excessively."""
        import os

        import psutil

        # Create temporary file
        temp_file = tempfile.NamedTemporaryFile(mode='w', suffix='.tsv', delete=False)
        df = pd.DataFrame(self.medium_data)
        df.to_csv(temp_file.name, sep='\t', index=False)
        temp_file.close()

        try:
            session_data = SessionData()
            session_data.file_path = temp_file.name
            exporter = SessionExporter(session_data)

            # Get initial memory
            process = psutil.Process(os.getpid())
            initial_memory = process.memory_info().rss / 1024 / 1024  # MB

            # Export multiple times
            for _i in range(5):
                with tempfile.NamedTemporaryFile(suffix='.xlsx', delete=False) as excel_file:
                    with patch('PyQt5.QtWidgets.QFileDialog.getSaveFileName', return_value=(excel_file.name, "Excel Files (*.xlsx)")):
                        with patch('PyQt5.QtWidgets.QMessageBox.information'):
                            exporter.export_to_excel()
                    Path(excel_file.name).unlink(missing_ok=True)

                # Check memory after each export
                current_memory = process.memory_info().rss / 1024 / 1024  # MB
                memory_growth = current_memory - initial_memory

                self.assertLess(memory_growth, 100, f"Memory grew too much: {memory_growth:.2f}MB")

            print(f"Memory usage after 5 exports: {current_memory:.2f}MB (growth: {memory_growth:.2f}MB)")

        finally:
            Path(temp_file.name).unlink(missing_ok=True)


if __name__ == '__main__':
    unittest.main()
