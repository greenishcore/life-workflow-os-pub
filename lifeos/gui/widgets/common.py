"""lifeos.gui.widgets.common — 复用 UI 组件

页面只组装这些组件，不自己画细节，保证整套界面观感统一。
"""
from __future__ import annotations

from PyQt5.QtCore import Qt, pyqtSignal
from PyQt5.QtGui import QColor, QPainter, QPen
from PyQt5.QtWidgets import (
    QFrame, QHBoxLayout, QLabel, QPlainTextEdit, QPushButton,
    QVBoxLayout, QWidget,
)

from ..theme import PAD, Palette, R_SM, mono_font, ui_font


class Card(QFrame):
    """带标题的卡片容器。内容用 self.body 这个 QVBoxLayout 往里加。"""

    def __init__(self, title: str = "", hint: str = "", parent=None):
        super().__init__(parent)
        self.setObjectName("Card")
        outer = QVBoxLayout(self)
        outer.setContentsMargins(PAD, PAD - 2, PAD, PAD)
        outer.setSpacing(10)

        if title:
            head = QHBoxLayout()
            head.setSpacing(8)
            self.title_label = QLabel(title)
            self.title_label.setObjectName("CardTitle")
            head.addWidget(self.title_label)
            if hint:
                hint_label = QLabel(hint)
                hint_label.setObjectName("CardHint")
                head.addWidget(hint_label)
            head.addStretch(1)
            self.header = head
            outer.addLayout(head)

        self.body = QVBoxLayout()
        self.body.setSpacing(8)
        self.body.setContentsMargins(0, 0, 0, 0)
        outer.addLayout(self.body, 1)

    def add_header_widget(self, w: QWidget) -> None:
        if hasattr(self, "header"):
            self.header.addWidget(w)


class StatTile(QFrame):
    """KPI 数字块。"""

    def __init__(self, label: str, value: str = "—", delta: str = "",
                 color: str | None = None, parent=None):
        super().__init__(parent)
        self.setObjectName("Card")
        lay = QVBoxLayout(self)
        lay.setContentsMargins(PAD, 12, PAD, 12)
        lay.setSpacing(2)

        self.value_label = QLabel(value)
        self.value_label.setObjectName("StatValue")
        if color:
            self.value_label.setStyleSheet(f"color: {color}; background: transparent;")
        self.label_label = QLabel(label)
        self.label_label.setObjectName("StatLabel")
        self.delta_label = QLabel(delta)
        self.delta_label.setObjectName("StatDelta")

        lay.addWidget(self.value_label)
        lay.addWidget(self.label_label)
        lay.addWidget(self.delta_label)
        self.setMinimumHeight(96)

    def set_value(self, value: str, delta: str = "") -> None:
        self.value_label.setText(value)
        self.delta_label.setText(delta)


class Badge(QLabel):
    """状态/优先级色标签。"""

    def __init__(self, text: str, color: str, filled: bool = False, parent=None):
        super().__init__(text, parent)
        self.set_style(text, color, filled)
        self.setAlignment(Qt.AlignCenter)
        self.setFont(ui_font(11))

    def set_style(self, text: str, color: str, filled: bool = False) -> None:
        self.setText(text)
        c = QColor(color)
        if filled:
            self.setStyleSheet(
                f"background: {color}; color: white; border-radius: {R_SM}px;"
                f"padding: 2px 8px; font-size: 11px;"
            )
        else:
            soft = f"rgba({c.red()},{c.green()},{c.blue()},38)"
            self.setStyleSheet(
                f"background: {soft}; color: {color}; border-radius: {R_SM}px;"
                f"padding: 2px 8px; font-size: 11px;"
            )


class TagChip(QLabel):
    def __init__(self, text: str, palette: Palette, parent=None):
        super().__init__(f"#{text}", parent)
        self.setStyleSheet(
            f"background: {palette.accent_soft}; color: {palette.accent};"
            f"border-radius: {R_SM}px; padding: 1px 7px; font-size: 11px;"
        )
        self.setFont(ui_font(11))


class Dot(QWidget):
    """小圆点（状态色）。"""

    def __init__(self, color: str, size: int = 9, parent=None):
        super().__init__(parent)
        self._color, self._size = color, size
        self.setFixedSize(size, size)

    def set_color(self, color: str) -> None:
        self._color = color
        self.update()

    def paintEvent(self, e):
        p = QPainter(self)
        p.setRenderHint(QPainter.Antialiasing)
        p.setPen(Qt.NoPen)
        p.setBrush(QColor(self._color))
        p.drawEllipse(0, 0, self._size, self._size)
        p.end()


