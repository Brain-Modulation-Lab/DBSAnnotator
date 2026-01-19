"""
Multi-select combo box widget with custom selection rules.

A custom combo box that allows multiple selections with checkboxes
and automatic conflict resolution between mutually exclusive options.
"""

from typing import List

from PyQt5.QtCore import Qt, pyqtSignal
from PyQt5.QtGui import QStandardItem, QStandardItemModel
from PyQt5.QtWidgets import QComboBox, QLineEdit, QHBoxLayout, QWidget


class MultiSelectComboBox(QComboBox):
    """
    A combo box that supports multiple selections using checkboxes.
    
    Includes automatic deselection logic for mutually exclusive options:
    - 'case' is mutually exclusive with all other options
    - '1 ring' is auto-deselected when 1a, 1b, or 1c are selected
    - '2 ring' is auto-deselected when 2a, 2b, or 2c are selected
    """

    selectionChanged = pyqtSignal()

    def __init__(self, parent=None):
        """Initialize the multi-select combo box."""
        super().__init__(parent)

        # Make combo box non-editable but keep lineEdit accessible for events
        self.setEditable(True)
        # Don't set readOnly to allow proper popup behavior
        # self.lineEdit().setReadOnly(True)
        self.lineEdit().setPlaceholderText("Select")
        self.setEditText("")
        self.setFixedWidth(150)

        # Create model for items
        self.model_items = QStandardItemModel(self)
        self.setModel(self.model_items)

        # Set view properties
        view = self.view()

        # Install event filter to detect clicks outside
        view.viewport().installEventFilter(self)

        # Store item list
        self.items = []

    def addItems(self, items: List[str]) -> None:
        """
        Add items to the combo box.

        Args:
            items: List of item strings to add
        """
        self.items = items
        for item_text in items:
            item = QStandardItem(item_text)
            item.setFlags(Qt.ItemIsUserCheckable | Qt.ItemIsEnabled)
            item.setData(Qt.Unchecked, Qt.CheckStateRole)
            self.model_items.appendRow(item)

    def on_item_pressed(self, index) -> None:
        """
        Handle item press event to toggle checkbox with conflict resolution.

        Args:
            index: Model index of the pressed item
        """
        item = self.model_items.itemFromIndex(index)
        item_text = item.text()
        
        # Toggle the clicked item
        new_state = Qt.Unchecked if item.checkState() == Qt.Checked else Qt.Checked
        item.setCheckState(new_state)
        
        # Apply selection rules only if item was just checked
        if new_state == Qt.Checked:
            self._apply_selection_rules(item_text)
        
        # Update the combo box text to show current selections
        self.update_text()
        self.selectionChanged.emit()

    def _apply_selection_rules(self, selected_item: str) -> None:
        """
        Apply mutual exclusion rules when an item is selected.

        Args:
            selected_item: The item that was just selected
        """
        # # Rule 1: 
        if selected_item == "case":
            self._deselect_all_except("case")
        else:
            self._deselect_item("case")
        
        # Rule 2: 
        if selected_item in ["1a", "1b", "1c"]:
            self._deselect_items(["case", "0 ring", "1 ring", "2 ring", "3 ring"])
        if selected_item == "1a":
            if "1b" not in self.get_selected_items():
                self._deselect_item("2b")
            if "1c" not in self.get_selected_items():
                self._deselect_item("2c")
        if selected_item == "1b":
            if "1a" not in self.get_selected_items():
                self._deselect_item("2a")
            if "1c" not in self.get_selected_items():
                self._deselect_item("2c")
        if selected_item == "1c":
            if "1a" not in self.get_selected_items():
                self._deselect_item("2a")
            if "1b" not in self.get_selected_items():
                self._deselect_item("2b")
        
        # Rule 3: 
        if selected_item in ["2a", "2b", "2c"]:
            self._deselect_items(["case", "0 ring", "1 ring", "2 ring", "3 ring"])
        if selected_item == "2a":
            if "2b" not in self.get_selected_items():
                self._deselect_item("1b")
            if "2c" not in self.get_selected_items():
                self._deselect_item("1c")
        if selected_item == "2b":
            if "2a" not in self.get_selected_items():
                self._deselect_item("1a")
            if "2c" not in self.get_selected_items():
                self._deselect_item("1c")
        if selected_item == "2c":
            if "2a" not in self.get_selected_items():
                self._deselect_item("1a")
            if "2b" not in self.get_selected_items():
                self._deselect_item("1b")
        
        # # Rule 4: 
        if selected_item == "1 ring":
            self._deselect_items(["1a", "1b", "1c","2a", "2b", "2c"])
        
        # # Rule 5: 
        if selected_item == "2 ring":
            self._deselect_items(["1a", "1b", "1c","2a", "2b", "2c"])

    def _deselect_items(self, items_to_deselect: List[str]) -> None:
        """
        Deselect multiple items by text.

        Args:
            items_to_deselect: List of item texts to deselect
        """
        for item_text in items_to_deselect:
            self._deselect_item(item_text)

    def _deselect_item(self, item_text: str) -> None:
        """
        Deselect a specific item by text.

        Args:
            item_text: Text of the item to deselect
        """
        for i in range(self.model_items.rowCount()):
            item = self.model_items.item(i)
            if item.text() == item_text:
                item.setCheckState(Qt.Unchecked)
                break

    def _deselect_all_except(self, keep_item: str) -> None:
        """
        Deselect all items except the specified one.

        Args:
            keep_item: Text of the item to keep selected
        """
        for i in range(self.model_items.rowCount()):
            item = self.model_items.item(i)
            if item.text() != keep_item:
                item.setCheckState(Qt.Unchecked)

    def update_text(self) -> None:
        """Update the combo box display text with current selections."""
        selected = self.get_selected_items()
        if selected:
            # Show selections with underscore separator
            self.setEditText("_".join(selected))
        else:
            # Show empty when no selections
            self.setEditText("")

    def get_selected_items(self) -> List[str]:
        """
        Get list of selected item texts.

        Returns:
            List of selected item strings
        """
        selected = []
        for i in range(self.model_items.rowCount()):
            item = self.model_items.item(i)
            if item.checkState() == Qt.Checked:
                selected.append(item.text())
        return selected

    def get_selected_text(self) -> str:
        """
        Get selected items joined with underscore.

        Returns:
            String with selected items joined by underscore
        """
        selected = self.get_selected_items()
        return "_".join(selected) if selected else ""

    def set_selected_items(self, items: List[str]) -> None:
        """
        Set which items are selected.

        Args:
            items: List of item texts to select
        """
        # Clear all selections
        for i in range(self.model_items.rowCount()):
            item = self.model_items.item(i)
            item.setCheckState(Qt.Unchecked)

        # Set specified selections
        for i in range(self.model_items.rowCount()):
            item = self.model_items.item(i)
            if item.text() in items:
                item.setCheckState(Qt.Checked)

        self.update_text()

    def set_selected_from_string(self, value: str) -> None:
        """
        Set selected items from underscore-separated string.

        Args:
            value: String with items separated by underscore
        """
        if not value:
            self.set_selected_items([])
        else:
            items = value.split("_")
            self.set_selected_items(items)

    def showPopup(self) -> None:
        """Show popup."""
        super().showPopup()

    def eventFilter(self, obj, event) -> bool:
        """
        Event filter to handle clicks and key presses.

        Args:
            obj: Object that triggered the event
            event: The event

        Returns:
            True if event was handled, False otherwise
        """
        if event.type() == event.KeyPress:
            if event.key() in (Qt.Key_Escape, Qt.Key_Return, Qt.Key_Enter):
                self.hidePopup()
                return True
        elif event.type() == event.MouseButtonPress:
            if event.button() == Qt.LeftButton:
                # Get the index at the click position
                view = self.view()
                index = view.indexAt(event.pos())
                if index.isValid():
                    # Call our item press handler
                    self.on_item_pressed(index)
                    return True
        return False


