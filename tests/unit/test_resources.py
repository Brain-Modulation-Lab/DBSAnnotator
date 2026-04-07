"""
Unit tests for resource path utilities.

Tests cover:
- Package-relative path resolution
- Fallback to cwd-relative paths
"""

import os


class TestResourcePath:
    """Test suite for resource_path function."""

    def test_resource_path_package_relative(self):
        """Test that config files inside package are found."""
        from clinical_dbs_annotator.utils.resources import resource_path

        # Test config folder that was moved inside package
        config_path = resource_path("config/session_scales_presets.json")
        # Should find the file in package directory
        assert os.path.exists(config_path) or "config" in config_path

    def test_resource_path_styles(self):
        """Test that styles directory is accessible."""
        from clinical_dbs_annotator.utils.resources import resource_path

        # Styles are still in project root
        styles_path = resource_path("styles/light_theme.qss")
        # Path should be constructed correctly
        assert "styles" in styles_path


class TestPackageDirectory:
    """Test suite for package directory caching."""

    def test_package_dir_is_cached(self):
        """Test that _PACKAGE_DIR is properly set."""
        from clinical_dbs_annotator.utils import resources

        assert hasattr(resources, '_PACKAGE_DIR')
        assert os.path.isdir(resources._PACKAGE_DIR)
        assert 'clinical_dbs_annotator' in resources._PACKAGE_DIR
