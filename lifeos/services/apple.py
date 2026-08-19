"""lifeos.services.apple — Apple 提醒事项 / 日历 / 备忘录 → Markdown

复用仓库里已调通的 AppleScript（scripts/*.scpt），只在 Python 侧统一
参数、错误提示与落点，避免 GUI 再去拼 shell。

注意：首次运行会弹「自动化」权限申请，需在
系统设置 → 隐私与安全性 → 自动化 中允许。
"""
from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

from ..config import Config, get_config
from ..repository import VaultRepository
from .proc import Logger, have, run


@dataclass
class ImportResult:
    ok: bool
    markdown: str
    target: Path | None
    message: str


def _osascript(script: Path, args: list[str], log: Logger | None = None, timeout: int = 120):
    if not script.is_file():
        return None, f"缺少脚本：{script}"
    if not have("osascript"):
        return None, "当前系统没有 osascript（仅 macOS 可用）"
    res = run(["osascript", str(script), *args], timeout=timeout, log=log)
    if not res.ok:
        hint = ""
        if "not allowed" in res.err.lower() or "-1743" in res.err:
            hint = "\n提示：需在「系统设置 → 隐私与安全性 → 自动化」中允许本程序控制该 App。"
        return None, (res.err.strip() or "AppleScript 执行失败") + hint
    return res.out.strip(), ""


def import_reminders(
    list_name: str = "", include_done: bool = False,
    config: Config | None = None, repo: VaultRepository | None = None,
    log: Logger | None = None,
) -> ImportResult:
    """提醒事项 → 当日 Daily 笔记的「## 提醒」段。"""
    cfg = config or get_config()
    repo = repo or VaultRepository(cfg)
    args = [list_name or cfg.default_reminder_list]
    if include_done:
        args.append("--all")
    md, err = _osascript(cfg.scripts / "reminders2obsidian.scpt", args, log)
    if md is None:
        return ImportResult(False, "", None, err)
    if not md.strip():
        return ImportResult(True, "", None, "该列表没有可导出的提醒")
    target = repo.upsert_section(repo.daily_note(), "提醒", md)
    return ImportResult(True, md, target, f"已写入 {target}")


def import_calendar(
    calendar_name: str = "", days: int = 7,
    config: Config | None = None, repo: VaultRepository | None = None,
    log: Logger | None = None,
) -> ImportResult:
    """日历未来 N 天 → 当日 Daily 笔记的「## 日程」段。"""
    cfg = config or get_config()
    repo = repo or VaultRepository(cfg)
    md, err = _osascript(
        cfg.scripts / "calendar2md.scpt",
        [calendar_name or cfg.default_calendar, str(days)], log,
    )
    if md is None:
        return ImportResult(False, "", None, err)
    if not md.strip():
        return ImportResult(True, "", None, f"未来 {days} 天没有日程")
    target = repo.upsert_section(repo.daily_note(), "日程", md)
    return ImportResult(True, md, target, f"已写入 {target}")


def import_notes(
    config: Config | None = None, log: Logger | None = None, timeout: int = 900,
) -> ImportResult:
    """Apple 备忘录 → vault/Inbox/notes-export/（依赖外部 notes-exporter）。"""
    cfg = config or get_config()
    script = cfg.scripts / "notes2obsidian.sh"
    if not script.is_file():
        return ImportResult(False, "", None, f"缺少脚本：{script}")
    out_dir = cfg.vault / "Inbox" / "notes-export"
    res = run(["bash", str(script), str(out_dir)], timeout=timeout, log=log,
              env={"VAULT_DIR": str(cfg.vault), "PATH": __import__("os").environ.get("PATH", "")})
    if not res.ok:
        return ImportResult(False, "", None, res.text or "导出失败")
    n = len(list(out_dir.rglob("*.md"))) if out_dir.is_dir() else 0
    return ImportResult(True, "", out_dir, f"已导出 {n} 篇备忘录 → {out_dir}")
