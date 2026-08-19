"""想法库：从「只能看」变成「能改」——本次重构补上的最大缺口。

原来看板是只读 HTML，要改状态、加思路注释只能手动编辑 YAML。
这里把想法的五个维度（时间/状态/优先级/标签/思路注释）全部做成可编辑控件，
保存时走 repository 的确定性序列化，写回的文件与手写笔记同风格、对 Obsidian 透明。
"""
from __future__ import annotations

import subprocess

from PyQt5.QtCore import Qt, pyqtSignal
from PyQt5.QtGui import QKeySequence
from PyQt5.QtWidgets import (
    QComboBox, QHBoxLayout, QLabel, QLineEdit, QListWidget, QListWidgetItem,
    QMessageBox, QPlainTextEdit, QPushButton, QShortcut, QSizePolicy, QSlider,
    QSplitter, QVBoxLayout, QWidget,
)

from lifeos.models import Item, ItemType, Priority, Status, ThinkingNote, today
from lifeos.gui.pages.base import Page
from lifeos.gui.widgets.common import (
    Badge, Card, EmptyState, ProgressRing, TagChip,
)


class IdeasPage(Page):
    title = "想法库"
    subtitle = "想法是一等公民：时间 · 状态 · 优先级 · 标签 · 思路注释"
    icon = "☰"
    scrollable = False

    item_changed = pyqtSignal(object)

    def __init__(self, ctx, parent=None):
        super().__init__(ctx, parent)
        self.current: Item | None = None
        self._dirty = False
        self._loading = False
        self.build()

    # ------------------------------------------------------------------
    def build(self) -> None:
        new_btn = QPushButton("＋ 新建想法")
        new_btn.setObjectName("Primary")
        new_btn.setCursor(Qt.PointingHandCursor)
        new_btn.clicked.connect(self.new_item)
        self.header.add_action(new_btn)
        for seq in ("Ctrl+N", "Meta+N"):
            QShortcut(QKeySequence(seq), self, self.new_item)
        for seq in ("Ctrl+S", "Meta+S"):
            QShortcut(QKeySequence(seq), self, self.save_current)

        split = QSplitter(Qt.Horizontal)
        split.addWidget(self._build_list())
        split.addWidget(self._build_editor())
        split.setStretchFactor(0, 0)
        split.setStretchFactor(1, 1)
        split.setSizes([340, 800])
        self.content.addWidget(split, 1)

    def _build_list(self) -> QWidget:
        box = QWidget()
        lay = QVBoxLayout(box)
        lay.setContentsMargins(0, 0, 0, 0)
        lay.setSpacing(8)

        self.search = QLineEdit()
        self.search.setPlaceholderText("搜索标题 / 标签 / 思路注释 / 正文…")
        self.search.setProperty("search", True)
        self.search.textChanged.connect(self.reload_list)
        lay.addWidget(self.search)

        filters = QHBoxLayout()
        filters.setSpacing(6)
        self.status_filter = QComboBox()
        self.status_filter.addItem("全部状态", None)
        for s in Status.ordered():
            self.status_filter.addItem(s.label, s)
        self.status_filter.currentIndexChanged.connect(self.reload_list)

        self.type_filter = QComboBox()
        self.type_filter.addItem("全部类型", None)
        for t in ItemType:
            self.type_filter.addItem(t.label, t)
        self.type_filter.currentIndexChanged.connect(self.reload_list)

        filters.addWidget(self.status_filter, 1)
        filters.addWidget(self.type_filter, 1)
        lay.addLayout(filters)

        self.list = QListWidget()
        self.list.setUniformItemSizes(False)
        self.list.setHorizontalScrollBarPolicy(Qt.ScrollBarAlwaysOff)
        self.list.setWordWrap(False)
        self.list.currentItemChanged.connect(self._on_select)
        lay.addWidget(self.list, 1)

        self.count_label = QLabel("")
        self.count_label.setStyleSheet(
            f"color: {self.p.faint}; background: transparent; font-size: 11px;"
        )
        lay.addWidget(self.count_label)
        box.setMinimumWidth(280)
        return box

    def _build_editor(self) -> QWidget:
        from PyQt5.QtWidgets import QScrollArea

        scroll = QScrollArea()
        scroll.setWidgetResizable(True)
        scroll.setHorizontalScrollBarPolicy(Qt.ScrollBarAlwaysOff)
        host = QWidget()
        lay = QVBoxLayout(host)
        lay.setContentsMargins(14, 0, 6, 6)
        lay.setSpacing(12)

        # 空态
        self.empty = EmptyState("☰", "还没有选中任何想法",
                                "从左边挑一条，或按 ⌘N 新建", "新建想法", self.p)
        self.empty.action_clicked.connect(self.new_item)
        lay.addWidget(self.empty)

        # 编辑区
        self.editor_box = QWidget()
        ed = QVBoxLayout(self.editor_box)
        ed.setContentsMargins(0, 0, 0, 0)
        ed.setSpacing(12)

        self.title_edit = QLineEdit()
        self.title_edit.setPlaceholderText("想法标题")
        self.title_edit.setStyleSheet("font-size: 17px; font-weight: 600; padding: 8px 10px;")
        self.title_edit.textChanged.connect(self._mark_dirty)
        ed.addWidget(self.title_edit)

        # --- 属性 ---
        attr = Card("属性")
        row1 = QHBoxLayout()
        row1.setSpacing(10)
        self.status_combo = QComboBox()
        for s in Status.ordered():
            self.status_combo.addItem(s.label, s)
        self.status_combo.currentIndexChanged.connect(self._mark_dirty)

        self.priority_combo = QComboBox()
        for pr in Priority.ordered():
            self.priority_combo.addItem(pr.label, pr)
        self.priority_combo.currentIndexChanged.connect(self._mark_dirty)

        self.type_combo = QComboBox()
        for t in ItemType:
            self.type_combo.addItem(t.label, t)
        self.type_combo.currentIndexChanged.connect(self._mark_dirty)

        for label, w in (("状态", self.status_combo), ("优先级", self.priority_combo),
                         ("类型", self.type_combo)):
            row1.addWidget(self._field_label(label))
            row1.addWidget(w, 1)
        row1.addStretch(1)
        attr.body.addLayout(row1)

        row2 = QHBoxLayout()
        row2.setSpacing(10)
        self.energy = QSlider(Qt.Horizontal)
        self.energy.setRange(0, 10)
        self.energy_val = QLabel("0")
        self.energy.valueChanged.connect(lambda v: (self.energy_val.setText(str(v)), self._mark_dirty()))

        self.progress = QSlider(Qt.Horizontal)
        self.progress.setRange(0, 100)
        self.progress_val = QLabel("0%")
        self.progress.valueChanged.connect(
            lambda v: (self.progress_val.setText(f"{v}%"), self._mark_dirty())
        )

        row2.addWidget(self._field_label("精力"))
        row2.addWidget(self.energy, 1)
        row2.addWidget(self.energy_val)
        row2.addSpacing(16)
        row2.addWidget(self._field_label("进度"))
        row2.addWidget(self.progress, 1)
        row2.addWidget(self.progress_val)
        attr.body.addLayout(row2)

        self.tags_edit = QLineEdit()
        self.tags_edit.setPlaceholderText("标签，用逗号分隔：life, workflow, pkms")
        self.tags_edit.textChanged.connect(self._mark_dirty)
        tag_row = QHBoxLayout()
        tag_row.setSpacing(10)
        tag_row.addWidget(self._field_label("标签"))
        tag_row.addWidget(self.tags_edit, 1)
        attr.body.addLayout(tag_row)

        self.meta_label = QLabel("")
        self.meta_label.setStyleSheet(
            f"color: {self.p.faint}; background: transparent; font-size: 11px;"
        )
        attr.body.addWidget(self.meta_label)
        ed.addWidget(attr)

        # --- 思路注释 ---
        self.notes_card = Card("思路注释（思维轨迹）",
                               "记录「为什么想到它、想法怎么变的」——复盘时看的是过程，不只是结论")
        self.notes_box = QVBoxLayout()
        self.notes_box.setSpacing(0)
        self.notes_card.body.addLayout(self.notes_box)

        add_row = QHBoxLayout()
        add_row.setSpacing(8)
        self.note_input = QLineEdit()
        self.note_input.setPlaceholderText("补一条思路…（回车添加，自动记今天的日期）")
        self.note_input.returnPressed.connect(self._add_note)
        add_note_btn = QPushButton("添加")
        add_note_btn.clicked.connect(self._add_note)
        add_row.addWidget(self.note_input, 1)
        add_row.addWidget(add_note_btn)
        self.notes_card.body.addLayout(add_row)
        ed.addWidget(self.notes_card)

        # --- 下一步 ---
        na = Card("下一步（Next Actions）", "一行一条")
        self.next_actions = QPlainTextEdit()
        self.next_actions.setPlaceholderText("落地可视化看板\n配置 Obsidian 插件")
        self.next_actions.setFixedHeight(78)
        self.next_actions.textChanged.connect(self._mark_dirty)
        na.body.addWidget(self.next_actions)
        ed.addWidget(na)

        # --- 正文 ---
        body_card = Card("正文（Markdown）")
        self.body_edit = QPlainTextEdit()
        self.body_edit.setPlaceholderText("# 标题\n\n叙述性内容…")
        self.body_edit.setMinimumHeight(150)
        self.body_edit.textChanged.connect(self._mark_dirty)
        body_card.body.addWidget(self.body_edit)
        ed.addWidget(body_card)

        # --- 操作 ---
        actions = QHBoxLayout()
        actions.setSpacing(8)
        self.dirty_label = QLabel("")
        self.dirty_label.setStyleSheet(
            f"color: {self.p.warn}; background: transparent; font-size: 11px;"
        )
        actions.addWidget(self.dirty_label)
        actions.addStretch(1)

        reveal = QPushButton("在访达中显示")
        reveal.clicked.connect(self._reveal)
        archive_btn = QPushButton("归档")
        archive_btn.clicked.connect(self._archive)
        delete_btn = QPushButton("删除")
        delete_btn.setObjectName("Danger")
        delete_btn.clicked.connect(self._delete)
        save_btn = QPushButton("保存  ⌘S")
        save_btn.setObjectName("Primary")
        save_btn.clicked.connect(self.save_current)
        for b in (reveal, archive_btn, delete_btn, save_btn):
            b.setCursor(Qt.PointingHandCursor)
            actions.addWidget(b)
        ed.addLayout(actions)
        ed.addStretch(1)

        lay.addWidget(self.editor_box)
        self.editor_box.hide()
        scroll.setWidget(host)
        return scroll

    def _field_label(self, text: str) -> QLabel:
        lab = QLabel(text)
        lab.setStyleSheet(f"color: {self.p.muted}; background: transparent; font-size: 12px;")
        return lab

    # ------------------------------------------------------------------
    def refresh(self) -> None:
        self.repo.reload()
        self.reload_list()

    def reload_list(self) -> None:
        keep = self.current.id if self.current else None
        status = self.status_filter.currentData()
        typ = self.type_filter.currentData()
        items = self.repo.query(
            text=self.search.text().strip(),
            statuses={status} if status else None,
            types={typ} if typ else None,
        )
        items.sort(key=lambda i: i.last_activity, reverse=True)

        self.list.blockSignals(True)
        self.list.clear()
        for it in items:
            row = _ItemRow(it, self.p)
            li = QListWidgetItem(self.list)
            li.setSizeHint(row.sizeHint())
            li.setData(Qt.UserRole, it)
            self.list.addItem(li)
            self.list.setItemWidget(li, row)
        self.list.blockSignals(False)

        total = len(self.repo.items)
        self.count_label.setText(
            f"显示 {len(items)} / 共 {total} 条" + ("（有筛选）" if len(items) != total else "")
        )
        if keep:
            self.select_by_id(keep)
        elif items:
            self.list.setCurrentRow(0)
        else:
            self._show_item(None)

    def select_by_id(self, item_id: str) -> None:
        for i in range(self.list.count()):
            it = self.list.item(i).data(Qt.UserRole)
            if it and it.id == item_id:
                self.list.setCurrentRow(i)
                return

    def select_item(self, item: Item) -> None:
        """供外部（看板点击）跳转过来。"""
        self.refresh()
        if item is not None:
            self.select_by_id(item.id)

    def _on_select(self, current, _previous) -> None:
        if self._dirty and self.current is not None:
            self.save_current(silent=True)
        self._show_item(current.data(Qt.UserRole) if current else None)

    # ------------------------------------------------------------------
    def _show_item(self, item: Item | None) -> None:
        self.current = item
        if item is None:
            self.editor_box.hide()
            self.empty.show()
            return
        self.empty.hide()
        self.editor_box.show()

        self._loading = True
        self.title_edit.setText(item.title)
        self.status_combo.setCurrentIndex(Status.ordered().index(item.status))
        self.priority_combo.setCurrentIndex(Priority.ordered().index(item.priority))
        self.type_combo.setCurrentIndex(list(ItemType).index(item.type))
        self.energy.setValue(item.energy or 0)
        self.progress.setValue(item.progress or 0)
        self.tags_edit.setText(", ".join(item.tags))
        self.next_actions.setPlainText("\n".join(item.next_actions))
        self.body_edit.setPlainText(item.body.strip())
        self.meta_label.setText(
            f"id {item.id}   ·   创建 {item.created}"
            + (f"   ·   更新 {item.updated}" if item.updated else "")
            + (f"   ·   {item.path.relative_to(self.config.vault)}" if item.path else "")
        )
        self._fill_notes(item)
        self._loading = False
        self._set_dirty(False)

    def _fill_notes(self, item: Item) -> None:
        while self.notes_box.count():
            w = self.notes_box.takeAt(0).widget()
            if w:
                w.deleteLater()
        if not item.thinking_notes:
            hint = QLabel("还没有思路注释。第一条建议写「为什么会想到这个」。")
            hint.setStyleSheet(f"color: {self.p.faint}; background: transparent; font-size: 12px;")
            hint.setWordWrap(True)
            self.notes_box.addWidget(hint)
            return
        for i, n in enumerate(item.thinking_notes):
            self.notes_box.addWidget(
                _NoteRow(n, self.p, last=(i == len(item.thinking_notes) - 1),
                         on_delete=lambda note=n: self._delete_note(note))
            )

    def _add_note(self) -> None:
        text = self.note_input.text().strip()
        if not text or self.current is None:
            return
        self.current.thinking_notes.append(ThinkingNote(t=today(), note=text))
        self.note_input.clear()
        self._fill_notes(self.current)
        self._set_dirty(True)

    def _delete_note(self, note: ThinkingNote) -> None:
        if self.current is None:
            return
        self.current.thinking_notes = [n for n in self.current.thinking_notes if n is not note]
        self._fill_notes(self.current)
        self._set_dirty(True)

    # ------------------------------------------------------------------
    def _mark_dirty(self, *_) -> None:
        if not self._loading:
            self._set_dirty(True)

    def _set_dirty(self, dirty: bool) -> None:
        self._dirty = dirty
        self.dirty_label.setText("● 未保存的修改" if dirty else "")

    def _collect(self) -> None:
        it = self.current
        if it is None:
            return
        it.title = self.title_edit.text().strip() or "未命名想法"
        it.status = self.status_combo.currentData()
        it.priority = self.priority_combo.currentData()
        it.type = self.type_combo.currentData()
        it.energy = self.energy.value()
        it.progress = self.progress.value()
        it.tags = [t.strip() for t in self.tags_edit.text().split(",") if t.strip()]
        it.next_actions = [
            l.strip().lstrip("-[ ]x").strip()
            for l in self.next_actions.toPlainText().splitlines() if l.strip()
        ]
        it.body = self.body_edit.toPlainText()

    def save_current(self, silent: bool = False) -> None:
        if self.current is None:
            return
        self._collect()
        try:
            path = self.repo.save(self.current)
        except OSError as exc:
            QMessageBox.warning(self, "保存失败", str(exc))
            return
        self._set_dirty(False)
        self.item_changed.emit(self.current)
        if not silent:
            self.notify(f"已保存 → {path.name}")
        self.reload_list()

    def new_item(self) -> None:
        item = self.repo.create("未命名想法", body="# 未命名想法\n\n")
        self.refresh()
        self.select_by_id(item.id)
        self.title_edit.setFocus()
        self.title_edit.selectAll()
        self.notify("已新建想法，改个标题吧")

    def _archive(self) -> None:
        if self.current is None:
            return
        self._collect()
        path = self.repo.archive(self.current)
        self.notify(f"已归档 → {path.relative_to(self.config.vault)}")
        self.refresh()

    def _delete(self) -> None:
        if self.current is None:
            return
        ans = QMessageBox.question(
            self, "删除想法",
            f"把「{self.current.title}」移到 vault/.trash/？\n（不是永久删除，可以从回收站找回）",
            QMessageBox.Yes | QMessageBox.No, QMessageBox.No,
        )
        if ans != QMessageBox.Yes:
            return
        target = self.repo.delete(self.current)
        self.current = None
        self.notify(f"已移入回收站{f'：{target.name}' if target else ''}")
        self.refresh()

    def _reveal(self) -> None:
        if self.current and self.current.path:
            subprocess.run(["open", "-R", str(self.current.path)], check=False)

    def on_theme_changed(self, palette) -> None:
        self.reload_list()


