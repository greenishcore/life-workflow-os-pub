"""设置：vault 位置、主题、Apple 默认列表、LLM、依赖体检。

配置写到 ~/.config/lifeos/config.json，CLI 脚本与 GUI 共用同一份，
不会出现「命令行改的和界面看到的不是一个 vault」。
"""
from __future__ import annotations

import subprocess
from dataclasses import replace
from pathlib import Path

from PyQt5.QtCore import Qt, pyqtSignal
from PyQt5.QtWidgets import (
    QComboBox, QFileDialog, QGridLayout, QHBoxLayout, QLabel, QLineEdit,
    QPushButton,
)

from lifeos.config import CONFIG_FILE
from lifeos.services import convert as convert_svc
from lifeos.services import prompts as prompt_svc
from lifeos.gui.pages.base import Page
from lifeos.gui.widgets.common import Card


class SettingsPage(Page):
    title = "设置"
    subtitle = "配置写入 ~/.config/lifeos/config.json，GUI 与命令行脚本共用"
    icon = "⚙"

    theme_changed = pyqtSignal(str)
    vault_changed = pyqtSignal(object)

    def __init__(self, ctx, parent=None):
        super().__init__(ctx, parent)
        self.build()

    def build(self) -> None:
        # ---- vault ----
        vault_card = Card("知识库位置", "所有想法/日记/看板数据的根目录")
        row = QHBoxLayout()
        row.setSpacing(8)
        self.vault_edit = QLineEdit(str(self.config.vault))
        browse = QPushButton("浏览…")
        browse.clicked.connect(self._browse)
        open_btn = QPushButton("在访达中打开")
        open_btn.clicked.connect(
            lambda: subprocess.run(["open", self.vault_edit.text().strip()], check=False)
        )
        apply_btn = QPushButton("应用")
        apply_btn.setObjectName("Primary")
        apply_btn.clicked.connect(self._apply_vault)
        row.addWidget(self.vault_edit, 1)
        for b in (browse, open_btn, apply_btn):
            b.setCursor(Qt.PointingHandCursor)
            row.addWidget(b)
        vault_card.body.addLayout(row)

        self.paths_label = QLabel("")
        self.paths_label.setStyleSheet(
            f"color: {self.p.faint}; background: transparent; font-size: 11px;"
        )
        self.paths_label.setWordWrap(True)
        vault_card.body.addWidget(self.paths_label)
        self.content.addWidget(vault_card)

        # ---- 外观 ----
        look = Card("外观")
        lrow = QHBoxLayout()
        lrow.setSpacing(8)
        lrow.addWidget(self._label("主题"))
        self.theme_combo = QComboBox()
        self.theme_combo.addItem("浅色", "light")
        self.theme_combo.addItem("深色", "dark")
        self.theme_combo.setCurrentIndex(0 if self.config.theme == "light" else 1)
        self.theme_combo.currentIndexChanged.connect(
            lambda: self.theme_changed.emit(self.theme_combo.currentData())
        )
        lrow.addWidget(self.theme_combo)
        lrow.addStretch(1)
        look.body.addLayout(lrow)
        self.content.addWidget(look)

        # ---- Apple ----
        apple = Card("Apple 默认值", "捕捉页导入时的默认列表 / 日历名")
        arow = QHBoxLayout()
        arow.setSpacing(8)
        self.reminder_edit = QLineEdit(self.config.default_reminder_list)
        self.calendar_edit = QLineEdit(self.config.default_calendar)
        arow.addWidget(self._label("提醒事项列表"))
        arow.addWidget(self.reminder_edit, 1)
        arow.addSpacing(12)
        arow.addWidget(self._label("日历名"))
        arow.addWidget(self.calendar_edit, 1)
        apple.body.addLayout(arow)
        self.content.addWidget(apple)

        # ---- LLM ----
        llm = Card("提示词重写用的 LLM", "OpenAI 兼容接口；API Key 走环境变量 OPENAI_API_KEY，不落盘")
        lrow2 = QHBoxLayout()
        lrow2.setSpacing(8)
        self.base_edit = QLineEdit(self.config.openai_base_url)
        self.model_edit = QLineEdit(self.config.openai_model)
        lrow2.addWidget(self._label("Base URL"))
        lrow2.addWidget(self.base_edit, 2)
        lrow2.addWidget(self._label("模型"))
        lrow2.addWidget(self.model_edit, 1)
        llm.body.addLayout(lrow2)
        self.llm_state = QLabel("")
        self.llm_state.setStyleSheet(
            f"color: {self.p.faint}; background: transparent; font-size: 11px;"
        )
        llm.body.addWidget(self.llm_state)
        self.content.addWidget(llm)

        # ---- 依赖 ----
        self.tools_card = Card("依赖体检", "只影响对应功能，缺了不妨碍其它模块")
        self.tools_grid = QGridLayout()
        self.tools_grid.setSpacing(6)
        self.tools_card.body.addLayout(self.tools_grid)
        self.content.addWidget(self.tools_card)

        # ---- 保存 ----
        save_row = QHBoxLayout()
        self.config_path_label = QLabel(f"配置文件：{CONFIG_FILE}")
        self.config_path_label.setStyleSheet(
            f"color: {self.p.faint}; background: transparent; font-size: 11px;"
        )
        save_row.addWidget(self.config_path_label, 1)
        save_btn = QPushButton("保存设置")
        save_btn.setObjectName("Primary")
        save_btn.setCursor(Qt.PointingHandCursor)
        save_btn.clicked.connect(self._save)
        save_row.addWidget(save_btn)
        self.content.addLayout(save_row)
        self.content.addStretch(1)

    def _label(self, t: str) -> QLabel:
        lab = QLabel(t)
        lab.setStyleSheet(f"color: {self.p.muted}; background: transparent; font-size: 12px;")
        return lab

    # ------------------------------------------------------------------
    def _browse(self) -> None:
        path = QFileDialog.getExistingDirectory(self, "选择 vault 目录", self.vault_edit.text())
        if path:
            self.vault_edit.setText(path)

    def _apply_vault(self) -> None:
        path = Path(self.vault_edit.text().strip()).expanduser()
        if not path.is_dir():
            self.notify(f"目录不存在：{path}")
            return
        cfg = replace(self.config, vault_dir=str(path),
                      convert_raw_dir="", convert_md_dir="", convert_out_dir="")
        cfg.ensure_dirs()
        cfg.save()
        self.vault_changed.emit(cfg)
        self.refresh()

    def _save(self) -> None:
        cfg = self.config
        cfg.default_reminder_list = self.reminder_edit.text().strip() or "提醒事项"
        cfg.default_calendar = self.calendar_edit.text().strip() or "个人"
        cfg.openai_base_url = self.base_edit.text().strip() or "https://api.openai.com/v1"
        cfg.openai_model = self.model_edit.text().strip() or "gpt-4o-mini"
        cfg.theme = self.theme_combo.currentData()
        try:
            path = cfg.save()
        except OSError as exc:
            self.notify(f"保存失败：{exc}")
            return
        self.notify(f"设置已保存 → {path}")

    def refresh(self) -> None:
        self.vault_edit.setText(str(self.config.vault))
        self.paths_label.setText(
            f"日志 {self.config.logs}\n提示词 {self.config.prompts}\n"
            f"转换缓存 {self.config.cache}\n脚本 {self.config.scripts}"
        )
        self.llm_state.setText(
            "✅ 已检测到 OPENAI_API_KEY，可使用 LLM 重写"
            if prompt_svc.llm_available()
            else "⬜ 未设置 OPENAI_API_KEY —— 提示词只能生成脚手架。"
                 "可在终端 export OPENAI_API_KEY=... 后重启本程序"
        )
        while self.tools_grid.count():
            w = self.tools_grid.takeAt(0).widget()
            if w:
                w.deleteLater()
        for i, (name, (ok, info)) in enumerate(convert_svc.tool_status().items()):
            r, c = divmod(i, 2)
            lab = QLabel(f"{'✅' if ok else '⬜'}  {name}  ·  {info}")
            lab.setStyleSheet(
                f"color: {self.p.muted if ok else self.p.faint}; background: transparent; font-size: 11px;"
            )
            self.tools_grid.addWidget(lab, r, c)
