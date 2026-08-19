"""版本归档：把阶段性成果 commit / push / 打 tag / 发 release。"""
from __future__ import annotations

from PyQt5.QtCore import Qt
from PyQt5.QtWidgets import (
    QHBoxLayout, QLabel, QLineEdit, QListWidget, QPushButton,
    
)

from lifeos.services import archive as archive_svc
from lifeos.gui.pages.base import Page
from lifeos.gui.widgets.common import Card, Console


class ArchivePage(Page):
    title = "版本归档"
    subtitle = "阶段成果 commit / push，里程碑 tag + release"
    icon = "⎘"

    def __init__(self, ctx, parent=None):
        super().__init__(ctx, parent)
        self.build()

    def build(self) -> None:
        # ---- 状态 ----
        self.status_card = Card("仓库状态")
        self.status_label = QLabel("检查中…")
        self.status_label.setStyleSheet(f"color: {self.p.muted}; background: transparent;")
        self.status_label.setWordWrap(True)
        self.status_card.body.addWidget(self.status_label)

        self.changes = QListWidget()
        self.changes.setMaximumHeight(140)
        self.status_card.body.addWidget(self.changes)
        self.content.addWidget(self.status_card)

        # ---- 提交 ----
        commit_card = Card("提交并推送", "留空则用「auto: 日期 工作流同步」")
        row = QHBoxLayout()
        row.setSpacing(8)
        self.message = QLineEdit()
        self.message.setPlaceholderText("commit 说明")
        self.sync_btn = QPushButton("提交并推送")
        self.sync_btn.setObjectName("Primary")
        self.sync_btn.setCursor(Qt.PointingHandCursor)
        self.sync_btn.clicked.connect(self._sync)
        self.commit_only = QPushButton("只提交")
        self.commit_only.clicked.connect(lambda: self._sync(push=False))
        row.addWidget(self.message, 1)
        row.addWidget(self.commit_only)
        row.addWidget(self.sync_btn)
        commit_card.body.addLayout(row)

        self.console = Console()
        self.console.setFixedHeight(130)
        commit_card.body.addWidget(self.console)
        self.content.addWidget(commit_card)

        # ---- 里程碑 ----
        rel = Card("里程碑发布", "语义化版本 vX.Y.Z，需要 gh CLI 已登录")
        rrow = QHBoxLayout()
        rrow.setSpacing(8)
        self.version = QLineEdit()
        self.version.setPlaceholderText("v0.2.0")
        self.version.setFixedWidth(120)
        self.notes = QLineEdit()
        self.notes.setPlaceholderText("本阶段成果 + 下阶段计划")
        self.release_btn = QPushButton("打 tag 并发布")
        self.release_btn.setCursor(Qt.PointingHandCursor)
        self.release_btn.clicked.connect(self._release)
        rrow.addWidget(self.version)
        rrow.addWidget(self.notes, 1)
        rrow.addWidget(self.release_btn)
        rel.body.addLayout(rrow)
        self.tags_label = QLabel("")
        self.tags_label.setStyleSheet(
            f"color: {self.p.faint}; background: transparent; font-size: 11px;"
        )
        rel.body.addWidget(self.tags_label)
        self.content.addWidget(rel)

        # ---- 历史 ----
        hist = Card("提交历史")
        self.history = QListWidget()
        self.history.setMinimumHeight(180)
        hist.body.addWidget(self.history)
        self.content.addWidget(hist)
        self.content.addStretch(1)

    # ------------------------------------------------------------------
    def refresh(self) -> None:
        st = archive_svc.status(self.config)
        if not st.is_repo:
            self.status_label.setText("当前目录不是 git 仓库，归档功能不可用。")
            self.changes.clear()
            self.history.clear()
            for b in (self.sync_btn, self.commit_only, self.release_btn):
                b.setEnabled(False)
            return
        for b in (self.sync_btn, self.commit_only, self.release_btn):
            b.setEnabled(True)

        bits = [f"分支 <b>{st.branch}</b>"]
        if st.remote:
            bits.append(f"远端 {st.remote}")
        if st.ahead or st.behind:
            bits.append(f"领先 {st.ahead} / 落后 {st.behind}")
        bits.append(f"{len(st.changed)} 处改动" if st.dirty else "工作区干净")
        if st.last_commit:
            bits.append(f"最近：{st.last_commit}")
        self.status_label.setText("　·　".join(bits))

        self.changes.clear()
        for line in st.changed[:200]:
            self.changes.addItem(line)
        if not st.changed:
            self.changes.addItem("（没有未提交的改动）")

        self.history.clear()
        for h, when, subject in archive_svc.log_history(30, self.config):
            self.history.addItem(f"{h}   {when:<16}  {subject}")

        tags = archive_svc.tags(self.config)
        self.tags_label.setText(("已有里程碑：" + "、".join(tags[:8])) if tags else "还没有里程碑")

    def _sync(self, push: bool = True) -> None:
        self.console.rule("同步")
        self.sync_btn.setEnabled(False)
        self.commit_only.setEnabled(False)
        self.runner.start(
            archive_svc.sync, self.message.text().strip(), push,
            config=self.config, on_log=self.console.log, on_done=self._sync_done,
        )

    def _sync_done(self, ok: bool, result, err: str) -> None:
        self.sync_btn.setEnabled(True)
        self.commit_only.setEnabled(True)
        if not ok or result is None:
            self.console.log(f"❌ {err.splitlines()[0] if err else '同步失败'}")
            return
        success, msg = result
        self.console.log(("✅ " if success else "❌ ") + msg)
        self.notify(msg)
        if success:
            self.message.clear()
        self.refresh()

    def _release(self) -> None:
        version = self.version.text().strip()
        if not version:
            self.notify("先填版本号，如 v0.2.0")
            return
        self.console.rule(f"发布 {version}")
        self.release_btn.setEnabled(False)
        self.runner.start(
            archive_svc.release, version, self.notes.text().strip(),
            config=self.config, on_log=self.console.log, on_done=self._release_done,
        )

    def _release_done(self, ok: bool, result, err: str) -> None:
        self.release_btn.setEnabled(True)
        if not ok or result is None:
            self.console.log(f"❌ {err.splitlines()[0] if err else '发布失败'}")
            return
        success, msg = result
        self.console.log(("✅ " if success else "❌ ") + msg)
        self.notify(msg)
        if success:
            self.version.clear()
            self.notes.clear()
        self.refresh()
