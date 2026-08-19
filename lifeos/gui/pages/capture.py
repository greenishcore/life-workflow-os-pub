"""捕捉页：把任何一闪而过的念头，用最低摩擦落到本地 Markdown。

三条入口：
  1. 手打 —— 写完 ⌘↩ 直接进 Inbox；
  2. Apple 导入 —— 提醒事项 / 日历 / 备忘录；
  3. 提升 —— 把 Inbox 里的一行随手记，一键变成带状态机的「想法」。
第 3 条是原来 CLI 缺的一环：以前捕捉完就躺在 Inbox 里，没有通往想法库的路。
"""
from __future__ import annotations

from PyQt5.QtCore import Qt, pyqtSignal
from PyQt5.QtGui import QKeySequence
from PyQt5.QtWidgets import (
    QCheckBox, QHBoxLayout, QLabel, QPlainTextEdit, QPushButton,
    QShortcut, QSpinBox, QLineEdit, QWidget,
)

from lifeos.models import ItemType, Status
from lifeos.services import apple
from lifeos.gui.pages.base import Page
from lifeos.gui.widgets.common import Card, Console, Divider, EmptyState


class CapturePage(Page):
    title = "快速捕获"
    subtitle = "想到什么先记下来，之后再整理成想法"
    icon = "✎"

    item_created = pyqtSignal(object)

    def __init__(self, ctx, parent=None):
        super().__init__(ctx, parent)
        self.build()

    def build(self) -> None:
        # ---------- 输入 ----------
        cap = Card("随手记", "⌘↩ 直接捕获到 Inbox")
        self.editor = QPlainTextEdit()
        self.editor.setPlaceholderText(
            "突然想到的点子、待办、一句灵感…\n\n"
            "⌘↩ 捕获到 Inbox（当天一个文件，追加为待办）"
        )
        self.editor.setMinimumHeight(120)
        cap.body.addWidget(self.editor)

        btn_row = QHBoxLayout()
        btn_row.setSpacing(8)
        self.hint = QLabel("")
        self.hint.setStyleSheet(f"color: {self.p.faint}; background: transparent; font-size: 11px;")
        btn_row.addWidget(self.hint)
        btn_row.addStretch(1)

        to_idea = QPushButton("建为想法…")
        to_idea.setCursor(Qt.PointingHandCursor)
        to_idea.clicked.connect(self._create_idea)
        capture_btn = QPushButton("捕获到 Inbox")
        capture_btn.setObjectName("Primary")
        capture_btn.setCursor(Qt.PointingHandCursor)
        capture_btn.clicked.connect(self._capture)
        btn_row.addWidget(to_idea)
        btn_row.addWidget(capture_btn)
        cap.body.addLayout(btn_row)
        self.content.addWidget(cap)

        for seq in ("Ctrl+Return", "Meta+Return"):
            QShortcut(QKeySequence(seq), self.editor, self._capture)

        # ---------- Apple 导入 ----------
        apple_card = Card("从 Apple 导入", "写入当天 Daily 笔记的对应段落")
        row = QHBoxLayout()
        row.setSpacing(8)

        self.reminder_list = QLineEdit(self.config.default_reminder_list)
        self.reminder_list.setPlaceholderText("提醒事项列表名")
        self.reminder_list.setFixedWidth(140)
        self.include_done = QCheckBox("含已完成")
        rem_btn = QPushButton("导入提醒")
        rem_btn.clicked.connect(self._import_reminders)

        self.calendar_name = QLineEdit(self.config.default_calendar)
        self.calendar_name.setPlaceholderText("日历名")
        self.calendar_name.setFixedWidth(110)
        self.days = QSpinBox()
        self.days.setRange(1, 60)
        self.days.setValue(7)
        self.days.setSuffix(" 天")
        self.days.setFixedWidth(74)
        cal_btn = QPushButton("导入日程")
        cal_btn.clicked.connect(self._import_calendar)

        notes_btn = QPushButton("导入备忘录")
        notes_btn.clicked.connect(self._import_notes)

        for w in (self.reminder_list, self.include_done, rem_btn):
            row.addWidget(w)
        sep = QLabel("│")
        sep.setStyleSheet(f"color: {self.p.border}; background: transparent;")
        row.addWidget(sep)
        for w in (self.calendar_name, self.days, cal_btn):
            row.addWidget(w)
        row.addWidget(notes_btn)
        row.addStretch(1)
        apple_card.body.addLayout(row)

        tip = QLabel("首次运行会申请「自动化」权限：系统设置 → 隐私与安全性 → 自动化")
        tip.setStyleSheet(f"color: {self.p.faint}; background: transparent; font-size: 11px;")
        apple_card.body.addWidget(tip)

        self.console = Console()
        self.console.setFixedHeight(96)
        apple_card.body.addWidget(self.console)
        self.content.addWidget(apple_card)

        # ---------- 最近捕获 ----------
        self.recent_card = Card("最近捕获", "勾选 = 已处理；「→ 想法」把它提升为带状态机的想法")
        self.recent_box = self.recent_card.body
        self.content.addWidget(self.recent_card)
        self.content.addStretch(1)

    # ------------------------------------------------------------------
    def _text(self) -> str:
        return self.editor.toPlainText().strip()

    def _capture(self) -> None:
        text = self._text()
        if not text:
            self.hint.setText("先写点什么")
            return
        try:
            path = self.repo.capture(text)
        except (OSError, ValueError) as exc:
            self.hint.setText(f"捕获失败：{exc}")
            return
        self.editor.clear()
        self.hint.setText(f"已捕获 → {path.name}")
        self.notify(f"已捕获到 {path}")
        self.refresh()

    def _create_idea(self, text: str = "") -> None:
        text = (text or self._text()).strip()
        if not text:
            self.hint.setText("先写点什么")
            return
        first, _, rest = text.partition("\n")
        item = self.repo.create(
            title=first.strip()[:60] or "未命名想法",
            type=ItemType.IDEA,
            status=Status.SEED,
            body=f"# {first.strip()}\n\n{rest.strip()}\n" if rest.strip() else f"# {first.strip()}\n\n",
        )
        item.add_thinking_note(f"初始想法：{first.strip()}")
        self.repo.save(item)
        self.editor.clear()
        self.hint.setText(f"已建为想法 → {item.path.name}")
        self.notify(f"已创建想法「{item.title}」")
        self.item_created.emit(item)

    # ---------- Apple ----------
    def _run(self, fn, **kwargs) -> None:
        self.console.rule("开始")
        self.runner.start(
            fn, config=self.config, repo=self.repo, **kwargs,
            on_log=self.console.log, on_done=self._on_import_done,
        )

    def _on_import_done(self, ok: bool, result, err: str) -> None:
        if not ok:
            self.console.log(f"❌ {err.splitlines()[0] if err else '执行失败'}")
            return
        self.console.log(("✅ " if result.ok else "⚠️ ") + result.message)
        self.notify(result.message)
        self.refresh()

    def _import_reminders(self) -> None:
        self._run(apple.import_reminders,
                  list_name=self.reminder_list.text().strip(),
                  include_done=self.include_done.isChecked())

    def _import_calendar(self) -> None:
        self._run(apple.import_calendar,
                  calendar_name=self.calendar_name.text().strip(),
                  days=self.days.value())

    def _import_notes(self) -> None:
        self.console.rule("导出备忘录（较慢）")
        self.runner.start(apple.import_notes, config=self.config,
                          on_log=self.console.log, on_done=self._on_import_done)

    # ------------------------------------------------------------------
    def refresh(self) -> None:
        while self.recent_box.count():
            w = self.recent_box.takeAt(0).widget()
            if w:
                w.deleteLater()

        groups = self.repo.read_capture_log(days=7)
        if not groups:
            empty = EmptyState("✎", "Inbox 还是空的",
                               "在上面写一句话，⌘↩ 就能落到 vault/Inbox/", palette=self.p)
            self.recent_box.addWidget(empty)
            return

        for gi, (date, lines) in enumerate(groups):
            if gi:
                self.recent_box.addWidget(Divider())
            head = QLabel(date)
            head.setStyleSheet(
                f"color: {self.p.muted}; background: transparent; font-size: 11px; font-weight: 600;"
            )
            self.recent_box.addWidget(head)
            for raw in lines:
                self.recent_box.addWidget(_CaptureRow(date, raw, self.p, self))


