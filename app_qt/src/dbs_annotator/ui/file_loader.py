"""
File drag-and-drop line edit widget.

Provides a QLineEdit subclass that accepts file drops, invoking a callback
with the dropped file path.
"""

import typing
from collections.abc import Callable

from PySide6.QtGui import QDragEnterEvent, QDropEvent
from PySide6.QtWidgets import QLineEdit


class FileDropLineEdit(QLineEdit):
    """QLineEdit that accepts file drag-and-drop and notifies via callback."""

    def __init__(self, on_file_dropped: Callable[[str], None], parent=None):
        """Initialize with a callback invoked when a file is dropped.

        Args:
            on_file_dropped: Callable receiving the local file path string.
            parent: Optional parent widget.
        """
        super().__init__(parent)
        self._on_file_dropped = on_file_dropped
        self.setAcceptDrops(True)

    @typing.override
    def dragEnterEvent(self, arg__1: QDragEnterEvent) -> None:
        """Accept drag events that carry file URLs."""
        if arg__1.mimeData().hasUrls():
            arg__1.acceptProposedAction()
            return
        super().dragEnterEvent(arg__1)

    @typing.override
    def dropEvent(self, arg__1: QDropEvent) -> None:
        """Handle file drop: extract first URL and invoke callback."""
        if arg__1.mimeData().hasUrls():
            urls = arg__1.mimeData().urls()
            if urls:
                local_path = urls[0].toLocalFile()
                if local_path:
                    self._on_file_dropped(local_path)
            arg__1.acceptProposedAction()
            return
        super().dropEvent(arg__1)
