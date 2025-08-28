from PyQt5.QtGui import QIcon, QPixmap, QPainter, QPainterPath
from PyQt5.QtCore import Qt,  QRectF, QTimer

# graphical elements

def create_arrow_icon(direction="up", double=False):
    arrow_color = "#cccccc"  
    if double:
        if direction == "up":
            svg = f"""
            <svg width="16" height="16" viewBox="0 0 18 18" fill="none">
                <polygon points="4,12 9,7 14,12" fill="{arrow_color}"/>
                <polygon points="4,16 9,11 14,16" fill="{arrow_color}"/>
            </svg>
            """
        else:
            svg = f"""
            <svg width="16" height="16" viewBox="0 0 18 18" fill="none">
                <polygon points="4,6 9,11 14,6" fill="{arrow_color}"/>
                <polygon points="4,2 9,7 14,2" fill="{arrow_color}"/>
            </svg>
            """
    else:
        if direction == "up":
            svg = f"""
            <svg width="16" height="16" viewBox="0 0 18 18" fill="none">
                <polygon points="4,12 9,7 14,12" fill="{arrow_color}"/>
            </svg>
            """
        else:
            svg = f"""
            <svg width="16" height="16" viewBox="0 0 18 18" fill="none">
                <polygon points="4,6 9,11 14,6" fill="{arrow_color}"/>
            </svg>
            """
    pixmap = QPixmap()
    pixmap.loadFromData(bytes(svg, encoding='utf-8'), "SVG")
    return QIcon(pixmap)

def rounded_pixmap(pixmap, radius):
    size = pixmap.size()
    rounded = QPixmap(size)
    rounded.fill(Qt.transparent)
    painter = QPainter(rounded)
    painter.setRenderHint(QPainter.Antialiasing)
    path = QPainterPath()
    path.addRoundedRect(QRectF(0, 0, size.width(), size.height()), radius, radius)
    painter.setClipPath(path)
    painter.drawPixmap(0, 0, pixmap)
    painter.end()
    return rounded

def animate_insert_button(button):
        normal_style = button.styleSheet()
        orange_style = "background-color: #ff6600; color: black;"
        def pulse(times_left):
            if times_left == 0:
                button.setStyleSheet(normal_style)
                return
            button.setStyleSheet(orange_style)
            QTimer.singleShot(120, lambda: (
                button.setStyleSheet(normal_style),
                QTimer.singleShot(120, lambda: pulse(times_left - 1))
            ))
        pulse(3)


# scales

    
