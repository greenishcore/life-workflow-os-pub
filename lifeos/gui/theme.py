"""lifeos.gui.theme — 设计令牌与 QSS 主题

只在这一处定义颜色/字号/圆角/间距，页面里不写死颜色，
这样切换明暗主题、后续调品牌色都只改一个文件。
"""
from __future__ import annotations

from dataclasses import dataclass

from PyQt5.QtGui import QColor, QFont, QFontDatabase


@dataclass(frozen=True)
class Palette:
    name: str
    bg: str            # 窗口底色
    sidebar: str       # 侧边栏
    surface: str       # 卡片
    surface_alt: str   # 次级面（表头/输入框）
    text: str
    muted: str         # 次要文字
    faint: str         # 更淡（坐标轴、占位）
    border: str
    accent: str
    accent_soft: str   # 强调色的浅底
    danger: str
    ok: str
    warn: str
    grid: str          # 图表网格线
    heat: tuple        # 热力图 0→满 的色阶


LIGHT = Palette(
    name="light",
    bg="#f4f5f7", sidebar="#ffffff", surface="#ffffff", surface_alt="#f8f9fb",
    text="#1f2430", muted="#6b7280", faint="#9ca3af", border="#e4e7ec",
    accent="#4f46e5", accent_soft="#eef2ff",
    danger="#ef4444", ok="#10b981", warn="#f59e0b", grid="#eceef2",
    heat=("#eef0f4", "#c7d7f7", "#8fb3ef", "#5b8ae6", "#2f63cf"),
)

DARK = Palette(
    name="dark",
    bg="#14161b", sidebar="#181b21", surface="#1c2028", surface_alt="#222732",
    text="#e6e9ef", muted="#9aa3b2", faint="#6b7280", border="#2a2f3a",
    accent="#818cf8", accent_soft="#262a44",
    danger="#f87171", ok="#34d399", warn="#fbbf24", grid="#252a34",
    heat=("#20242c", "#25406e", "#2f5aa0", "#3f7ad0", "#5b9bf5"),
)

PALETTES = {"light": LIGHT, "dark": DARK}

# 间距与半径（保持整套界面节奏一致）
R_SM, R_MD, R_LG = 6, 10, 14
PAD = 16


def ui_font(size: int = 13, bold: bool = False) -> QFont:
    families = QFontDatabase().families()
    for name in ("PingFang SC", "Helvetica Neue", "Arial"):
        if name in families:
            f = QFont(name, size)
            break
    else:
        f = QFont()
        f.setPointSize(size)
    f.setBold(bold)
    return f


def mono_font(size: int = 12) -> QFont:
    families = QFontDatabase().families()
    for name in ("SF Mono", "Menlo", "Monaco", "Courier New"):
        if name in families:
            return QFont(name, size)
    f = QFont()
    f.setStyleHint(QFont.Monospace)
    f.setPointSize(size)
    return f


def qcolor(hex_str: str, alpha: int | None = None) -> QColor:
    c = QColor(hex_str)
    if alpha is not None:
        c.setAlpha(alpha)
    return c


