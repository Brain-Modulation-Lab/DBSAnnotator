"""
Run script for Visual Studio Code / Visual Studio.

This is the main entry point for running the Clinical DBS Annotator application
from Visual Studio or any IDE.

Usage:
    python run.py
"""

import sys

from dbs_annotator.__main__ import main

if __name__ == "__main__":
    sys.exit(main())
