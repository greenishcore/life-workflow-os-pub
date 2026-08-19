"""融合时间轴：一张图同时表达 时间 × 精力 × 优先级 × 状态 × 思维轨迹

与原先 ECharts 版散点图的关键差别：每条想法不再是孤立的一个点，
而是一条**生命线**——从「产生」那天延伸到最后一条思路注释，
沿线的刻度就是思维演进的时刻。这样看板才真正回答得了
「这个想法何时产生、如何演进、现在到哪一步」。
"""
from __future__ import annotations

import datetime as _dt

from PyQt5.QtCore import QPointF, QRectF, Qt, pyqtSignal
from PyQt5.QtGui import QColor, QPen
from PyQt5.QtWidgets import QToolTip

from ...models import Item
from .base import ChartBase


class TimelineChart(ChartBase):
    """X=时间，Y=精力，点径=优先级，颜色=状态，横线=思维轨迹。"""

    item_clicked = pyqtSignal(object)

    L, R, T, B = 34, 14, 16, 26      # 四周留白

    def __init__(self, palette=None, parent=None):
        super().__init__(palette, parent)
        self.items: list[Item] = []
        self.setMinimumHeight(220)
        self._hot: list[tuple[QPointF, float, Item]] = []
        self._lo = self._hi = _dt.date.today()
        self.empty_text = "还没有带「精力/状态」的想法"

    def set_items(self, items: list[Item]) -> None:
        self.items = [i for i in (items or []) if i.created]
        if self.items:
            dates = []
            for it in self.items:
                dates.append(_d(it.created))
                dates += [_d(n.t) for n in it.thinking_notes if n.t]
            dates = [d for d in dates if d]
            if dates:
                self._lo, self._hi = min(dates), max(dates)
                if self._lo == self._hi:                    # 单日数据也要有横向跨度
                    self._lo -= _dt.timedelta(days=1)
                    self._hi += _dt.timedelta(days=1)
        self.update()

    # ---- 坐标换算 ----
    def _x(self, day: _dt.date) -> float:
        span = max(1, (self._hi - self._lo).days)
        w = self.width() - self.L - self.R
        return self.L + w * ((day - self._lo).days / span)

    def _y(self, energy: int | None) -> float:
        h = self.height() - self.T - self.B
        e = 0 if energy is None else max(0, min(10, energy))
        return self.T + h * (1 - e / 10)

    def paintEvent(self, e):
        p = self._painter()
        self._hot.clear()
        if not self.items:
            self._draw_empty(p)
            p.end()
            return

        # 横向网格 + Y 轴刻度（精力 0–10）
        for v in (0, 2, 4, 6, 8, 10):
            y = self._y(v)
            p.setPen(self._grid_pen())
            p.drawLine(int(self.L), int(y), int(self.width() - self.R), int(y))
            self._label(p, QRectF(0, y - 7, self.L - 6, 14), str(v),
                        self.p.faint, 9, Qt.AlignRight | Qt.AlignVCenter)

        # X 轴日期刻度
        span = max(1, (self._hi - self._lo).days)
        ticks = min(6, span + 1)
        for i in range(ticks):
            day = self._lo + _dt.timedelta(days=round(span * i / max(1, ticks - 1)))
            # 首尾标签往内收，避免被裁掉
            x = min(max(self._x(day), self.L + 20), self.width() - self.R - 20)
            self._label(p, QRectF(x - 32, self.height() - self.B + 4, 64, 14),
                        day.strftime("%m-%d"), self.p.faint, 9, Qt.AlignCenter)

        # 先画生命线（在点下面）
        for it in self.items:
            start = _d(it.created)
            if not start:
                continue
            note_days = sorted({d for n in it.thinking_notes if (d := _d(n.t))})
            # 生命线覆盖「创建日 ∪ 所有注释日」的真实跨度：
            # 注释日期早于创建日（补记）时也要画得出来。
            span_days = note_days + [start]
            begin, end = min(span_days), max(span_days)
            if end <= begin:
                continue
            y = self._y(it.energy)
            color = QColor(it.status.color)
            color.setAlpha(90)
            p.setPen(QPen(color, 2, Qt.SolidLine, Qt.RoundCap))
            p.drawLine(int(self._x(begin)), int(y), int(self._x(end)), int(y))
            # 思路注释刻度
            tick = QColor(it.status.color)
            tick.setAlpha(190)
            p.setPen(QPen(tick, 2))
            for d in note_days:
                if d == start:
                    continue
                x = self._x(d)
                p.drawLine(int(x), int(y - 4), int(x), int(y + 4))

        # 再画主点
        for it in self.items:
            start = _d(it.created)
            if not start:
                continue
            x, y = self._x(start), self._y(it.energy)
            r = it.priority.weight / 2.6
            col = QColor(it.status.color)
            p.setPen(QPen(QColor(self.p.surface), 2))
            col.setAlpha(215)
            p.setBrush(col)
            p.drawEllipse(QPointF(x, y), r, r)
            self._hot.append((QPointF(x, y), max(r, 7.0), it))

        p.end()

    # ---- 交互 ----
    def _hit(self, pos) -> Item | None:
        best, best_d = None, 1e9
        for pt, r, it in self._hot:
            d = (pt.x() - pos.x()) ** 2 + (pt.y() - pos.y()) ** 2
            if d <= (r + 4) ** 2 and d < best_d:
                best, best_d = it, d
        return best

    def mouseMoveEvent(self, e):
        it = self._hit(e.pos())
        if it:
            self.setCursor(Qt.PointingHandCursor)
            notes = len(it.thinking_notes)
            last = it.thinking_notes[-1].note if notes else ""
            tip = (f"<b>{_esc(it.title)}</b><br>"
                   f"{it.created} · {it.status.label} · {it.priority.label}优先级<br>"
                   f"精力 {it.energy if it.energy is not None else '—'} · "
                   f"进度 {it.progress if it.progress is not None else '—'}%<br>"
                   f"思路注释 {notes} 条")
            if last:
                tip += f"<br><i>最近：{_esc(last[:40])}</i>"
            QToolTip.showText(e.globalPos(), tip, self)
        else:
            self.unsetCursor()
            QToolTip.hideText()

    def mousePressEvent(self, e):
        it = self._hit(e.pos())
        if it:
            self.item_clicked.emit(it)


def _d(s: str) -> _dt.date | None:
    try:
        return _dt.date.fromisoformat(str(s)[:10])
    except (ValueError, TypeError):
        return None


def _esc(s: str) -> str:
    return (str(s).replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;"))
