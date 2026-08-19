"""lifeos.services.runlog — agent 操作日志（JSONL 主 + Markdown 辅）

每次 agent 操作留痕：输入提示词、工具、过程、产出、错误、耗时、模型、复盘备注。
JSONL 供程序聚合（周复盘），Markdown 供人浏览。等价于 scripts/log_run.py。
"""
from __future__ import annotations

import json
import uuid
from datetime import datetime, timezone
from pathlib import Path

from ..config import Config, get_config
from ..models import RunLog

STATUSES = ["success", "partial", "failed"]


def _now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def append(log: RunLog, config: Config | None = None) -> RunLog:
    """追加一条日志到 JSONL + Markdown。"""
    cfg = config or get_config()
    if not log.objective.strip():
        raise ValueError("objective（这次做了什么）不能为空")
    log.run_id = log.run_id or uuid.uuid4().hex[:12]
    log.timestamp = log.timestamp or _now()
    if log.status not in STATUSES:
        log.status = "success"

    cfg.logs.mkdir(parents=True, exist_ok=True)
    with open(cfg.run_log_jsonl, "a", encoding="utf-8") as f:
        f.write(json.dumps(log.to_dict(), ensure_ascii=False) + "\n")
    with open(cfg.run_log_md, "a", encoding="utf-8") as f:
        f.write(_markdown_line(log) + "\n")
    return log


def _markdown_line(r: RunLog) -> str:
    line = f"- {r.icon} `{r.run_id}` {r.timestamp} **{r.objective}**"
    if r.tools_used:
        line += f" | 工具: {', '.join(r.tools_used)}"
    if r.duration_seconds:
        line += f" | {r.duration_seconds:g}s"
    if r.outputs:
        line += f"\n  - 产出: {', '.join(r.outputs)}"
    if r.errors:
        line += f"\n  - 错误: {'; '.join(r.errors)}"
    if r.notes:
        line += f"\n  - 复盘: {r.notes}"
    return line


def load(since: str | None = None, config: Config | None = None) -> list[RunLog]:
    """读取全部日志（按时间倒序）。since 为 YYYY-MM-DD。"""
    cfg = config or get_config()
    path: Path = cfg.run_log_jsonl
    if not path.is_file():
        return []
    out: list[RunLog] = []
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            data = json.loads(line)
        except json.JSONDecodeError:
            continue
        if since and str(data.get("timestamp", ""))[:10] < since:
            continue
        out.append(RunLog.from_dict(data))
    out.sort(key=lambda r: r.timestamp, reverse=True)
    return out
