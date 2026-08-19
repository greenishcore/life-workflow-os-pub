"""提示词工作台：交互前先把口语需求重写成结构化提示词文档，再交给 agent。"""
from __future__ import annotations

import subprocess

from PyQt5.QtCore import Qt
from PyQt5.QtWidgets import (
    QApplication, QHBoxLayout, QLabel, QListWidget, QListWidgetItem,
    QPlainTextEdit, QPushButton, QSplitter, QVBoxLayout, QWidget,
)

from lifeos.services import prompts as prompt_svc
from lifeos.gui.pages.base import Page
from lifeos.gui.widgets.common import Card
from lifeos.gui.theme import mono_font


class PromptsPage(Page):
    title = "提示词工作台"
    subtitle = "口语需求 → 五段式提示词文档 → 版本化留档"
    icon = "❯"
    scrollable = False

    def __init__(self, ctx, parent=None):
        super().__init__(ctx, parent)
        self.build()

    def build(self) -> None:
        split = QSplitter(Qt.Horizontal)

        # ---- 左：输入 + 历史 ----
        left = QWidget()
        ll = QVBoxLayout(left)
        ll.setContentsMargins(0, 0, 0, 0)
        ll.setSpacing(12)

        input_card = Card("原始需求", "把想让 agent 做的事，用大白话写出来")
        self.raw = QPlainTextEdit()
        self.raw.setPlaceholderText("例：帮我做一个把 PDF 转 Markdown 的小工具，要能缓存，别重复转…")
        self.raw.setMinimumHeight(110)
        input_card.body.addWidget(self.raw)

        row = QHBoxLayout()
        row.setSpacing(8)
        self.llm_hint = QLabel("")
        self.llm_hint.setStyleSheet(
            f"color: {self.p.faint}; background: transparent; font-size: 11px;"
        )
        row.addWidget(self.llm_hint, 1)
        self.scaffold_btn = QPushButton("生成脚手架")
        self.scaffold_btn.setCursor(Qt.PointingHandCursor)
        self.scaffold_btn.clicked.connect(lambda: self._generate(False))
        self.llm_btn = QPushButton("用 LLM 重写")
        self.llm_btn.setObjectName("Primary")
        self.llm_btn.setCursor(Qt.PointingHandCursor)
        self.llm_btn.clicked.connect(lambda: self._generate(True))
        row.addWidget(self.scaffold_btn)
        row.addWidget(self.llm_btn)
        input_card.body.addLayout(row)
        ll.addWidget(input_card)

        hist_card = Card("已重写的提示词", "都在 prompts/01_rewritten/，随仓库版本化")
        self.history = QListWidget()
        self.history.currentItemChanged.connect(self._open_history)
        hist_card.body.addWidget(self.history)
        ll.addWidget(hist_card, 1)
        split.addWidget(left)

        # ---- 右：结果 ----
        right = QWidget()
        rl = QVBoxLayout(right)
        rl.setContentsMargins(12, 0, 0, 0)
        rl.setSpacing(10)
        result_card = Card("提示词文档")
        self.result = QPlainTextEdit()
        self.result.setFont(mono_font(12))
        self.result.setPlaceholderText(
            "生成的提示词会显示在这里，可直接编辑后保存。\n\n"
            "五段式：角色 / 背景 / 目标 / 约束 / 输出格式 / 验收标准"
        )
        result_card.body.addWidget(self.result)

        act = QHBoxLayout()
        act.setSpacing(8)
        self.path_label = QLabel("")
        self.path_label.setStyleSheet(
            f"color: {self.p.faint}; background: transparent; font-size: 11px;"
        )
        act.addWidget(self.path_label, 1)
        copy_btn = QPushButton("复制")
        copy_btn.clicked.connect(self._copy)
        reveal_btn = QPushButton("在访达中显示")
        reveal_btn.clicked.connect(self._reveal)
        save_btn = QPushButton("保存修改")
        save_btn.setObjectName("Primary")
        save_btn.clicked.connect(self._save)
        for b in (copy_btn, reveal_btn, save_btn):
            b.setCursor(Qt.PointingHandCursor)
            act.addWidget(b)
        result_card.body.addLayout(act)
        rl.addWidget(result_card, 1)
        split.addWidget(right)

        split.setSizes([420, 720])
        self.content.addWidget(split, 1)
        self._current_path = None

    # ------------------------------------------------------------------
    def _generate(self, use_llm: bool) -> None:
        raw = self.raw.toPlainText().strip()
        if not raw:
            self.notify("先写下你的需求")
            return
        if use_llm and not prompt_svc.llm_available():
            self.notify("未设置 OPENAI_API_KEY，改用脚手架模式")
            use_llm = False
        self.scaffold_btn.setEnabled(False)
        self.llm_btn.setEnabled(False)
        self.result.setPlainText("生成中…" if use_llm else "")
        self.runner.start(
            prompt_svc.rewrite, raw, use_llm=use_llm, config=self.config,
            pass_log=False, on_done=self._done,
        )

    def _done(self, ok: bool, doc, err: str) -> None:
        self.scaffold_btn.setEnabled(True)
        self.llm_btn.setEnabled(True)
        if not ok or doc is None:
            self.result.setPlainText(f"生成失败：\n{err}")
            self.notify("生成失败")
            return
        self.result.setPlainText(doc.content)
        self._current_path = doc.out_path
        self.path_label.setText(str(doc.out_path))
        self.notify(f"[{doc.mode}] 已生成 → {doc.out_path.name}")
        self.refresh()

    def _open_history(self, current, _prev) -> None:
        if current is None:
            return
        path = current.data(Qt.UserRole)
        try:
            self.result.setPlainText(path.read_text(encoding="utf-8"))
            self._current_path = path
            self.path_label.setText(str(path))
        except OSError as exc:
            self.notify(f"读取失败：{exc}")

    def _save(self) -> None:
        if self._current_path is None:
            self.notify("还没有可保存的提示词")
            return
        self._current_path.write_text(self.result.toPlainText(), encoding="utf-8")
        self.notify(f"已保存 → {self._current_path.name}")

    def _copy(self) -> None:
        QApplication.clipboard().setText(self.result.toPlainText())
        self.notify("已复制到剪贴板")

    def _reveal(self) -> None:
        if self._current_path:
            subprocess.run(["open", "-R", str(self._current_path)], check=False)

    def refresh(self) -> None:
        self.llm_hint.setText(
            f"LLM：{self.config.openai_model}" if prompt_svc.llm_available()
            else "未设置 OPENAI_API_KEY，只能生成脚手架"
        )
        self.llm_btn.setEnabled(prompt_svc.llm_available())
        self.history.blockSignals(True)
        self.history.clear()
        for path in prompt_svc.list_prompts(self.config):
            li = QListWidgetItem(path.stem)
            li.setData(Qt.UserRole, path)
            self.history.addItem(li)
        self.history.blockSignals(False)
