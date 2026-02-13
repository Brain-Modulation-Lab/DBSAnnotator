"""
DBS Electrode 3D Interactive Viewer
Interactive 3D visualization of deep brain stimulation electrodes
with anodic/cathodic modes and case (ground) support
Based on Lead-DBS repository models
"""

from PyQt5.QtWidgets import QWidget
from PyQt5.QtCore import Qt, QRectF, QPointF
from PyQt5.QtGui import QPainter, QColor, QPen, QBrush, QFont, QPolygonF, QPalette, QPainterPath, QPainterPathStroker, QLinearGradient, QRadialGradient

# Import configuration
from ..config_electrode_models import (ContactState, ElectrodeModel, ELECTRODE_MODELS, 
                    MANUFACTURERS, get_all_manufacturers, StimulationRule)


class ElectrodeCanvas(QWidget):
    """Canvas for drawing 2D electrode visualization with clickable contacts"""
    
    def __init__(self, parent=None):
        """Initialize the electrode canvas with default empty state."""
        super().__init__(parent)
        self.model = None

        self.contact_states = {}  # {(contact_idx, segment_idx): ContactState}
        self.case_state = ContactState.OFF  # Case (ground) state
        self.contact_rects = {}  # Dictionary to store contact positions
        self.contact_hit_areas = {}  # {(contact_idx, segment_idx): QPainterPath}
        self.ring_rects = {}  # Dictionary for ring "caps" on directional electrodes
        self.case_rect = None  # Case rectangle
        self.hovered_contact = None
        self.hovered_ring = None
        self.hovered_case = False
        self.validation_callback = None  # Callback for validation
        self.setMinimumWidth(120)
        self.setContentsMargins(2, 2, 2, 2)
        self.setAutoFillBackground(False)
        self.setMouseTracking(True)
        self.setCursor(Qt.PointingHandCursor)
        self.export_mode = False

    def set_export_mode(self, enabled: bool) -> None:
        """Toggle export mode (tighter padding, larger scale for PNG output)."""
        self.export_mode = bool(enabled)
        self.update()
        
    def set_model(self, model):
        """Set the electrode model and reset all states"""
        self.model = model
        self.contact_states.clear()
        self.case_state = ContactState.OFF
        self.contact_rects.clear()
        self.contact_hit_areas.clear()
        self.ring_rects.clear()
        self.case_rect = None
        self.hovered_contact = None
        self.hovered_ring = None
        self.hovered_case = False
        self.update()
        
    def _is_contact_directional(self, contact_idx: int) -> bool:
        """Return True if the given contact index is a segmented (directional) contact."""
        if not self.model or not self.model.is_directional:
            return False
        return 0 < contact_idx < self.model.num_contacts - 1
        
    def calculate_scale(self):
        """Calculate optimal scale to fit electrode in canvas based on height only"""
        if not self.model:
            return 20
            
        contacts_total_mm = (
            self.model.num_contacts * self.model.contact_height
            + max(0, self.model.num_contacts - 1) * self.model.contact_spacing
        )
        total_height_mm = contacts_total_mm + 18
        
        # Calculate scale based on height only
        # In export mode, reduce top/bottom padding so the electrode occupies more space.
        available_height = max(1, self.height() - (10 if self.export_mode else 60))
        
        scale_height = available_height / total_height_mm
        
        # Apply only height-based scaling with max limit
        max_scale = 80 if self.export_mode else 40
        return min(scale_height * 1.2, max_scale)
        
    def get_contact_at_pos(self, pos):
        """Return contact (contact_index, segment_index) at mouse position"""
        point = QPointF(pos)
        for contact_id, hit_area in self.contact_hit_areas.items():
            if hit_area.contains(point):
                return contact_id
        return None
    
    def get_ring_at_pos(self, pos):
        """Return ring index at mouse position"""
        for ring_idx, rect in self.ring_rects.items():
            # Make ring easier to click
            pad = 6
            if rect.adjusted(-pad, -pad, pad, pad).contains(pos):
                return ring_idx
        return None
    
    def is_case_at_pos(self, pos):
        """Check if mouse is over the case"""
        if self.case_rect and self.case_rect.contains(pos):
            return True
        return False
    
    def _apply_change_if_valid(self, new_contact_states, new_case_state):
        """Apply new contact/case states and invoke validation callback."""
        is_valid, error_msg = StimulationRule.validate_configuration(
            new_contact_states,
            new_case_state,
        )

        # Always apply the change regardless of validation
        self.contact_states = new_contact_states
        self.case_state = new_case_state

        if self.validation_callback:
            self.validation_callback(is_valid, error_msg)
        self.update()
        return is_valid

    def cycle_contact_state(self, contact_id):
        """Cycle contact state: OFF -> ANODIC -> CATHODIC -> OFF"""
        new_states = dict(self.contact_states)
        current_state = new_states.get(contact_id, ContactState.OFF)

        if current_state == ContactState.OFF:
            new_states[contact_id] = ContactState.ANODIC
        elif current_state == ContactState.ANODIC:
            new_states[contact_id] = ContactState.CATHODIC
        elif current_state == ContactState.CATHODIC:
            if contact_id in new_states:
                del new_states[contact_id]

        self._apply_change_if_valid(new_states, self.case_state)
    
    def cycle_case_state(self):
        """Cycle case state: OFF -> ANODIC -> CATHODIC -> OFF"""
        new_case_state = self.case_state
        if self.case_state == ContactState.OFF:
            new_case_state = ContactState.ANODIC
        elif self.case_state == ContactState.ANODIC:
            new_case_state = ContactState.CATHODIC
        elif self.case_state == ContactState.CATHODIC:
            new_case_state = ContactState.OFF

        self._apply_change_if_valid(dict(self.contact_states), new_case_state)
    
    def set_ring_state(self, ring_idx, state):
        """Set state for all segments of a ring"""
        if not self.model or not self.model.is_directional or not self._is_contact_directional(ring_idx):
            return

        new_states = dict(self.contact_states)
        for seg in range(3):
            contact_id = (ring_idx, seg)
            if state == ContactState.OFF:
                if contact_id in new_states:
                    del new_states[contact_id]
            else:
                new_states[contact_id] = state

        self._apply_change_if_valid(new_states, self.case_state)
        
    def mousePressEvent(self, event):
        """Handle clicks on contacts, rings and case"""
        if event.button() == Qt.LeftButton:
            # Check if a contact was clicked
            contact_id = self.get_contact_at_pos(event.pos())
            if contact_id:
                self.cycle_contact_state(contact_id)
                return

            # Check if a ring (cap) was clicked
            ring_idx = self.get_ring_at_pos(event.pos())
            if ring_idx is not None:
                # Cycle entire ring state
                states = []
                for seg in range(3):
                    contact_id = (ring_idx, seg)
                    states.append(self.contact_states.get(contact_id, ContactState.OFF))
                
                # Determine predominant state
                if all(s == ContactState.OFF for s in states):
                    new_state = ContactState.ANODIC
                elif all(s == ContactState.ANODIC for s in states):
                    new_state = ContactState.CATHODIC
                else:
                    new_state = ContactState.OFF
                
                self.set_ring_state(ring_idx, new_state)
                return
            
            # Check if case was clicked
            if self.is_case_at_pos(event.pos()):
                self.cycle_case_state()
                return
                
    def mouseMoveEvent(self, event):
        """Handle hover over contacts, rings and case"""
        old_hovered_contact = self.hovered_contact
        old_hovered_ring = self.hovered_ring
        old_hovered_case = self.hovered_case
        
        self.hovered_case = self.is_case_at_pos(event.pos())
        self.hovered_ring = self.get_ring_at_pos(event.pos())
        self.hovered_contact = self.get_contact_at_pos(event.pos())
        
        if (old_hovered_contact != self.hovered_contact or 
            old_hovered_ring != self.hovered_ring or
            old_hovered_case != self.hovered_case):
            self.update()
    
    def get_state_color(self, state, is_hovered=False):
        """Return color based on state"""
        if state == ContactState.ANODIC:
            base_color = QColor(255, 100, 100)  # Red for anodic
            border_color = QColor(200, 50, 50)
        elif state == ContactState.CATHODIC:
            base_color = QColor(100, 150, 255)  # Blue for cathodic
            border_color = QColor(50, 100, 200)
        else: 
            base_color = QColor(150, 150, 150)  # Gray for OFF
            border_color = QColor(50, 50, 50)
        
        if is_hovered:
            base_color = base_color.lighter(120)
            border_color = border_color.lighter(120)
        
        border_width = 3 if state != ContactState.OFF else 1
        if is_hovered:
            border_width += 1
            
        return base_color, border_color, border_width
            
    def paintEvent(self, event):
        """Render the electrode lead, contacts, case, and labels."""
        if not self.model:
            return
            
        painter = QPainter(self)
        painter.setRenderHint(QPainter.Antialiasing)
        painter.setRenderHint(QPainter.SmoothPixmapTransform)
        
        # Background
        palette = self.palette()
       #painter.fillRect(self.rect(), palette.color(QPalette.Window))
        
        # Calculate optimal scale
        scale = self.calculate_scale()
        
        # Canvas center
        center_x = self.width() / 2 - 4
        top_padding = 2 if self.export_mode else 7
        
        # Clear position dictionaries
        self.contact_rects.clear()
        self.contact_hit_areas.clear()
        self.ring_rects.clear()
        
        # Draw case (ground) at the top
        case_height = 4 * scale
        case_width = self.model.lead_diameter * scale * 1.35 + 10
        case_x = center_x - case_width / 2
        case_y = top_padding
        start_y = case_y + case_height + (8 if self.export_mode else 15)
        
        self.case_rect = QRectF(case_x, case_y, case_width, case_height)
        
        color, border_color, border_width = self.get_state_color(
            self.case_state, 
            self.hovered_case
        )
        painter.setBrush(QBrush(color))
        painter.setPen(QPen(border_color, border_width))
        painter.drawRoundedRect(self.case_rect, 5, 5)

        # 3D gradient for case
        case_gradient = QLinearGradient(case_x, case_y, case_x, case_y + case_height)
        color, border_color, border_width = self.get_state_color(
            self.case_state, 
            self.hovered_case
        )
        case_gradient.setColorAt(0, color.lighter(130))
        case_gradient.setColorAt(0.5, color)
        case_gradient.setColorAt(1, color.darker(120))
        
        painter.setBrush(QBrush(case_gradient))
        painter.setPen(QPen(border_color, border_width))
        painter.drawRoundedRect(self.case_rect, 5, 5)
        
        # Add specular highlight on case
        highlight_rect = QRectF(case_x + 2, case_y + 1, case_width * 0.4, case_height * 0.3)
        painter.setBrush(QColor(255, 255, 255, 40))
        painter.setPen(Qt.NoPen)
        painter.drawRoundedRect(highlight_rect, 3, 3)
        
        # Case label - smaller font in export mode
        painter.setPen(Qt.white if self.case_state != ContactState.OFF else Qt.black)
        case_font_size = max(7, int(scale * 0.35)) if self.export_mode else max(8, int(scale * 0.4))
        font = QFont('Arial', case_font_size, QFont.Bold)
        painter.setFont(font)
        painter.drawText(self.case_rect, Qt.AlignCenter, "CASE")
        
        # Draw electrode body (lead)
        lead_width = self.model.lead_diameter * scale * 1.8
        
        # Calculate where E0 (bottom contact) will be positioned
        contact_height_px = self.model.contact_height * scale
        # E0 is the last contact (index 0), positioned after all other contacts and their spacing
        e0_y_position = start_y + 2 * scale  # Initial offset
        for i in range(self.model.num_contacts - 1):  # All contacts except E0
            e0_y_position += contact_height_px + (self.model.contact_spacing + 1.0) * scale
        
        # Lead should end just below E0 (0.3mm tail - minimal overhang)
        total_height = e0_y_position + contact_height_px + 0.3 * scale - start_y
        
        # Create linear gradient for cylindrical effect (no spotlight)
        lead_gradient = QLinearGradient(
            center_x - lead_width/2, start_y,
            center_x + lead_width/2, start_y
        )
        
        base_color = palette.color(QPalette.Midlight)
        lead_gradient.setColorAt(0, base_color.darker(120))
        lead_gradient.setColorAt(0.3, base_color)
        lead_gradient.setColorAt(0.7, base_color)
        lead_gradient.setColorAt(1, base_color.darker(120))
        
        painter.setBrush(QBrush(lead_gradient))
        painter.setPen(QPen(palette.color(QPalette.Dark), 2))
        painter.drawRoundedRect(
            int(center_x - lead_width/2),
            int(start_y),
            int(lead_width),
            int(total_height),
            int(lead_width/4),
            int(lead_width/4)
        )

        # Add ambient occlusion (subtle shadows on edges)
        shadow_left = QLinearGradient(
            center_x - lead_width/2, start_y,
            center_x - lead_width/2 + lead_width * 0.1, start_y
        )
        shadow_left.setColorAt(0, QColor(0, 0, 0, 30))
        shadow_left.setColorAt(1, QColor(0, 0, 0, 0))
        painter.setBrush(QBrush(shadow_left))
        painter.setPen(Qt.NoPen)
        painter.drawRect(
            int(center_x - lead_width/2),
            int(start_y),
            int(lead_width * 0.1),
            int(total_height)
        )
        
        shadow_right = QLinearGradient(
            center_x + lead_width/2 - lead_width * 0.1, start_y,
            center_x + lead_width/2, start_y
        )
        shadow_right.setColorAt(0, QColor(0, 0, 0, 0))
        shadow_right.setColorAt(1, QColor(0, 0, 0, 30))
        painter.setBrush(QBrush(shadow_right))
        painter.drawRect(
            int(center_x + lead_width/2 - lead_width * 0.1),
            int(start_y),
            int(lead_width * 0.1),
            int(total_height)
        )
        
        # Draw contacts with metallic 3D appearance
        current_y = start_y + 2 * scale
        base_extension = lead_width * 0.22 if self.model.is_directional else 0
         
        for i in range(self.model.num_contacts):
            contact_height_px = self.model.contact_height * scale
            contact_number = self.model.num_contacts - 1 - i
            contact_idx = contact_number
            is_directional_contact = self._is_contact_directional(contact_idx)
             
            if is_directional_contact:
                # Store ring cap position but don't draw yet - will draw after contacts
                ring_cap_height = contact_height_px * 0.8
                ring_cap_width = lead_width * 1.1  # Will be recalculated below
                ring_cap_rect = QRectF(
                    center_x - ring_cap_width/2,
                    current_y - ring_cap_height * 0.7,
                    ring_cap_width,
                    ring_cap_height
                )
                self.ring_rects[contact_idx] = ring_cap_rect
                
                #  Directional electrode with 3D metallic segments
                segment_width = lead_width * 0.5
                extension = base_extension
                
                # Helper function to draw 3D segment
                def draw_3d_segment(poly, state, is_hovered, contact_id, label):
                    color, border, width = self.get_state_color(state, is_hovered)
                    
                    # Create gradient for metallic appearance
                    bounds = poly.boundingRect()
                    segment_gradient = QRadialGradient(
                        bounds.center().x(),
                        bounds.center().y(),
                        bounds.width() * 0.6
                    )
                    segment_gradient.setColorAt(0, color.lighter(150))
                    segment_gradient.setColorAt(0.5, color.lighter(110))
                    segment_gradient.setColorAt(0.9, color.darker(110))
                    segment_gradient.setColorAt(1, color.darker(130))
                    
                    # Draw shadow beneath segment
                    shadow_poly = QPolygonF(poly)
                    shadow_poly.translate(1, 2)
                    painter.setBrush(QColor(0, 0, 0, 30))
                    painter.setPen(Qt.NoPen)
                    painter.drawPolygon(shadow_poly)
                    
                    # Draw main segment
                    painter.setBrush(QBrush(segment_gradient))
                    painter.setPen(QPen(border, width))
                    painter.drawPolygon(poly)
                    
                    # Add specular highlight
                    if state != ContactState.OFF:
                        highlight_poly = QPolygonF([
                            QPointF(bounds.left() + bounds.width() * 0.2, bounds.top()),
                            QPointF(bounds.left() + bounds.width() * 0.5, bounds.top()),
                            QPointF(bounds.left() + bounds.width() * 0.4, bounds.top() + bounds.height() * 0.3),
                            QPointF(bounds.left() + bounds.width() * 0.1, bounds.top() + bounds.height() * 0.3)
                        ])
                        painter.setBrush(QColor(255, 255, 255, 40))
                        painter.setPen(Qt.NoPen)
                        painter.drawPolygon(highlight_poly)
                    
                    self.contact_rects[contact_id] = bounds
                    path = QPainterPath()
                    path.addPolygon(poly)
                    # Expand clickable area for better UX
                    stroker = QPainterPathStroker()
                    stroker.setWidth(max(10.0, scale * 0.8))
                    self.contact_hit_areas[contact_id] = stroker.createStroke(path).united(path)
                    
                    # Label - smaller font in export mode
                    painter.setPen(Qt.white if state != ContactState.OFF else Qt.black)
                    font_size = max(6, int(scale * 0.3)) if self.export_mode else max(7, int(scale * 0.4))
                    font = QFont('Arial', font_size, QFont.Bold)
                    painter.setFont(font)
                    painter.drawText(bounds, Qt.AlignCenter, label)
                
                # Segment 'a' (left) - extends left
                contact_id_a = (contact_idx, 0)
                state_a = self.contact_states.get(contact_id_a, ContactState.OFF)
                is_hovered_a = contact_id_a == self.hovered_contact

                # Calculate positions to center b and prevent overlap
                b_width = lead_width * 0.55
                b_left = center_x - b_width/2
                
                x_left = center_x - lead_width/2 - extension
                poly_a = QPolygonF([
                    QPointF(x_left-2, current_y),
                    QPointF(b_left - 1, current_y),  # 2px gap from b
                    QPointF(b_left - 2, current_y + contact_height_px),
                    QPointF(x_left + extension/2, current_y + contact_height_px)
                ])
                draw_3d_segment(poly_a, state_a, is_hovered_a, contact_id_a, "a")

                # Segment 'b' (center)
                contact_id_b = (contact_idx, 1)
                state_b = self.contact_states.get(contact_id_b, ContactState.OFF)
                is_hovered_b = contact_id_b == self.hovered_contact

                rect_b = QRectF(
                    b_left,
                    current_y,
                    b_width,
                    contact_height_px
                )
                
                # Convert rect to polygon for consistent rendering
                poly_b = QPolygonF([
                    rect_b.topLeft(),
                    rect_b.topRight(),
                    rect_b.bottomRight(),
                    rect_b.bottomLeft()
                ])
                draw_3d_segment(poly_b, state_b, is_hovered_b, contact_id_b, "b")
                
                # Segment 'c' (right) - extends right
                contact_id_c = (contact_idx, 2)
                state_c = self.contact_states.get(contact_id_c, ContactState.OFF)
                is_hovered_c = contact_id_c == self.hovered_contact
                
                x_right = center_x + lead_width/2 + extension
                poly_c = QPolygonF([
                    QPointF(b_left + b_width + 2, current_y),  # 2px gap from b
                    QPointF(x_right + 2, current_y),
                    QPointF(x_right - extension/2, current_y + contact_height_px),
                    QPointF(b_left + b_width + 2, current_y + contact_height_px)
                ])
                draw_3d_segment(poly_c, state_c, is_hovered_c, contact_id_c, "c")
                
                # Recalculate ring cap to align with segment edges
                a_left = center_x - lead_width/2 - extension
                c_right = center_x + lead_width/2 + extension
                ring_cap_width = c_right - a_left
                ring_cap_rect = QRectF(
                    a_left,
                    current_y - ring_cap_height * 0.7,
                    ring_cap_width,
                    ring_cap_height
                )
                self.ring_rects[contact_idx] = ring_cap_rect  # Update with corrected position
                
            else:
                # Standard electrode without segments (also used for first/last contacts in directional leads)
                contact_id = (contact_idx, 0)
                contact_state = self.contact_states.get(contact_id, ContactState.OFF)
                is_hovered = contact_id == self.hovered_contact
                
                color, border_color, border_width = self.get_state_color(
                    contact_state, 
                    is_hovered
                )
                
                painter.setBrush(QBrush(color))
                painter.setPen(QPen(border_color, border_width))
                
                # Draw contact with cylindrical gradient
                rect = QRectF(
                    center_x - lead_width/2 + 2,
                    current_y,
                    lead_width - 4,
                    contact_height_px
                )
                
                # Radial gradient for cylindrical contact
                contact_gradient = QRadialGradient(
                    rect.center().x(),
                    rect.center().y(),
                    rect.width() * 0.6
                )
                contact_gradient.setColorAt(0, color.lighter(150))
                contact_gradient.setColorAt(0.5, color.lighter(110))
                contact_gradient.setColorAt(0.85, color.darker(110))
                contact_gradient.setColorAt(1, color.darker(130))
                
                # Draw shadow
                shadow_rect = QRectF(rect)
                shadow_rect.translate(0, 2)
                painter.setBrush(QColor(0, 0, 0, 20))
                painter.setPen(Qt.NoPen)
                painter.drawRoundedRect(shadow_rect, 3, 3)
                
                # Draw contact
                painter.setBrush(QBrush(contact_gradient))
                painter.setPen(QPen(border_color, border_width))
                painter.drawRoundedRect(rect, 3, 3)
                
                # Add specular highlight for metallic appearance
                if contact_state != ContactState.OFF:
                    highlight_rect = QRectF(
                        rect.left() + rect.width() * 0.15,
                        rect.top() + 1,
                        rect.width() * 0.3,
                        rect.height() * 0.4
                    )
                    painter.setBrush(QColor(255, 255, 255, 50))
                    painter.setPen(Qt.NoPen)
                    painter.drawRoundedRect(highlight_rect, 2, 2)
                
                # Store position
                self.contact_rects[contact_id] = rect
                path = QPainterPath()
                path.addRoundedRect(rect, 3, 3)
                # Expand clickable area for better UX
                stroker = QPainterPathStroker()
                stroker.setWidth(max(10.0, scale * 0.9))
                self.contact_hit_areas[contact_id] = stroker.createStroke(path).united(path)
            
            # Contact number on the left - smaller font in export mode
            painter.setPen(palette.color(QPalette.Text))
            elabel_size = max(7, int(scale * 0.35)) if self.export_mode else max(10, int(scale * 0.5))
            font = QFont('Arial', elabel_size, QFont.Bold)
            painter.setFont(font)
            
            label_extension = base_extension if is_directional_contact else 0
            extra_offset = label_extension + 15 if is_directional_contact else 0
            
            # Adjust horizontal position for better alignment
            if is_directional_contact:
                label_x = center_x - lead_width/2 - label_extension - 22 - extra_offset
            else:
                # For ring contacts, center the label relative to the contact rectangle
                contact_rect_x = center_x - lead_width/2 + 2
                contact_rect_width = lead_width - 4
                label_x = contact_rect_x + contact_rect_width/2 - 30
            
            # Label format
            contact_label = f"E{contact_idx}"
            
            painter.drawText(
                int(label_x),
                int(current_y),
                35,
                int(contact_height_px),
                Qt.AlignVCenter | Qt.AlignRight,
                contact_label
            )
            
            # Spacing between contacts - reasonable vertical space for clickability
            current_y += contact_height_px + (self.model.contact_spacing + 1.0) * scale
        
        # Draw ring caps on top of contacts (after all contacts are drawn)
        for contact_idx, ring_cap_rect in self.ring_rects.items():
            # Cap color based on ring state
            ring_states = [self.contact_states.get((contact_idx, seg), ContactState.OFF) 
                          for seg in range(3)]
            if all(s == ContactState.ANODIC for s in ring_states):
                ring_state = ContactState.ANODIC
            elif all(s == ContactState.CATHODIC for s in ring_states):
                ring_state = ContactState.CATHODIC
            else:
                ring_state = ContactState.OFF
            
            is_ring_hovered = self.hovered_ring == contact_idx
            cap_color, cap_border, cap_width = self.get_state_color(
                ring_state, 
                is_ring_hovered
            )
            
            # 3D gradient for ring cap
            ring_gradient = QLinearGradient(
                ring_cap_rect.left(),
                ring_cap_rect.top(),
                ring_cap_rect.left(),
                ring_cap_rect.bottom()
            )
            ring_gradient.setColorAt(0, cap_color.lighter(150))
            ring_gradient.setColorAt(0.3, cap_color.lighter(120))
            ring_gradient.setColorAt(1, cap_color.darker(80))
            
            # Draw shadow
            shadow_rect = QRectF(ring_cap_rect)
            shadow_rect.translate(0, 1)
            painter.setBrush(QColor(0, 0, 0, 25))
            painter.setPen(Qt.NoPen)
            painter.drawRoundedRect(shadow_rect, 3, 3)
            
            # Draw ring cap
            painter.setBrush(QBrush(ring_gradient))
            painter.setPen(QPen(cap_border, cap_width))
            painter.drawRoundedRect(ring_cap_rect, 3, 3)
            
            # Add highlight
            if ring_state != ContactState.OFF:
                highlight = QRectF(
                    ring_cap_rect.left() + ring_cap_rect.width() * 0.2,
                    ring_cap_rect.top() + 1,
                    ring_cap_rect.width() * 0.4,
                    ring_cap_rect.height() * 0.4
                )
                painter.setBrush(QColor(255, 255, 255, 50))
                painter.setPen(Qt.NoPen)
                painter.drawRoundedRect(highlight, 2, 2)
            
            # Ring label - smaller font in export mode
            painter.setPen(Qt.white if ring_state != ContactState.OFF else Qt.black)
            ring_font_size = max(6, int(scale * 0.3)) if self.export_mode else max(7, int(scale * 0.3))
            font = QFont('Arial', ring_font_size)
            painter.setFont(font)
            painter.drawText(ring_cap_rect, Qt.AlignCenter, "Ring")

        
    def resizeEvent(self, event):
        """Redraw when window is resized"""
        super().resizeEvent(event)
        self.update()