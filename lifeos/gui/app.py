"""lifeos.gui.app — 主窗口与应用上下文

界面结构：左侧按「捕捉 → 整理 → 执行 → 复盘 → 归档」五阶段闭环组织导航，
右侧是页面栈。所有页面共享同一个 AppContext（配置 + vault 仓库 + 主题）。
"""
from __future__ import annotations

import sys
from dataclasses import dataclass

from PyQt5.QtCore import Qt, QTimer
from PyQt5.QtGui import QKeySequence
from PyQt5.QtWidgets import (
    QApplication, QButtonGroup, QFrame, QHBoxLayout, QLabel, QMainWindow,
    QPushButton, QShortcut, QStackedWidget, QStatusBar, QVBoxLayout, QWidget,
)

from ..config import Config, get_config, set_config
from ..repository import VaultRepository
from .theme import PALETTES, Palette, qss, ui_font

APP_NAME = "Life Workflow OS"
APP_VERSION = "1.0.0"


@dataclass
class AppContext:
    """页面共享的运行期上下文。"""
    config: Config
    repo: VaultRepository
    palette: Palette
    window: "MainWindow | None" = None

    def set_theme(self, name: str) -> Palette:
        self.palette = PALETTES.get(name, PALETTES["light"])
        self.config.theme = name
        return self.palette


NAV = [
    ("总览", [("dashboard", "看板", "◎")]),
    ("捕捉", [("capture", "快速捕获", "✎")]),
    ("整理", [("ideas", "想法库", "☰"), ("convert", "格式转换", "⇄")]),
    ("执行", [("prompts", "提示词工作台", "❯")]),
    ("复盘", [("logs", "运行日志与复盘", "◷")]),
    ("归档", [("archive", "版本归档", "⎘")]),
    ("", [("settings", "设置", "⚙")]),
]


