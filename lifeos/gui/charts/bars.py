"""柱状图 / 分布条：状态分布、进度分布、工具 TopN。"""
from __future__ import annotations

from PyQt5.QtCore import QRectF, Qt, pyqtSignal
from PyQt5.QtGui import QColor
from PyQt5.QtWidgets import QToolTip

from .base import ChartBase


class BarChart(ChartBase):
    """竖直柱状图，柱顶标数值，柱底标类目。"""

    bar_clicked = pyqtSignal(str)

    def __init__(self, palette=None, parent=None):
        super().__init__(palette, parent)
        self.items: list[tuple[str, int, str]] = []   # (标签, 值, 颜色)
        self.setMinimumHeight(150)
        self._bars: list[tuple[QRectF, str, int]] = []

    def set_data(self, items: list[tuple[str, int, str]]) -> None:
        self.items = items or []
        self.update()

    def paintEvent(self, e):
        p = self._painter()
        self._bars.clear()
        if not self.items or all(v == 0 for _, v, _ in self.items):
            self._draw_empty(p)
            p.end()
            return

        top, bottom, side = 22, 24, 10
        w = self.width() - side * 2
        h = self.height() - top - bottom
        n = len(self.items)
        slot = w / n
        bw = min(46, slot * 0.56)
        vmax = max(v for _, v, _ in self.items) or 1

        p.setPen(self._grid_pen())
        p.drawLine(side, self.height() - bottom, self.width() - side, self.height() - bottom)

        for i, (label, value, color) in enumerate(self.items):
            cx = side + slot * (i + 0.5)
            bh = (value / vmax) * h if value else 0
            r = QRectF(cx - bw / 2, self.height() - bottom - bh, bw, bh)
            p.setPen(Qt.NoPen)
            p.setBrush(QColor(color))
            if bh > 0:
                p.drawRoundedRect(r, 4, 4)
            self._bars.append((QRectF(cx - slot / 2, top, slot, h + bottom), label, value))
            self._label(p, QRectF(cx - slot / 2, self.height() - bottom - bh - 17, slot, 15),
                        str(value), self.p.text if value else self.p.faint, 10,
                        Qt.AlignCenter, bold=True)
            self._label(p, QRectF(cx - slot / 2, self.height() - bottom + 4, slot, 15),
                        label, self.p.muted, 10)
        p.end()

    def mouseMoveEvent(self, e):
        hit = next((b for b in self._bars if b[0].contains(e.pos())), None)
        if hit:
            QToolTip.showText(e.globalPos(), f"{hit[1]}：{hit[2]}", self)

    def mousePressEvent(self, e):
        hit = next((b for b in self._bars if b[0].contains(e.pos())), None)
        if hit:
            self.bar_clicked.emit(hit[1])


class HBarChart(ChartBase):
    """横向条形图，适合标签较长的排行（工具 TopN / 错误 TopN / 标签）。"""

    def __init__(self, palette=None, parent=None):
        super().__init__(palette, parent)
        self.items: list[tuple[str, int]] = []
        self.color: str | None = None
        self.setMinimumHeight(120)

    def set_data(self, items: list[tuple[str, int]], color: str | None = None) -> None:
        self.items = items or []
        self.color = color
        self.update()

    def paintEvent(self, e):
        p = self._painter()
        if not self.items:
            self._draw_empty(p)
            p.end()
            return
        pad, label_w, val_w = 4, 96, 34
        n = len(self.items)
        row_h = min(26, max(16, (self.height() - pad * 2) / n))
        bar_area = self.width() - label_w - val_w - pad * 2
        vmax = max(v for _, v in self.items) or 1
        accent = self.color or self.p.accent

        for i, (label, value) in enumerate(self.items):
            y = pad + i * row_h
            self._label(p, QRectF(pad, y, label_w - 8, row_h), _elide(label, 12),
                        self.p.muted, 10, Qt.AlignRight | Qt.AlignVCenter)
            track = QRectF(label_w, y + row_h * 0.25, bar_area, row_h * 0.5)
            p.setPen(Qt.NoPen)
            p.setBrush(QColor(self.p.grid))
            p.drawRoundedRect(track, 3, 3)
            fill = QRectF(track)
            fill.setWidth(max(3.0, bar_area * value / vmax))
            p.setBrush(QColor(accent))
            p.drawRoundedRect(fill, 3, 3)
            self._label(p, QRectF(label_w + bar_area + 6, y, val_w, row_h), str(value),
                        self.p.text, 10, Qt.AlignLeft | Qt.AlignVCenter)
        p.end()


def _elide(s: str, n: int) -> str:
    return s if len(s) <= n else s[: n - 1] + "…"