class _CaptureRow(QWidget):
    """Inbox 里的一行：勾选完成 / 提升为想法。"""

    def __init__(self, date: str, raw: str, palette, page: CapturePage):
        super().__init__()
        self._date, self._raw, self._page = date, raw, page
        done = raw.startswith("- [x]")
        text = raw
        for prefix in ("- [x] ", "- [ ] ", "- "):
            if text.startswith(prefix):
                text = text[len(prefix):]
                break

        lay = QHBoxLayout(self)
        lay.setContentsMargins(2, 1, 2, 1)
        lay.setSpacing(8)

        self.check = QCheckBox()
        self.check.setChecked(done)
        self.check.stateChanged.connect(self._toggle)

        label = QLabel(text)
        label.setWordWrap(True)
        color = palette.faint if done else palette.text
        deco = "text-decoration: line-through;" if done else ""
        label.setStyleSheet(f"color: {color}; background: transparent; font-size: 12px; {deco}")

        promote = QPushButton("→ 想法")
        promote.setObjectName("Ghost")
        promote.setCursor(Qt.PointingHandCursor)
        promote.setToolTip("提升为带状态机与思路注释的想法")
        promote.clicked.connect(lambda: self._promote(text))

        lay.addWidget(self.check)
        lay.addWidget(label, 1)
        lay.addWidget(promote)

    def _toggle(self) -> None:
        self._page.repo.toggle_capture_line(self._date, self._raw)
        self._page.refresh()

    def _promote(self, text: str) -> None:
        # 去掉行首时间戳（形如 "21:03 内容"）
        parts = text.split(" ", 1)
        clean = parts[1] if len(parts) == 2 and ":" in parts[0] and len(parts[0]) <= 5 else text
        self._page._create_idea(clean)
        self._page.repo.toggle_capture_line(self._date, self._raw)
        self._page.refresh()