class MainWindow(QMainWindow):
    def __init__(self, ctx: AppContext):
        super().__init__()
        self.ctx = ctx
        ctx.window = self
        self.pages: dict[str, object] = {}

        self.setWindowTitle(f"{APP_NAME} · 生活工作流")
        self.resize(1280, 840)
        self.setMinimumSize(1040, 680)

        root = QWidget()
        lay = QHBoxLayout(root)
        lay.setContentsMargins(0, 0, 0, 0)
        lay.setSpacing(0)
        lay.addWidget(self._build_sidebar())
        self.stack = QStackedWidget()
        lay.addWidget(self.stack, 1)
        self.setCentralWidget(root)

        self.setStatusBar(QStatusBar())
        self.status_left = QLabel("")
        self.status_right = QLabel("")
        self.statusBar().addWidget(self.status_left, 1)
        self.statusBar().addPermanentWidget(self.status_right)

        self._register_pages()
        self._apply_theme(self.ctx.config.theme)
        self._shortcuts()
        self.switch("dashboard")

    # ------------------------------------------------------------------
    def _build_sidebar(self) -> QWidget:
        bar = QFrame()
        bar.setObjectName("Sidebar")
        bar.setFixedWidth(206)
        lay = QVBoxLayout(bar)
        lay.setContentsMargins(12, 16, 12, 12)
        lay.setSpacing(2)

        brand = QLabel(APP_NAME)
        brand.setObjectName("BrandTitle")
        sub = QLabel("捕捉 → 整理 → 执行 → 复盘 → 归档")
        sub.setObjectName("BrandSub")
        sub.setWordWrap(True)
        lay.addWidget(brand)
        lay.addWidget(sub)
        lay.addSpacing(8)

        self.nav_group = QButtonGroup(self)
        self.nav_group.setExclusive(True)
        self.nav_buttons: dict[str, QPushButton] = {}

        for group_name, entries in NAV:
            if group_name:
                gl = QLabel(group_name)
                gl.setObjectName("NavGroup")
                lay.addWidget(gl)
            else:
                lay.addStretch(1)
            for key, label, icon in entries:
                btn = QPushButton(f"  {icon}   {label}")
                btn.setObjectName("NavItem")
                btn.setCheckable(True)
                btn.setCursor(Qt.PointingHandCursor)
                btn.clicked.connect(lambda _=False, k=key: self.switch(k))
                self.nav_group.addButton(btn)
                self.nav_buttons[key] = btn
                lay.addWidget(btn)

        lay.addSpacing(6)
        self.theme_btn = QPushButton("切换深色")
        self.theme_btn.setObjectName("Ghost")
        self.theme_btn.setCursor(Qt.PointingHandCursor)
        self.theme_btn.clicked.connect(self.toggle_theme)
        lay.addWidget(self.theme_btn)

        ver = QLabel(f"v{APP_VERSION}")
        ver.setObjectName("BrandSub")
        ver.setAlignment(Qt.AlignCenter)
        lay.addWidget(ver)
        return bar

    def _register_pages(self) -> None:
        from .pages.archive import ArchivePage
        from .pages.capture import CapturePage
        from .pages.convert import ConvertPage
        from .pages.dashboard import DashboardPage
        from .pages.ideas import IdeasPage
        from .pages.logs import LogsPage
        from .pages.prompts import PromptsPage
        from .pages.settings import SettingsPage

        for key, cls in [
            ("dashboard", DashboardPage), ("capture", CapturePage),
            ("ideas", IdeasPage), ("convert", ConvertPage),
            ("prompts", PromptsPage), ("logs", LogsPage),
            ("archive", ArchivePage), ("settings", SettingsPage),
        ]:
            page = cls(self.ctx)
            page.status_message.connect(self.flash)
            self.pages[key] = page
            self.stack.addWidget(page)

        # 页面之间的跳转
        self.pages["dashboard"].open_item.connect(self._open_item)
        self.pages["dashboard"].goto_capture.connect(lambda: self.switch("capture"))
        self.pages["capture"].item_created.connect(self._open_item)
        self.pages["settings"].theme_changed.connect(self._apply_theme)
        self.pages["settings"].vault_changed.connect(self._on_vault_changed)

    def _shortcuts(self) -> None:
        for i, key in enumerate(
            ["dashboard", "capture", "ideas", "convert", "prompts", "logs", "archive", "settings"], 1
        ):
            QShortcut(QKeySequence(f"Ctrl+{i}"), self, lambda k=key: self.switch(k))
            QShortcut(QKeySequence(f"Meta+{i}"), self, lambda k=key: self.switch(k))
        QShortcut(QKeySequence.Refresh, self, self.refresh_current)
        QShortcut(QKeySequence("Ctrl+R"), self, self.refresh_current)
        QShortcut(QKeySequence("Meta+R"), self, self.refresh_current)

    # ------------------------------------------------------------------
    def switch(self, key: str) -> None:
        page = self.pages.get(key)
        if page is None:
            return
        self.stack.setCurrentWidget(page)
        btn = self.nav_buttons.get(key)
        if btn and not btn.isChecked():
            btn.setChecked(True)
        page.refresh()
        self._update_status()

    def refresh_current(self) -> None:
        w = self.stack.currentWidget()
        if hasattr(w, "refresh"):
            w.refresh()
        self._update_status()
        self.flash("已刷新")

    def _open_item(self, item) -> None:
        self.switch("ideas")
        self.pages["ideas"].select_item(item)

    def _on_vault_changed(self, cfg: Config) -> None:
        self.ctx.config = set_config(cfg)
        self.ctx.repo = VaultRepository(cfg)
        for page in self.pages.values():
            page.ctx = self.ctx
        self.refresh_current()
        self.flash(f"已切换 vault：{cfg.vault}")

    def toggle_theme(self) -> None:
        self._apply_theme("dark" if self.ctx.palette.name == "light" else "light")

    def _apply_theme(self, name: str) -> None:
        palette = self.ctx.set_theme(name)
        app = QApplication.instance()
        if app is not None:
            app.setStyleSheet(qss(palette))
        self.theme_btn.setText("切换浅色" if name == "dark" else "切换深色")
        for page in self.pages.values():
            page.on_theme_changed(palette)

    def flash(self, text: str, ms: int = 4000) -> None:
        self.status_left.setText(text)
        QTimer.singleShot(ms, lambda: self.status_left.setText(""))

    def _update_status(self) -> None:
        try:
            n = len(self.ctx.repo.items)
        except Exception:
            n = 0
        self.status_right.setText(f"{n} 条记录   ·   {self.ctx.config.vault}")

    def closeEvent(self, e):
        try:
            self.ctx.config.save()
        except Exception:
            pass
        for page in self.pages.values():
            if hasattr(page, "runner"):
                page.runner.wait(1500)
        super().closeEvent(e)


def main(argv: list[str] | None = None) -> int:
    QApplication.setAttribute(Qt.AA_EnableHighDpiScaling, True)
    QApplication.setAttribute(Qt.AA_UseHighDpiPixmaps, True)
    app = QApplication(argv if argv is not None else sys.argv)
    app.setApplicationName(APP_NAME)
    app.setApplicationVersion(APP_VERSION)
    app.setFont(ui_font(13))

    cfg = get_config()
    cfg.ensure_dirs()
    cfg.seed_once()   # 首次运行补齐模板与示例，之后是空操作
    ctx = AppContext(config=cfg, repo=VaultRepository(cfg),
                     palette=PALETTES.get(cfg.theme, PALETTES["light"]))
    win = MainWindow(ctx)
    win.show()
    return app.exec_()


if __name__ == "__main__":
    sys.exit(main())