class _ItemRow(QWidget):
    """列表行：状态点 + 标题 + 标签 + 进度环 + 最近活动。"""

    def __init__(self, item: Item, palette):
        super().__init__()
        lay = QHBoxLayout(self)
        lay.setContentsMargins(8, 7, 8, 7)
        lay.setSpacing(9)

        col = QVBoxLayout()
        col.setSpacing(3)
        top = QHBoxLayout()
        top.setSpacing(6)
        dot = QLabel("●")
        dot.setStyleSheet(f"color: {item.status.color}; background: transparent; font-size: 10px;")
        title = QLabel(item.title)
        title.setStyleSheet(f"color: {palette.text}; background: transparent; font-weight: 600;")
        title.setToolTip(item.title)
        title.setMinimumWidth(0)
        title.setTextInteractionFlags(Qt.NoTextInteraction)
        title.setSizePolicy(QSizePolicy.Ignored, QSizePolicy.Preferred)
        top.addWidget(dot)
        top.addWidget(title, 1)
        col.addLayout(top)

        meta = QHBoxLayout()
        meta.setSpacing(5)
        date = QLabel(item.last_activity)
        date.setStyleSheet(f"color: {palette.faint}; background: transparent; font-size: 11px;")
        meta.addWidget(date)
        if item.thinking_notes:
            n = QLabel(f"✎{len(item.thinking_notes)}")
            n.setToolTip(f"{len(item.thinking_notes)} 条思路注释")
            n.setStyleSheet(f"color: {palette.faint}; background: transparent; font-size: 11px;")
            meta.addWidget(n)
        for t in item.tags[:2]:
            meta.addWidget(TagChip(t, palette))
        meta.addStretch(1)
        col.addLayout(meta)
        lay.addLayout(col, 1)

        if item.priority is Priority.HIGH:
            badge = Badge("高", item.priority.color)
            badge.setFixedHeight(20)
            lay.addWidget(badge, 0, Qt.AlignVCenter)
        ring = ProgressRing(item.progress or 0, 32, palette)
        lay.addWidget(ring)
        self.setMinimumHeight(56)