class MultiSelectComboBoxWithDisplay(QWidget):
    """
    Widget with dropdown menu showing current selections.
    Uses standard QComboBox popup behavior.
    """

    selectionChanged = pyqtSignal()

    def __init__(self, parent=None):
        """Initialize widget with dropdown menu."""
        super().__init__(parent)

        # Create layout
        layout = QHBoxLayout(self)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(5)

        # Create combo box
        self.combo_box = MultiSelectComboBox()
        self.combo_box.selectionChanged.connect(self._on_selection_changed)

        # Add widgets to layout
        layout.addWidget(self.combo_box)
        layout.addStretch()

        self.setLayout(layout)

    def addItems(self, items: List[str]) -> None:
        """
        Add items to the combo box.

        Args:
            items: List of item strings to add
        """
        self.combo_box.addItems(items)

    def _on_selection_changed(self) -> None:
        """Update display field when selection changes."""
        selected_text = self.combo_box.get_selected_text()
        # Update combo box text to show current selections
        self.combo_box.update_text()
        self.selectionChanged.emit()

    def get_selected_items(self) -> List[str]:
        """
        Get list of selected item texts.

        Returns:
            List of selected item strings
        """
        return self.combo_box.get_selected_items()

    def get_selected_text(self) -> str:
        """
        Get selected items joined with underscore.

        Returns:
            String with selected items joined by underscore
        """
        return self.combo_box.get_selected_text()

    def set_selected_items(self, items: List[str]) -> None:
        """
        Set which items are selected.

        Args:
            items: List of item texts to select
        """
        self.combo_box.set_selected_items(items)
        self._on_selection_changed()

    def set_selected_from_string(self, value: str) -> None:
        """
        Set selected items from underscore-separated string.

        Args:
            value: String with items separated by underscore
        """
        self.combo_box.set_selected_from_string(value)
        self._on_selection_changed()