"""运行日志与复盘：让每次 agent 操作可追溯，并把日志聚合成周复盘。"""
from __future__ import annotations

from PyQt5.QtCore import Qt
from PyQt5.QtWidgets import (
    QComboBox, QDoubleSpinBox, QGridLayout, QHBoxLayout, QHeaderView,
    QLineEdit, QPushButton, QTableWidget, QTableWidgetItem,
)

from lifeos.models import RunLog
from lifeos.services import review as review_svc
from lifeos.services import runlog as runlog_svc
from lifeos.gui.charts import BarChart, HBarChart
from lifeos.gui.pages.base import Page
from lifeos.gui.widgets.common import Card, StatTile

RANGES = [("最近 7 天", 7), ("最近 14 天", 14), ("最近 30 天", 30), ("全部", 3650)]
STATUS_COLOR = RunLog.STATUS_COLOR


class LogsPage(Page):
    title = "运行日志与复盘"
    subtitle = "每次 agent 操作留痕 → 聚合成可沉淀的复盘"
    icon = "◷"

    def __init__(self, ctx, parent=None):
        super().__init__(ctx, parent)
        self.build()

    def build(self) -> None:
        self.range_combo = QComboBox()
        for label, days in RANGES:
            self.range_combo.addItem(label, days)
        self.range_combo.currentIndexChanged.connect(self.refresh)
        self.header.add_action(self.range_combo)

        report_btn = QPushButton("生成周复盘报告")
        report_btn.setObjectName("Primary")
        report_btn.setCursor(Qt.PointingHandCursor)
        report_btn.clicked.connect(self._write_report)
        self.header.add_action(report_btn)

        # ---- KPI ----
        grid = QGridLayout()
        grid.setSpacing(12)
        self.tiles = {}
        for i, (key, label, color) in enumerate([
            ("total", "运行次数", None),
            ("rate", "成功率", self.p.ok),
            ("failed", "失败/部分", self.p.danger),
            ("duration", "总耗时", self.p.accent),
        ]):
            t = StatTile(label, "—", color=color)
            self.tiles[key] = t
            grid.addWidget(t, 0, i)
            grid.setColumnStretch(i, 1)
        self.content.addLayout(grid)

        # ---- 图表 ----
        row = QHBoxLayout()
        row.setSpacing(12)
        st = Card("状态分布")
        self.status_chart = BarChart(self.p)
        self.status_chart.setMinimumHeight(150)
        st.body.addWidget(self.status_chart)
        row.addWidget(st, 2)

        tools = Card("工具使用 TopN")
        self.tools_chart = HBarChart(self.p)
        self.tools_chart.setMinimumHeight(150)
        tools.body.addWidget(self.tools_chart)
        row.addWidget(tools, 3)

        errs = Card("错误 TopN", "高频错误 = 该沉淀成 skill 的信号")
        self.errors_chart = HBarChart(self.p)
        self.errors_chart.setMinimumHeight(150)
        errs.body.addWidget(self.errors_chart)
        row.addWidget(errs, 3)
        self.content.addLayout(row)

        # ---- 手动记一条 ----
        add = Card("记一次操作", "跑完一次 agent 任务后，把过程与产出记下来")
        r1 = QHBoxLayout()
        r1.setSpacing(8)
        self.objective = QLineEdit()
        self.objective.setPlaceholderText("这次做了什么（必填）")
        self.status_combo = QComboBox()
        for s in runlog_svc.STATUSES:
            self.status_combo.addItem({"success": "成功", "partial": "部分", "failed": "失败"}[s], s)
        self.duration = QDoubleSpinBox()
        self.duration.setRange(0, 100000)
        self.duration.setSuffix(" 秒")
        self.duration.setFixedWidth(110)
        r1.addWidget(self.objective, 1)
        r1.addWidget(self.status_combo)
        r1.addWidget(self.duration)
        add.body.addLayout(r1)

        r2 = QHBoxLayout()
        r2.setSpacing(8)
        self.tools_edit = QLineEdit()
        self.tools_edit.setPlaceholderText("用到的工具，逗号分隔：bash, pandoc")
        self.outputs_edit = QLineEdit()
        self.outputs_edit.setPlaceholderText("产出路径，逗号分隔")
        self.errors_edit = QLineEdit()
        self.errors_edit.setPlaceholderText("错误，逗号分隔")
        for w in (self.tools_edit, self.outputs_edit, self.errors_edit):
            r2.addWidget(w, 1)
        add.body.addLayout(r2)

        r3 = QHBoxLayout()
        r3.setSpacing(8)
        self.notes_edit = QLineEdit()
        self.notes_edit.setPlaceholderText("复盘备注：下次怎么做更好")
        self.model_edit = QLineEdit()
        self.model_edit.setPlaceholderText("模型")
        self.model_edit.setFixedWidth(140)
        save = QPushButton("记录")
        save.setObjectName("Primary")
        save.setCursor(Qt.PointingHandCursor)
        save.clicked.connect(self._add_log)
        r3.addWidget(self.notes_edit, 1)
        r3.addWidget(self.model_edit)
        r3.addWidget(save)
        add.body.addLayout(r3)
        self.content.addWidget(add)

        # ---- 日志表 ----
        table_card = Card("运行日志", "数据源 logs/run-log.jsonl")
        self.table = QTableWidget(0, 6)
        self.table.setHorizontalHeaderLabels(["时间", "状态", "目标", "工具", "耗时", "产出/错误"])
        self.table.verticalHeader().setVisible(False)
        self.table.setEditTriggers(QTableWidget.NoEditTriggers)
        self.table.setSelectionBehavior(QTableWidget.SelectRows)
        h = self.table.horizontalHeader()
        h.setSectionResizeMode(2, QHeaderView.Stretch)
        h.setSectionResizeMode(5, QHeaderView.Stretch)
        self.table.setMinimumHeight(240)
        table_card.body.addWidget(self.table)
        self.content.addWidget(table_card)
        self.content.addStretch(1)

    # ------------------------------------------------------------------
    def _since(self) -> str:
        return review_svc.default_since(self.range_combo.currentData())

    def refresh(self) -> None:
        since = self._since()
        st = review_svc.aggregate(since, self.config)
        self.tiles["total"].set_value(str(st.total), f"{since} 起")
        self.tiles["rate"].set_value(f"{st.rate:.0f}%", f"成功 {st.success}")
        self.tiles["failed"].set_value(str(st.failed), "失败 + 部分成功")
        self.tiles["duration"].set_value(
            f"{st.duration:.0f}s", f"平均 {(st.duration / st.total if st.total else 0):.1f}s/次"
        )
        self.status_chart.set_data([
            (label, st.by_status.get(key, 0), STATUS_COLOR[key])
            for key, label in (("success", "成功"), ("partial", "部分"), ("failed", "失败"))
        ])
        self.tools_chart.set_data(st.tools, self.p.accent)
        self.errors_chart.set_data(st.errors, self.p.danger)

        records = runlog_svc.load(since=since, config=self.config)
        self.table.setRowCount(len(records))
        for r, rec in enumerate(records):
            extra = ", ".join(rec.outputs) or ("; ".join(rec.errors))
            cells = [
                rec.timestamp.replace("T", " ").rstrip("Z"),
                f"{rec.icon} {rec.status}",
                rec.objective,
                ", ".join(rec.tools_used),
                f"{rec.duration_seconds:g}s" if rec.duration_seconds else "",
                extra,
            ]
            for c, text in enumerate(cells):
                cell = QTableWidgetItem(text)
                if c == 1:
                    from PyQt5.QtGui import QColor
                    cell.setForeground(QColor(rec.color))
                if rec.notes and c == 2:
                    cell.setToolTip(f"复盘：{rec.notes}")
                self.table.setItem(r, c, cell)
        self.table.resizeColumnsToContents()
        h = self.table.horizontalHeader()
        h.setSectionResizeMode(2, QHeaderView.Stretch)
        h.setSectionResizeMode(5, QHeaderView.Stretch)

    def _add_log(self) -> None:
        objective = self.objective.text().strip()
        if not objective:
            self.notify("「这次做了什么」是必填的")
            return
        def split(s: str) -> list[str]:
            return [x.strip() for x in s.split(",") if x.strip()]
        try:
            rec = runlog_svc.append(RunLog(
                objective=objective,
                status=self.status_combo.currentData(),
                tools_used=split(self.tools_edit.text()),
                outputs=split(self.outputs_edit.text()),
                errors=split(self.errors_edit.text()),
                duration_seconds=self.duration.value(),
                model=self.model_edit.text().strip(),
                notes=self.notes_edit.text().strip(),
            ), self.config)
        except (ValueError, OSError) as exc:
            self.notify(f"记录失败：{exc}")
            return
        for w in (self.objective, self.tools_edit, self.outputs_edit,
                  self.errors_edit, self.notes_edit):
            w.clear()
        self.duration.setValue(0)
        self.notify(f"已记录 {rec.run_id}")
        self.refresh()

    def _write_report(self) -> None:
        st = review_svc.aggregate(self._since(), self.config)
        if st.total == 0:
            self.notify("这段时间还没有日志，先记几条")
            return
        path = review_svc.write_report(st, config=self.config)
        self.notify(f"周复盘已生成 → {path}")

    def on_theme_changed(self, palette) -> None:
        for c in (self.status_chart, self.tools_chart, self.errors_chart):
            c.set_palette(palette)