class ProgressRing(QWidget):
    """环形进度（比长条更省横向空间，适合放在列表行里）。"""

    def __init__(self, value: int = 0, size: int = 34, palette: Palette | None = None, parent=None):
        super().__init__(parent)
        self._value = value
        self._size = size
        self._palette = palette
        self.setFixedSize(size, size)

    def set_value(self, v: int) -> None:
        self._value = max(0, min(100, v))
        self.update()

    def paintEvent(self, e):
        p = QPainter(self)
        p.setRenderHint(QPainter.Antialiasing)
        pal = self._palette
        track = QColor(pal.border if pal else "#e5e7eb")
        accent = QColor(pal.accent if pal else "#4f46e5")
        w = 4
        rect = self.rect().adjusted(w // 2 + 1, w // 2 + 1, -w // 2 - 1, -w // 2 - 1)
        p.setPen(QPen(track, w, Qt.SolidLine, Qt.RoundCap))
        p.drawArc(rect, 0, 360 * 16)
        if self._value > 0:
            p.setPen(QPen(accent, w, Qt.SolidLine, Qt.RoundCap))
            p.drawArc(rect, 90 * 16, -int(360 * 16 * self._value / 100))
        p.setPen(QColor(pal.muted if pal else "#6b7280"))
        p.setFont(ui_font(9))
        p.drawText(self.rect(), Qt.AlignCenter, f"{self._value}")
        p.end()


class Console(QPlainTextEdit):
    """执行日志输出区（等宽、只读、自动滚到底）。"""

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setObjectName("Console")
        self.setReadOnly(True)
        self.setFont(mono_font(11))
        self.setMaximumBlockCount(3000)
        self.setPlaceholderText("执行日志会显示在这里…")

    def log(self, text: str) -> None:
        for line in str(text).rstrip().splitlines() or [""]:
            self.appendPlainText(line)
        self.verticalScrollBar().setValue(self.verticalScrollBar().maximum())

    def rule(self, title: str = "") -> None:
        self.log("─" * 8 + (f" {title} " if title else "") + "─" * 8)


class Divider(QFrame):
    def __init__(self, parent=None):
        super().__init__(parent)
        self.setObjectName("Divider")
        self.setFrameShape(QFrame.HLine)
        self.setFixedHeight(1)


class EmptyState(QWidget):
    """空态提示（比一片空白友好）。"""

    action_clicked = pyqtSignal()

    def __init__(self, icon: str, title: str, hint: str = "",
                 action: str = "", palette: Palette | None = None, parent=None):
        super().__init__(parent)
        lay = QVBoxLayout(self)
        lay.setAlignment(Qt.AlignCenter)
        lay.setSpacing(6)
        muted = palette.muted if palette else "#6b7280"
        faint = palette.faint if palette else "#9ca3af"

        ic = QLabel(icon)
        ic.setAlignment(Qt.AlignCenter)
        ic.setStyleSheet(f"font-size: 34px; color: {faint}; background: transparent;")
        t = QLabel(title)
        t.setAlignment(Qt.AlignCenter)
        t.setStyleSheet(f"color: {muted}; font-size: 13px; background: transparent;")
        lay.addWidget(ic)
        lay.addWidget(t)
        if hint:
            h = QLabel(hint)
            h.setAlignment(Qt.AlignCenter)
            h.setWordWrap(True)
            h.setStyleSheet(f"color: {faint}; font-size: 11px; background: transparent;")
            lay.addWidget(h)
        if action:
            btn = QPushButton(action)
            btn.setObjectName("Primary")
            btn.setCursor(Qt.PointingHandCursor)
            btn.clicked.connect(self.action_clicked.emit)
            row = QHBoxLayout()
            row.addStretch(1)
            row.addWidget(btn)
            row.addStretch(1)
            lay.addSpacing(6)
            lay.addLayout(row)


class PageHeader(QWidget):
    """页面标题栏：标题 + 副标题 + 右侧操作区。"""

    def __init__(self, title: str, subtitle: str = "", parent=None):
        super().__init__(parent)
        lay = QHBoxLayout(self)
        lay.setContentsMargins(0, 0, 0, 0)
        lay.setSpacing(10)
        col = QVBoxLayout()
        col.setSpacing(1)
        self.title_label = QLabel(title)
        self.title_label.setObjectName("PageTitle")
        self.sub_label = QLabel(subtitle)
        self.sub_label.setObjectName("PageSub")
        col.addWidget(self.title_label)
        col.addWidget(self.sub_label)
        lay.addLayout(col)
        lay.addStretch(1)
        self.actions = QHBoxLayout()
        self.actions.setSpacing(8)
        lay.addLayout(self.actions)

    def add_action(self, w: QWidget) -> None:
        self.actions.addWidget(w)

    def set_subtitle(self, text: str) -> None:
        self.sub_label.setText(text)
