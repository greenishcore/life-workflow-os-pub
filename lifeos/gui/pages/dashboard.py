"""看板页：一屏回答「这个想法何时产生、如何演进、现在到哪一步」。"""
from __future__ import annotations

from PyQt5.QtCore import Qt, pyqtSignal
from PyQt5.QtWidgets import QGridLayout, QHBoxLayout, QLabel, QPushButton, QWidget

from lifeos import stats
from lifeos.models import Item, Status
from lifeos.gui.charts import BarChart, HBarChart, HeatmapCalendar, TimelineChart
from lifeos.gui.pages.base import Page
from lifeos.gui.widgets.common import Card, Divider, StatTile


class DashboardPage(Page):
    title = "看板"
    subtitle = "融合时间 · 精力 · 优先级 · 状态 · 思维轨迹"
    icon = "◎"

    open_item = pyqtSignal(object)
    goto_capture = pyqtSignal()

    def __init__(self, ctx, parent=None):
        super().__init__(ctx, parent)
        self.build()

    # ------------------------------------------------------------------
    def build(self) -> None:
        refresh = QPushButton("刷新")
        refresh.setCursor(Qt.PointingHandCursor)
        refresh.clicked.connect(self.refresh)
        self.header.add_action(refresh)

        # ---- KPI ----
        self.tiles: dict[str, StatTile] = {}
        grid = QGridLayout()
        grid.setSpacing(12)
        specs = [
            ("total", "想法总数", None),
            ("doing", "推进中", Status.DOING.color),
            ("done", "已完成", Status.DONE.color),
            ("notes", "思路注释", self.p.accent),
            ("streak", "连续活跃", self.p.warn),
        ]
        for i, (key, label, color) in enumerate(specs):
            tile = StatTile(label, "—", color=color)
            self.tiles[key] = tile
            grid.addWidget(tile, 0, i)
            grid.setColumnStretch(i, 1)
        self.content.addLayout(grid)

        # ---- 热力图 ----
        heat_card = Card("活跃热力图", "每格 = 当天新建想法 + 写下的思路注释")
        self.heatmap = HeatmapCalendar(self.p)
        self.heatmap.setMinimumHeight(168)
        self.heatmap.day_clicked.connect(self._on_day)
        heat_card.body.addWidget(self.heatmap)
        self.content.addWidget(heat_card)

        # ---- 融合时间轴 ----
        tl_card = Card("融合时间轴", "X=时间 · Y=精力 · 点径=优先级 · 颜色=状态 · 横线=思维轨迹")
        self.timeline = TimelineChart(self.p)
        self.timeline.setMinimumHeight(250)
        self.timeline.item_clicked.connect(self.open_item.emit)
        tl_card.body.addWidget(self.timeline)
        tl_card.body.addWidget(self._legend())
        self.content.addWidget(tl_card)

        # ---- 状态分布 + 标签 ----
        row = QHBoxLayout()
        row.setSpacing(12)
        st_card = Card("状态分布", "seed → sprout → doing → done → archived")
        self.status_chart = BarChart(self.p)
        self.status_chart.setMinimumHeight(170)
        st_card.body.addWidget(self.status_chart)
        row.addWidget(st_card, 3)

        tag_card = Card("标签 TopN")
        self.tag_chart = HBarChart(self.p)
        self.tag_chart.setMinimumHeight(170)
        tag_card.body.addWidget(self.tag_chart)
        row.addWidget(tag_card, 2)
        self.content.addLayout(row)

        # ---- 思维轨迹 ----
        self.traj_card = Card("最近的思维轨迹", "点击可跳到对应想法")
        self.traj_box = self.traj_card.body
        self.content.addWidget(self.traj_card)
        self.content.addStretch(1)

    def _legend(self) -> QWidget:
        box = QWidget()
        box.setStyleSheet("background: transparent;")
        lay = QHBoxLayout(box)
        lay.setContentsMargins(0, 0, 0, 0)
        lay.setSpacing(14)
        for s in Status.ordered():
            dot = QLabel("●")
            dot.setStyleSheet(f"color: {s.color}; background: transparent; font-size: 11px;")
            name = QLabel(s.label)
            name.setStyleSheet(f"color: {self.p.muted}; background: transparent; font-size: 11px;")
            lay.addWidget(dot)
            lay.addWidget(name)
        lay.addStretch(1)
        return box

    # ------------------------------------------------------------------
    def refresh(self) -> None:
        items = self.repo.reload()
        s = stats.summarize(items)

        self.tiles["total"].set_value(str(s.total), f"跨度 {s.span_days} 天")
        self.tiles["doing"].set_value(str(s.active), f"平均进度 {s.avg_progress:.0f}%")
        self.tiles["done"].set_value(str(s.done),
                                     f"完成率 {(s.done / s.total * 100 if s.total else 0):.0f}%")
        self.tiles["notes"].set_value(str(s.total_notes),
                                      f"人均 {(s.total_notes / s.total if s.total else 0):.1f} 条/想法")
        self.tiles["streak"].set_value(f"{s.streak}", "天" if s.streak else "今天还没记录")

        self.heatmap.set_data(stats.activity_heat(items))
        self.timeline.set_items(items)
        self.status_chart.set_data(
            [(st.label, c, st.color) for st, c in stats.status_counts(items).items()]
        )
        self.tag_chart.set_data(stats.tag_counts(items, 8), self.p.accent)
        self._fill_trajectory(items)
        self.header.set_subtitle(
            f"{self.subtitle} · 共 {s.total} 条记录 · vault: {self.config.vault}"
        )

    def _fill_trajectory(self, items: list[Item]) -> None:
        while self.traj_box.count():
            w = self.traj_box.takeAt(0).widget()
            if w:
                w.deleteLater()

        rows = stats.trajectory(items)[:8]
        if not rows:
            empty = QLabel("还没有思路注释。打开一个想法，把「为什么想到它、想法怎么变的」记下来。")
            empty.setStyleSheet(f"color: {self.p.faint}; background: transparent;")
            empty.setWordWrap(True)
            self.traj_box.addWidget(empty)
            return

        for i, (date, note, item) in enumerate(rows):
            if i:
                self.traj_box.addWidget(Divider())
            self.traj_box.addWidget(_TrajRow(date, note, item, self.p, self.open_item.emit))

    def on_theme_changed(self, palette) -> None:
        for chart in (self.heatmap, self.timeline, self.status_chart, self.tag_chart):
            chart.set_palette(palette)
        self.refresh()

    def _on_day(self, day: str) -> None:
        self.notify(f"{day}：{stats.activity_heat(self.repo.items).get(day, 0)} 次活动")


class _TrajRow(QWidget):
    """一条思维轨迹：日期 · 状态点 · 所属想法 · 注释内容。"""

    def __init__(self, date: str, note: str, item: Item, palette, on_click):
        super().__init__()
        self._item, self._on_click = item, on_click
        self.setCursor(Qt.PointingHandCursor)
        lay = QHBoxLayout(self)
        lay.setContentsMargins(2, 5, 2, 5)
        lay.setSpacing(10)

        d = QLabel(date)
        d.setStyleSheet(f"color: {palette.faint}; background: transparent; font-size: 11px;")
        d.setFixedWidth(74)

        dot = QLabel("●")
        dot.setStyleSheet(f"color: {item.status.color}; background: transparent; font-size: 10px;")

        title = QLabel(item.title)
        title.setStyleSheet(f"color: {palette.muted}; background: transparent; font-size: 12px;")
        title.setFixedWidth(120)
        title.setToolTip(item.title)

        text = QLabel(note)
        text.setWordWrap(True)
        text.setStyleSheet(f"color: {palette.text}; background: transparent; font-size: 12px;")

        for w in (d, dot, title, text):
            lay.addWidget(w)
        lay.setStretch(3, 1)

    def mousePressEvent(self, e):
        self._on_click(self._item)
