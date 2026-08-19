"""格式转换页：任意格式 → Markdown（缓存）→ 目标格式。

缓存是「算力经济」的核心：同一个文件二次转换直接命中，
不再重复跑 OCR / 大模型。这里把命中与否显式告诉用户。
"""
from __future__ import annotations

import subprocess
from pathlib import Path

from PyQt5.QtCore import Qt
from PyQt5.QtWidgets import (
    QComboBox, QFileDialog, QGridLayout, QHBoxLayout, QLabel, QLineEdit,
    QPushButton,
)

from lifeos.services import convert as convert_svc
from lifeos.gui.pages.base import Page
from lifeos.gui.widgets.common import Card, Console


class ConvertPage(Page):
    title = "格式转换"
    subtitle = "任意格式 → Markdown（带缓存）→ PDF / Word / HTML"
    icon = "⇄"

    def __init__(self, ctx, parent=None):
        super().__init__(ctx, parent)
        self.setAcceptDrops(True)
        self.build()

    def build(self) -> None:
        card = Card("转换", "支持把文件直接拖进这个窗口")
        row = QHBoxLayout()
        row.setSpacing(8)
        self.src = QLineEdit()
        self.src.setPlaceholderText("选择或拖入要转换的文件（PDF / Word / PPT / HTML / Markdown…）")
        pick = QPushButton("选择文件…")
        pick.setCursor(Qt.PointingHandCursor)
        pick.clicked.connect(self._pick)
        row.addWidget(self.src, 1)
        row.addWidget(pick)
        card.body.addLayout(row)

        row2 = QHBoxLayout()
        row2.setSpacing(8)
        row2.addWidget(self._label("目标格式"))
        self.target = QComboBox()
        for t, desc in [("md", "Markdown（中间态）"), ("pdf", "PDF"),
                        ("docx", "Word"), ("html", "HTML")]:
            self.target.addItem(f"{t} · {desc}", t)
        self.target.setCurrentIndex(1)
        row2.addWidget(self.target)
        row2.addSpacing(10)
        row2.addWidget(self._label("输出到"))
        self.out = QLineEdit()
        self.out.setPlaceholderText("留空 = vault/Attachments/_out/")
        row2.addWidget(self.out, 1)
        self.run_btn = QPushButton("开始转换")
        self.run_btn.setObjectName("Primary")
        self.run_btn.setCursor(Qt.PointingHandCursor)
        self.run_btn.clicked.connect(self._convert)
        row2.addWidget(self.run_btn)
        card.body.addLayout(row2)

        self.console = Console()
        self.console.setMinimumHeight(150)
        card.body.addWidget(self.console)

        act = QHBoxLayout()
        act.addStretch(1)
        self.open_btn = QPushButton("打开产物")
        self.open_btn.setEnabled(False)
        self.open_btn.clicked.connect(self._open_result)
        act.addWidget(self.open_btn)
        card.body.addLayout(act)
        self.content.addWidget(card)

        # ---- 缓存 ----
        cache_card = Card("转换缓存", "键 = sha256(输入) + 转换器版本")
        crow = QHBoxLayout()
        self.cache_label = QLabel("—")
        self.cache_label.setStyleSheet(f"color: {self.p.muted}; background: transparent;")
        clear = QPushButton("清空缓存")
        clear.setObjectName("Danger")
        clear.clicked.connect(self._clear_cache)
        crow.addWidget(self.cache_label, 1)
        crow.addWidget(clear)
        cache_card.body.addLayout(crow)
        self.content.addWidget(cache_card)

        # ---- 依赖体检 ----
        self.tools_card = Card("依赖体检", "缺哪个装哪个，不影响其它功能")
        self.tools_grid = QGridLayout()
        self.tools_grid.setSpacing(6)
        self.tools_card.body.addLayout(self.tools_grid)
        self.content.addWidget(self.tools_card)
        self.content.addStretch(1)
        self._result: Path | None = None

    def _label(self, t: str) -> QLabel:
        lab = QLabel(t)
        lab.setStyleSheet(f"color: {self.p.muted}; background: transparent; font-size: 12px;")
        return lab

    # ---------- 拖放 ----------
    def dragEnterEvent(self, e):
        if e.mimeData().hasUrls():
            e.acceptProposedAction()

    def dropEvent(self, e):
        urls = e.mimeData().urls()
        if urls:
            self.src.setText(urls[0].toLocalFile())
            self.console.log(f"已拖入：{urls[0].toLocalFile()}")

    # ---------- 动作 ----------
    def _pick(self) -> None:
        path, _ = QFileDialog.getOpenFileName(self, "选择要转换的文件", str(Path.home()))
        if path:
            self.src.setText(path)

    def _convert(self) -> None:
        src = self.src.text().strip()
        if not src:
            self.console.log("⚠️ 先选一个文件")
            return
        if self.runner.busy:
            self.console.log("⚠️ 还有转换在跑")
            return
        self.run_btn.setEnabled(False)
        self.open_btn.setEnabled(False)
        self.console.rule(Path(src).name)
        self.runner.start(
            convert_svc.convert, src,
            to=self.target.currentData(),
            out=self.out.text().strip() or None,
            config=self.config,
            on_log=self.console.log, on_done=self._done,
        )

    def _done(self, ok: bool, result, err: str) -> None:
        self.run_btn.setEnabled(True)
        if not ok or result is None:
            self.console.log(f"❌ {err.splitlines()[0] if err else '转换失败'}")
            self.notify("转换失败")
            self._refresh_cache()
            return
        if result.ok:
            self._result = result.output
            self.open_btn.setEnabled(True)
            tag = "（命中缓存，未重复计算）" if result.cached else ""
            self.console.log(f"✅ {result.message} {tag}")
            self.notify(f"转换完成 → {result.output}")
        else:
            self.console.log(f"❌ {result.message}")
            self.notify("转换失败")
        self._refresh_cache()

    def _open_result(self) -> None:
        if self._result and Path(self._result).exists():
            subprocess.run(["open", str(self._result)], check=False)

    def _clear_cache(self) -> None:
        n = convert_svc.clear_cache(self.config)
        self.console.log(f"已清空 {n} 条缓存")
        self._refresh_cache()

    def _refresh_cache(self) -> None:
        n, size = convert_svc.cache_stats(self.config)
        self.cache_label.setText(
            f"{n} 条缓存 · {size / 1024:.0f} KB · {self.config.cache}" if n
            else f"暂无缓存 · {self.config.cache}"
        )

    def refresh(self) -> None:
        self._refresh_cache()
        while self.tools_grid.count():
            w = self.tools_grid.takeAt(0).widget()
            if w:
                w.deleteLater()
        for i, (name, (ok, info)) in enumerate(convert_svc.tool_status().items()):
            r, c = divmod(i, 2)
            cell = QLabel(f"{'✅' if ok else '⬜'}  {name}  ·  {info}")
            cell.setStyleSheet(
                f"color: {self.p.muted if ok else self.p.faint}; background: transparent; font-size: 11px;"
            )
            cell.setToolTip(info)
            self.tools_grid.addWidget(cell, r, c)
