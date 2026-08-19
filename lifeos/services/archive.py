"""lifeos.services.archive — Git 版本归档与里程碑发布

对应 scripts/sync.sh 与 scripts/release.sh：
  · sync：pull --rebase → add -A → commit → push
  · release：打 tag + gh release
"""
from __future__ import annotations

import re
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path

from ..config import REPO_ROOT, Config, get_config
from .proc import Logger, have, run

SEMVER = re.compile(r"^v\d+\.\d+\.\d+$")


@dataclass
class GitStatus:
    is_repo: bool = False
    branch: str = ""
    changed: list[str] = field(default_factory=list)
    ahead: int = 0
    behind: int = 0
    remote: str = ""
    last_commit: str = ""

    @property
    def dirty(self) -> bool:
        return bool(self.changed)


def repo_root(config: Config | None = None) -> Path:
    cfg = config or get_config()
    r = run(["git", "rev-parse", "--show-toplevel"], cwd=REPO_ROOT, timeout=15)
    return Path(r.out.strip()) if r.ok and r.out.strip() else REPO_ROOT


def status(config: Config | None = None) -> GitStatus:
    root = repo_root(config)
    st = GitStatus()
    if not have("git"):
        return st
    if not run(["git", "rev-parse", "--is-inside-work-tree"], cwd=root, timeout=15).ok:
        return st
    st.is_repo = True
    st.branch = run(["git", "rev-parse", "--abbrev-ref", "HEAD"], cwd=root, timeout=15).out.strip()
    # core.quotepath=false：否则中文文件名会显示成 \346\227\266 这样的八进制转义
    porcelain = run(["git", "-c", "core.quotepath=false", "status", "--porcelain"],
                    cwd=root, timeout=30).out
    st.changed = [ln.strip() for ln in porcelain.splitlines() if ln.strip()]
    st.remote = run(["git", "remote", "get-url", "origin"], cwd=root, timeout=15).out.strip()
    st.last_commit = run(["git", "log", "-1", "--pretty=%h %s (%cr)"], cwd=root, timeout=15).out.strip()
    counts = run(["git", "rev-list", "--left-right", "--count", "@{upstream}...HEAD"],
                 cwd=root, timeout=20)
    if counts.ok and counts.out.strip():
        parts = counts.out.split()
        if len(parts) == 2:
            st.behind, st.ahead = int(parts[0]), int(parts[1])
    return st


def sync(message: str = "", push: bool = True, config: Config | None = None,
         log: Logger | None = None) -> tuple[bool, str]:
    """一键提交并推送。返回 (成功, 说明)。"""
    root = repo_root(config)
    if not have("git"):
        return False, "未安装 git"
    run(["git", "pull", "--rebase", "--autostash"], cwd=root, timeout=180, log=log)
    run(["git", "add", "-A"], cwd=root, timeout=60, log=log)
    if run(["git", "diff", "--cached", "--quiet"], cwd=root, timeout=30).ok:
        return True, "无变更，跳过提交"
    msg = message.strip() or f"auto: {datetime.now():%Y-%m-%d %H:%M} 工作流同步"
    r = run(["git", "commit", "-m", msg], cwd=root, timeout=60, log=log)
    if not r.ok:
        return False, r.text or "提交失败"
    if not push:
        return True, f"已提交（未推送）：{msg}"
    rp = run(["git", "push"], cwd=root, timeout=180, log=log)
    if not rp.ok:
        return False, f"已提交但推送失败：{rp.text}"
    return True, f"已提交并推送：{msg}"


def tags(config: Config | None = None) -> list[str]:
    r = run(["git", "tag", "--sort=-v:refname"], cwd=repo_root(config), timeout=30)
    return [t for t in r.out.split() if t]


def release(version: str, notes: str = "", config: Config | None = None,
            log: Logger | None = None) -> tuple[bool, str]:
    """打里程碑 tag 并发 GitHub release。"""
    root = repo_root(config)
    version = version.strip()
    if not SEMVER.match(version):
        return False, "版本号需形如 v0.2.0（语义化版本）"
    if version in tags(config):
        return False, f"标签 {version} 已存在"
    notes = notes.strip() or f"{version} 阶段成果"
    r = run(["git", "tag", "-a", version, "-m", notes], cwd=root, timeout=60, log=log)
    if not r.ok:
        return False, r.text or "打标签失败"
    rp = run(["git", "push", "origin", version], cwd=root, timeout=180, log=log)
    if not rp.ok:
        return False, f"标签已创建但推送失败：{rp.text}"
    if not have("gh"):
        return True, f"标签 {version} 已推送（未安装 gh，跳过 release）"
    rg = run(["gh", "release", "create", version, "--title", version, "--notes", notes],
             cwd=root, timeout=180, log=log)
    if not rg.ok:
        return False, f"标签已推送但 release 创建失败：{rg.text}"
    return True, f"已发布里程碑 {version}"


def log_history(limit: int = 30, config: Config | None = None) -> list[tuple[str, str, str]]:
    """返回 [(短哈希, 相对时间, 标题)]。"""
    r = run(["git", "log", f"-{limit}", "--pretty=%h\x1f%cr\x1f%s"],
            cwd=repo_root(config), timeout=30)
    out = []
    for line in r.out.splitlines():
        parts = line.split("\x1f")
        if len(parts) == 3:
            out.append(tuple(parts))
    return out
