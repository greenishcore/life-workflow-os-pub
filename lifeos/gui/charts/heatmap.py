"""日历热力图：每日活跃度（新建想法 + 写下的思路注释）。"""
from __future__ import annotations

import datetime as _dt

from PyQt5.QtCore import QRectF, Qt, pyqtSignal
from PyQt5.QtGui import QColor
from PyQt5.QtWidgets import QToolTip

from .base import ChartBase

WEEKDAY_LABELS = ["一", "", "三", "", "五", "", "日"]


class HeatmapCalendar(ChartBase):
    """GitHub 贡献图风格：列=周，行=星期。滚动窗口自动适配宽度。"""

    day_clicked = pyqtSignal(str)

    def __init__(self, palette=None, parent=None):
        super().__init__(palette, parent)
        self.data: dict[str, int] = {}
        self.end_date: _dt.date = _dt.date.today()
        self.setMinimumHeight(150)
        self._cells: list[tuple[QRectF, str, int]] = []
        self.empty_text = "还没有记录，去「捕捉」写下第一条想法"

    def set_data(self, data: dict[str, int], end_date: str | None = None) -> None:
        self.data = data or {}
        if end_date:
            try:
                self.end_date = _dt.date.fromisoformat(end_date)
            except ValueError:
                self.end_date = _dt.date.today()
        elif self.data:
            self.end_date = max(_dt.date.fromisoformat(d) for d in self.data)
        self.end_date = max(self.end_date, _dt.date.today())
        self.update()

    def _color_for(self, v: int, vmax: int) -> QColor:
        steps = self.p.heat
        if v <= 0:
            return QColor(steps[0])
        idx = 1 + min(len(steps) - 2, int((v - 1) / max(1, vmax) * (len(steps) - 1)))
        return QColor(steps[min(idx, len(steps) - 1)])

    def paintEvent(self, e):
        p = self._painter()
        self._cells.clear()
        left_pad, top_pad, bottom_pad = 24, 20, 22
        w = self.width() - left_pad - 8
        h = self.height() - top_pad - bottom_pad
        if w <= 0 or h <= 0:
            p.end()
            return

        cell = max(8, min(18, int(h / 7) - 3))
        gap = max(2, cell // 6)
        step = cell + gap
        weeks = max(4, int(w // step))

        # 结束于 end_date 所在周的周日
        end = self.end_date + _dt.timedelta(days=(6 - self.end_date.weekday()))
        start = end - _dt.timedelta(days=weeks * 7 - 1)
        vmax = max(self.data.values()) if self.data else 1

        # 星期标签
        for i, lab in enumerate(WEEKDAY_LABELS):
            if lab:
                self._label(p, QRectF(0, top_pad + i * step, left_pad - 6, cell),
                            lab, self.p.faint, 9, Qt.AlignRight | Qt.AlignVCenter)

        last_month, last_label_wi = None, -99
        today_s = _dt.date.today().strftime("%Y-%m-%d")
        for wi in range(weeks):
            for di in range(7):
                day = start + _dt.timedelta(days=wi * 7 + di)
                if day > self.end_date:
                    continue
                x = left_pad + wi * step
                y = top_pad + di * step
                v = self.data.get(day.strftime("%Y-%m-%d"), 0)
                r = QRectF(x, y, cell, cell)
                p.setPen(Qt.NoPen)
                p.setBrush(self._color_for(v, vmax))
                p.drawRoundedRect(r, 2.5, 2.5)
                if day.strftime("%Y-%m-%d") == today_s:
                    p.setPen(QColor(self.p.accent))
                    p.setBrush(Qt.NoBrush)
                    p.drawRoundedRect(r.adjusted(-1, -1, 1, 1), 3.5, 3.5)
                self._cells.append((r, day.strftime("%Y-%m-%d"), v))

            # 月份标签（每月第一次出现时）
            first = start + _dt.timedelta(days=wi * 7)
            if first.month != last_month and wi - last_label_wi >= 3:
                last_month, last_label_wi = first.month, wi
                self._label(p, QRectF(left_pad + wi * step - 4, 2, 40, 14),
                            f"{first.month}月", self.p.faint, 9, Qt.AlignLeft | Qt.AlignVCenter)

        # 图例
        legend_y = top_pad + 7 * step + 6
        self._label(p, QRectF(left_pad, legend_y, 24, 14), "少", self.p.faint, 9,
                    Qt.AlignLeft | Qt.AlignVCenter)
        for i, c in enumerate(self.p.heat):
            p.setPen(Qt.NoPen)
            p.setBrush(QColor(c))
            p.drawRoundedRect(QRectF(left_pad + 22 + i * 13, legend_y + 2, 10, 10), 2, 2)
        self._label(p, QRectF(left_pad + 22 + len(self.p.heat) * 13 + 3, legend_y, 24, 14),
                    "多", self.p.faint, 9, Qt.AlignLeft | Qt.AlignVCenter)
        p.end()

    def _hit(self, pos):
        return next((c for c in self._cells if c[0].contains(pos)), None)

    def mouseMoveEvent(self, e):
        hit = self._hit(e.pos())
        if hit:
            _, day, v = hit
            QToolTip.showText(e.globalPos(), f"{day}\n{v} 次活动" if v else f"{day}\n无活动", self)
        else:
            QToolTip.hideText()

    def mousePressEvent(self, e):
        hit = self._hit(e.pos())
        if hit:
            self.day_clicked.emit(hit[1])
