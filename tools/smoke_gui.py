#!/usr/bin/env python3
"""GUI 离屏冒烟测试：逐页构建 + 渲染，任一页报错即失败。

跑：python3 tools/smoke_gui.py [--shots 输出目录]
CI 也能跑（QT_QPA_PLATFORM=offscreen，无需显示器）。
"""
from __future__ import annotations

import argparse
import os
import sys
import traceback
from pathlib import Path

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

PAGES = ["dashboard", "capture", "ideas", "convert", "prompts", "logs", "archive", "settings"]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--shots", help="把每页截图存到该目录")
    ap.add_argument("--theme", default="both", choices=["light", "dark", "both"])
    args = ap.parse_args()

    from PyQt5.QtWidgets import QApplication
    from lifeos.config import get_config
    from lifeos.gui.app import AppContext, MainWindow
    from lifeos.gui.theme import PALETTES
    from lifeos.repository import VaultRepository

    app = QApplication(sys.argv[:1])
    cfg = get_config()
    cfg.ensure_dirs()
    ctx = AppContext(config=cfg, repo=VaultRepository(cfg), palette=PALETTES["light"])
    win = MainWindow(ctx)
    win.resize(1320, 880)
    win.show()

    shots = Path(args.shots) if args.shots else None
    if shots:
        shots.mkdir(parents=True, exist_ok=True)

    themes = ["light", "dark"] if args.theme == "both" else [args.theme]
    failures: list[str] = []
    for theme in themes:
        win._apply_theme(theme)
        for key in PAGES:
            try:
                win.switch(key)
                for _ in range(20):
                    app.processEvents()
                if shots:
                    win.grab().save(str(shots / f"{key}-{theme}.png"))
                print(f"  ✅ {theme}/{key}")
            except Exception as exc:                      # noqa: BLE001
                failures.append(f"{theme}/{key}: {exc}")
                print(f"  ❌ {theme}/{key}: {exc}")
                traceback.print_exc()

    print(f"\n{'❌ 失败 ' + str(len(failures)) if failures else '✅ 全部页面通过'}")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
