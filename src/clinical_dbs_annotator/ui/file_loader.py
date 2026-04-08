"""
File drag-and-drop line edit widget.

Provides a QLineEdit subclass that accepts file drops, invoking a callback
with the dropped file path.
"""
import typing
from collections.abc import Callable

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
    def dragEnterEvent(self, event):
        """Accept drag events that carry file URLs."""
        if event.mimeData().hasUrls():
            event.acceptProposedAction()
            return
        super().dragEnterEvent(event)
    @typing.override
    def dropEvent(self, event):
        """Handle file drop: extract first URL and invoke callback."""
        if event.mimeData().hasUrls():
            urls = event.mimeData().urls()
            if urls:
                local_path = urls[0].toLocalFile()
                if local_path:
                    self._on_file_dropped(local_path)
            event.acceptProposedAction()
            return
        super().dropEvent(event)
