"""图表基类：统一主题、留白与坐标换算。"""
from __future__ import annotations

from PyQt5.QtCore import QRectF, Qt
from PyQt5.QtGui import QColor, QPainter, QPen
from PyQt5.QtWidgets import QWidget

from ..theme import LIGHT, Palette, ui_font


class ChartBase(QWidget):
    """所有图表的共同底座：调色板、抗锯齿、空态文案。"""

    def __init__(self, palette: Palette | None = None, parent=None):
        super().__init__(parent)
        self.p = palette or LIGHT
        self.setMouseTracking(True)
        self.setAttribute(Qt.WA_StyledBackground, False)
        self.empty_text = "暂无数据"

    def set_palette(self, palette: Palette) -> None:
        self.p = palette
        self.update()

    # ---- 绘制辅助 ----
    def _painter(self) -> QPainter:
        p = QPainter(self)
        p.setRenderHint(QPainter.Antialiasing, True)
        p.setRenderHint(QPainter.TextAntialiasing, True)
        return p

    def _draw_empty(self, p: QPainter) -> None:
        p.setPen(QColor(self.p.faint))
        p.setFont(ui_font(12))
        p.drawText(self.rect(), Qt.AlignCenter, self.empty_text)

    def _label(self, p: QPainter, rect: QRectF, text: str, color: str | None = None,
               size: int = 10, align=Qt.AlignCenter, bold: bool = False) -> None:
        p.setPen(QColor(color or self.p.faint))
        p.setFont(ui_font(size, bold))
        p.drawText(rect, int(align), text)

    def _grid_pen(self) -> QPen:
        return QPen(QColor(self.p.grid), 1, Qt.SolidLine)
