#!/usr/bin/env python3
"""生成应用图标：五阶段闭环（捕捉→整理→执行→复盘→归档）的环形节点。"""
import os, sys, subprocess, tempfile
from pathlib import Path

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from PyQt5.QtCore import QPointF, QRectF, Qt
from PyQt5.QtGui import QColor, QImage, QLinearGradient, QPainter, QPen
from PyQt5.QtWidgets import QApplication

from lifeos.models import Status

STAGE_COLORS = [s.color for s in Status.ordered()]


def render(size: int) -> QImage:
    img = QImage(size, size, QImage.Format_ARGB32)
    img.fill(Qt.transparent)
    p = QPainter(img)
    p.setRenderHint(QPainter.Antialiasing)

    # 圆角底板
    pad = size * 0.06
    rect = QRectF(pad, pad, size - pad * 2, size - pad * 2)
    grad = QLinearGradient(rect.topLeft(), rect.bottomRight())
    grad.setColorAt(0, QColor("#5b5bd6"))
    grad.setColorAt(1, QColor("#3730a3"))
    p.setPen(Qt.NoPen)
    p.setBrush(grad)
    p.drawRoundedRect(rect, size * 0.22, size * 0.22)

    # 闭环轨道
    cx = cy = size / 2
    r = size * 0.27
    ring = QRectF(cx - r, cy - r, r * 2, r * 2)
    p.setBrush(Qt.NoBrush)
    p.setPen(QPen(QColor(255, 255, 255, 70), size * 0.035, Qt.SolidLine, Qt.RoundCap))
    p.drawArc(ring, 60 * 16, 300 * 16)

    # 五个阶段节点
    import math
    for i, color in enumerate(STAGE_COLORS):
        ang = math.radians(90 - i * 72)
        x, y = cx + r * math.cos(ang), cy - r * math.sin(ang)
        node = size * (0.075 if i == 2 else 0.058)
        p.setPen(QPen(QColor("#3730a3"), size * 0.018))
        p.setBrush(QColor(color))
        p.drawEllipse(QPointF(x, y), node, node)
    p.end()
    return img


def main() -> int:
    app = QApplication(sys.argv)
    out_dir = Path(__file__).resolve().parent.parent / "assets"
    out_dir.mkdir(exist_ok=True)
    png = out_dir / "icon-1024.png"
    render(1024).save(str(png))

    # 组装 .icns（macOS 应用图标）
    with tempfile.TemporaryDirectory() as tmp:
        iconset = Path(tmp) / "AppIcon.iconset"
        iconset.mkdir()
        for sz in (16, 32, 64, 128, 256, 512, 1024):
            render(sz).save(str(iconset / f"icon_{sz}x{sz}.png"))
            if sz <= 512:
                render(sz * 2).save(str(iconset / f"icon_{sz}x{sz}@2x.png"))
        icns = out_dir / "AppIcon.icns"
        r = subprocess.run(["iconutil", "-c", "icns", str(iconset), "-o", str(icns)],
                           capture_output=True, text=True)
        if r.returncode != 0:
            print(f"⚠️ iconutil 失败：{r.stderr.strip()}")
            return 1
    print(f"✅ 图标已生成：{png.name} / AppIcon.icns")
    return 0


if __name__ == "__main__":
    sys.exit(main())