class _NoteRow(QWidget):
    """一条思路注释：左侧时间轴 + 日期 + 内容 + 删除。"""

    def __init__(self, note: ThinkingNote, palette, last: bool, on_delete):
        super().__init__()
        self._palette, self._last = palette, last
        lay = QHBoxLayout(self)
        lay.setContentsMargins(16, 2, 2, 2)
        lay.setSpacing(10)

        date = QLabel(note.t)
        date.setStyleSheet(f"color: {palette.faint}; background: transparent; font-size: 11px;")
        date.setFixedWidth(72)

        text = QLabel(note.note)
        text.setWordWrap(True)
        text.setStyleSheet(f"color: {palette.text}; background: transparent; font-size: 12px;")

        rm = QPushButton("×")
        rm.setObjectName("Ghost")
        rm.setFixedWidth(24)
        rm.setToolTip("删除这条注释")
        rm.setCursor(Qt.PointingHandCursor)
        rm.clicked.connect(lambda: on_delete())

        lay.addWidget(date)
        lay.addWidget(text, 1)
        lay.addWidget(rm)
        self.setMinimumHeight(30)

    def paintEvent(self, e):
        """画左侧时间轴的竖线与节点。"""
        from PyQt5.QtGui import QColor, QPainter, QPen
        p = QPainter(self)
        p.setRenderHint(QPainter.Antialiasing)
        x = 7
        p.setPen(QPen(QColor(self._palette.border), 1))
        p.drawLine(x, 0, x, self.height() if not self._last else self.height() // 2)
        p.setPen(Qt.NoPen)
        p.setBrush(QColor(self._palette.accent))
        p.drawEllipse(x - 3, self.height() // 2 - 3, 6, 6)
        p.end()
