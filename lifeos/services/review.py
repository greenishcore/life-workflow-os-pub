"""lifeos.services.review — 从 run-log 聚合周复盘

把「日志 → 统计 → 可沉淀项」自动化：成功率、工具 TopN、错误 TopN、耗时、近期产出。
等价于 scripts/weekly_review.py，但统计结果可直接喂给 GUI 图表。
"""
from __future__ import annotations

from collections import Counter
from dataclasses import dataclass, field
from datetime import datetime, timedelta
from pathlib import Path

from ..config import Config, get_config
from ..models import RunLog
from . import runlog as runlog_svc


@dataclass
class ReviewStats:
    since: str = ""
    total: int = 0
    by_status: dict[str, int] = field(default_factory=dict)
    tools: list[tuple[str, int]] = field(default_factory=list)
    errors: list[tuple[str, int]] = field(default_factory=list)
    outputs: list[str] = field(default_factory=list)
    duration: float = 0.0
    by_day: dict[str, int] = field(default_factory=dict)

    @property
    def success(self) -> int:
        return self.by_status.get("success", 0)

    @property
    def failed(self) -> int:
        return self.by_status.get("failed", 0) + self.by_status.get("partial", 0)

    @property
    def rate(self) -> float:
        return (self.success / self.total * 100) if self.total else 0.0


def default_since(days: int = 7) -> str:
    return (datetime.now() - timedelta(days=days)).strftime("%Y-%m-%d")


def aggregate(since: str | None = None, config: Config | None = None) -> ReviewStats:
    since = since or default_since()
    recs: list[RunLog] = runlog_svc.load(since=since, config=config)
    st = ReviewStats(since=since, total=len(recs))
    tools, errors, days = Counter(), Counter(), Counter()
    for r in recs:
        st.by_status[r.status] = st.by_status.get(r.status, 0) + 1
        tools.update(r.tools_used)
        errors.update(r.errors)
        st.outputs += r.outputs
        st.duration += r.duration_seconds or 0
        if r.date:
            days[r.date] += 1
    st.tools = tools.most_common(10)
    st.errors = errors.most_common(10)
    st.by_day = dict(sorted(days.items()))
    return st


def render_markdown(st: ReviewStats) -> str:
    lines = [
        f"# 周复盘 {st.since} 起",
        "",
        f"> 自动生成于 {datetime.now().strftime('%Y-%m-%d %H:%M')}，数据源 `logs/run-log.jsonl`",
        "",
        "## 总览",
        f"- 运行次数：{st.total}",
        f"- 成功率：{st.rate:.0f}%（成功 {st.success} / 失败 {st.failed}）",
        f"- 总耗时：{st.duration:.0f} 秒",
        f"- 状态分布：{st.by_status}",
        "",
        "## 工具使用 TopN",
    ]
    lines += [f"- {t}: {c}" for t, c in st.tools] or ["- （无）"]
    lines += ["", "## 错误 TopN（可沉淀为 checklist / skill）"]
    lines += [f"- [{c}次] {e}" for e, c in st.errors] or ["- （无）"]
    lines += ["", "## 近期产出"]
    seen, outs = set(), []
    for o in st.outputs[-30:]:
        if o not in seen:
            outs.append(f"- `{o}`")
            seen.add(o)
    lines += outs or ["- （无）"]
    lines += [
        "",
        "## 复盘结论与待沉淀",
        "- [ ] 把高频错误写成 checklist / 修正脚本",
        "- [ ] 把可复用的成功操作沉淀为 `skills/` 下的 skill",
        "- [ ] 更新提示词库 `prompts/` 的模板",
        "",
    ]
    return "\n".join(lines)


def write_report(st: ReviewStats, out: str | Path | None = None,
                 config: Config | None = None) -> Path:
    cfg = config or get_config()
    target = Path(out) if out else cfg.vault / "Daily" / f"周复盘-{st.since}.md"
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(render_markdown(st), encoding="utf-8")
    return target
