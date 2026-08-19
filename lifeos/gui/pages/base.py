"""页面基类：统一持有 app context（配置/仓库/主题），并约定 refresh() 契约。"""
from __future__ import annotations

from PyQt5.QtCore import Qt, pyqtSignal
from PyQt5.QtWidgets import QScrollArea, QVBoxLayout, QWidget

from ..theme import PAD, Palette
from ..widgets.common import PageHeader
from ..worker import TaskRunner


class Page(QWidget):
    """所有页面的底座。

    · ctx 提供 config / repo / palette / 通知
    · refresh() 在切到本页时被调用，页面自行决定要不要重新读数据
    """

    status_message = pyqtSignal(str)

    title = "页面"
    subtitle = ""
    icon = "•"
    scrollable = True      # 列表/编辑器类页面自带滚动，设 False 用满高布局

    def __init__(self, ctx, parent=None):
        super().__init__(parent)
        self.ctx = ctx
        self.runner = TaskRunner(self)

        outer = QVBoxLayout(self)
        outer.setContentsMargins(0, 0, 0, 0)
        outer.setSpacing(0)

        if self.scrollable:
            scroll = QScrollArea()
            scroll.setWidgetResizable(True)
            scroll.setHorizontalScrollBarPolicy(Qt.ScrollBarAlwaysOff)
            inner = QWidget()
            self.content = QVBoxLayout(inner)
            scroll.setWidget(inner)
            outer.addWidget(scroll)
            self.scroll = scroll
        else:
            self.scroll = None
            self.content = QVBoxLayout()
            outer.addLayout(self.content)
        self.content.setContentsMargins(PAD + 6, PAD + 4, PAD + 6, PAD + 6)
        self.content.setSpacing(14)

        self.header = PageHeader(self.title, self.subtitle)
        self.content.addWidget(self.header)

    # ---- 子类覆写 ----
    def build(self) -> None:
        """构建页面内容（在 __init__ 末尾由子类自己调用）。"""

    def refresh(self) -> None:
        """切到本页时调用。"""

    def on_theme_changed(self, palette: Palette) -> None:
        """主题切换时调用，图表等需要重绘的组件在这里更新。"""

    # ---- 便利方法 ----
    @property
    def repo(self):
        return self.ctx.repo

    @property
    def config(self):
        return self.ctx.config

    @property
    def p(self) -> Palette:
        return self.ctx.palette

    def notify(self, text: str) -> None:
        self.status_message.emit(text)
