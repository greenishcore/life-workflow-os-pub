#!/usr/bin/env python3
"""log_run.py — 兼容壳：命令行接口不变，逻辑已统一到 lifeos 包。

重构后所有业务逻辑只有一份实现（lifeos/），GUI 与命令行共用；
本文件保留是为了不打断既有的 GitHub Actions / launchd / Makefile / 手感。
等价命令：python3 -m lifeos.cli log ...
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from lifeos.cli import main  # noqa: E402

if __name__ == "__main__":
    sys.exit(main(["log", *sys.argv[1:]]))