def qss(p: Palette) -> str:
    """整个应用的样式表。"""
    return f"""
* {{ outline: none; }}

QWidget {{
    background: {p.bg};
    color: {p.text};
    font-size: 13px;
}}

/* ---------- 侧边栏 ---------- */
#Sidebar {{
    background: {p.sidebar};
    border-right: 1px solid {p.border};
}}
#BrandTitle {{ font-size: 15px; font-weight: 700; color: {p.text}; background: transparent; }}
#BrandSub   {{ font-size: 11px; color: {p.faint}; background: transparent; }}
#NavGroup   {{ font-size: 11px; color: {p.faint}; font-weight: 600; background: transparent;
              padding: 12px 0 2px 4px; letter-spacing: 1px; }}

QPushButton#NavItem {{
    background: transparent;
    border: none;
    border-radius: {R_SM}px;
    padding: 8px 10px;
    text-align: left;
    color: {p.muted};
    font-size: 13px;
}}
QPushButton#NavItem:hover  {{ background: {p.surface_alt}; color: {p.text}; }}
QPushButton#NavItem:checked {{ background: {p.accent_soft}; color: {p.accent}; font-weight: 600; }}

/* ---------- 卡片 ---------- */
#Card {{
    background: {p.surface};
    border: 1px solid {p.border};
    border-radius: {R_MD}px;
}}
#CardTitle {{ font-size: 13px; font-weight: 600; color: {p.text}; background: transparent; }}
#CardHint  {{ font-size: 11px; color: {p.faint}; background: transparent; }}

#PageTitle {{ font-size: 20px; font-weight: 700; background: transparent; }}
#PageSub   {{ font-size: 12px; color: {p.muted}; background: transparent; }}

#StatValue {{ font-size: 26px; font-weight: 700; background: transparent; }}
#StatLabel {{ font-size: 11px; color: {p.muted}; background: transparent; }}
#StatDelta {{ font-size: 11px; color: {p.faint}; background: transparent; }}

/* ---------- 按钮 ---------- */
QPushButton {{
    background: {p.surface};
    border: 1px solid {p.border};
    border-radius: {R_SM}px;
    padding: 6px 14px;
    color: {p.text};
}}
QPushButton:hover    {{ background: {p.surface_alt}; border-color: {p.accent}; }}
QPushButton:pressed  {{ background: {p.accent_soft}; }}
QPushButton:disabled {{ color: {p.faint}; border-color: {p.border}; background: {p.surface_alt}; }}

QPushButton#Primary {{
    background: {p.accent}; color: #ffffff; border: 1px solid {p.accent}; font-weight: 600;
}}
QPushButton#Primary:hover   {{ background: {p.accent}; border-color: {p.text}; }}
QPushButton#Primary:disabled {{ background: {p.faint}; border-color: {p.faint}; color: {p.surface}; }}
QPushButton#Ghost {{ background: transparent; border: none; color: {p.muted}; padding: 4px 8px; }}
QPushButton#Ghost:hover {{ color: {p.accent}; background: {p.surface_alt}; }}
QPushButton#Danger {{ color: {p.danger}; border-color: {p.border}; }}
QPushButton#Danger:hover {{ border-color: {p.danger}; background: {p.surface_alt}; }}

/* ---------- 输入 ---------- */
QLineEdit, QTextEdit, QPlainTextEdit, QComboBox, QSpinBox {{
    background: {p.surface};
    border: 1px solid {p.border};
    border-radius: {R_SM}px;
    padding: 6px 9px;
    selection-background-color: {p.accent};
    selection-color: #ffffff;
}}
QLineEdit:focus, QTextEdit:focus, QPlainTextEdit:focus, QComboBox:focus, QSpinBox:focus {{
    border-color: {p.accent};
}}
QLineEdit[search="true"] {{ padding-left: 10px; background: {p.surface_alt}; }}
QComboBox::drop-down {{ border: none; width: 18px; }}
QComboBox QAbstractItemView {{
    background: {p.surface}; border: 1px solid {p.border};
    selection-background-color: {p.accent_soft}; selection-color: {p.accent};
    outline: none; padding: 4px;
}}

/* ---------- 列表 / 表格 ---------- */
QListWidget, QTreeWidget, QTableWidget {{
    background: {p.surface};
    border: 1px solid {p.border};
    border-radius: {R_MD}px;
    padding: 4px;
}}
QListWidget::item {{ padding: 0px; border-radius: {R_SM}px; margin: 2px; }}
QListWidget::item:selected {{ background: {p.accent_soft}; }}
QListWidget::item:hover    {{ background: {p.surface_alt}; }}
QHeaderView::section {{
    background: {p.surface_alt}; color: {p.muted};
    border: none; border-bottom: 1px solid {p.border};
    padding: 7px 8px; font-weight: 600;
}}
QTableWidget {{ gridline-color: {p.border}; }}
QTableWidget::item {{ padding: 6px 8px; }}
QTableWidget::item:selected {{ background: {p.accent_soft}; color: {p.text}; }}

/* ---------- 滚动条 ---------- */
QScrollArea {{ border: none; background: transparent; }}
QScrollBar:vertical   {{ background: transparent; width: 10px; margin: 2px; }}
QScrollBar:horizontal {{ background: transparent; height: 10px; margin: 2px; }}
QScrollBar::handle:vertical, QScrollBar::handle:horizontal {{
    background: {p.border}; border-radius: 5px; min-height: 30px; min-width: 30px;
}}
QScrollBar::handle:hover {{ background: {p.faint}; }}
QScrollBar::add-line, QScrollBar::sub-line {{ height: 0; width: 0; }}
QScrollBar::add-page, QScrollBar::sub-page {{ background: transparent; }}

/* ---------- 其它 ---------- */
QSplitter::handle {{ background: {p.border}; }}
QSplitter::handle:horizontal {{ width: 1px; }}
QSplitter::handle:vertical   {{ height: 1px; }}

QSlider::groove:horizontal {{ height: 4px; background: {p.border}; border-radius: 2px; }}
QSlider::handle:horizontal {{
    background: {p.accent}; width: 14px; height: 14px;
    margin: -5px 0; border-radius: 7px;
}}
QSlider::sub-page:horizontal {{ background: {p.accent}; border-radius: 2px; }}

QProgressBar {{
    background: {p.surface_alt}; border: none; border-radius: 4px;
    height: 6px; text-align: center; color: transparent;
}}
QProgressBar::chunk {{ background: {p.accent}; border-radius: 4px; }}

QCheckBox {{ spacing: 7px; background: transparent; }}
QCheckBox::indicator {{
    width: 15px; height: 15px; border: 1px solid {p.border};
    border-radius: 4px; background: {p.surface};
}}
QCheckBox::indicator:checked {{ background: {p.accent}; border-color: {p.accent}; }}

QToolTip {{
    background: {p.surface}; color: {p.text};
    border: 1px solid {p.border}; border-radius: {R_SM}px; padding: 6px 8px;
}}

QStatusBar {{ background: {p.sidebar}; border-top: 1px solid {p.border}; color: {p.muted}; }}
QStatusBar::item {{ border: none; }}

#Console {{
    background: {p.surface_alt}; border: 1px solid {p.border};
    border-radius: {R_SM}px; color: {p.muted};
}}
#Divider {{ background: {p.border}; max-height: 1px; min-height: 1px; border: none; }}
"""
