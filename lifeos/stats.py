"""lifeos.stats — 看板所需的统计聚合（纯函数，无 UI 依赖）

「融合时间」的含义：同一份数据同时按 时间 / 状态 / 优先级 / 精力 / 思维轨迹
四五个维度聚合，让看板能回答「这个想法何时产生、如何演进、现在到哪一步」。
"""
from __future__ import annotations

import datetime as _dt
from collections import Counter
from dataclasses import dataclass, field

from .models import Item, Priority, Status


@dataclass
class Point:
    """融合散点的一个点：X=时间 Y=精力 大小=优先级 颜色=状态。"""
    date: str
    energy: int
    size: int
    status: Status
    priority: Priority
    title: str
    item: Item | None = None


@dataclass
class Summary:
    total: int = 0
    by_status: dict[Status, int] = field(default_factory=dict)
    by_priority: dict[Priority, int] = field(default_factory=dict)
    active: int = 0            # 推进中
    done: int = 0
    avg_progress: float = 0.0
    total_notes: int = 0       # 思路注释总数
    streak: int = 0            # 连续活跃天数
    span_days: int = 0


def date_range(items: list[Item]) -> tuple[str, str]:
    dates = [i.created for i in items if i.created]
    for i in items:
        dates += [n.t for n in i.thinking_notes if n.t]
    if not dates:
        t = _dt.date.today().strftime("%Y-%m-%d")
        return t, t
    return min(dates), max(dates)


def activity_heat(items: list[Item]) -> dict[str, int]:
    """每日活跃度 = 当天新建的记录数 + 当天写下的思路注释数。

    比「只数创建」更能反映真实投入：一个想法持续演进也算活跃。
    """
    heat: Counter[str] = Counter()
    for it in items:
        if it.created:
            heat[it.created] += 1
        for n in it.thinking_notes:
            if n.t and n.t != it.created:
                heat[n.t] += 1
    return dict(heat)


def status_counts(items: list[Item]) -> dict[Status, int]:
    c = Counter(i.status for i in items)
    return {s: c.get(s, 0) for s in Status.ordered()}


def priority_counts(items: list[Item]) -> dict[Priority, int]:
    c = Counter(i.priority for i in items)
    return {p: c.get(p, 0) for p in Priority.ordered()}


def timeline_points(items: list[Item]) -> list[Point]:
    return [
        Point(
            date=it.created,
            energy=it.energy if it.energy is not None else 0,
            size=it.priority.weight,
            status=it.status,
            priority=it.priority,
            title=it.title,
            item=it,
        )
        for it in items if it.created
    ]


def tag_counts(items: list[Item], top: int = 12) -> list[tuple[str, int]]:
    c: Counter[str] = Counter()
    for it in items:
        c.update(it.tags)
    return c.most_common(top)


def streak(items: list[Item], today: str | None = None) -> int:
    """从今天往回数，连续有活跃记录的天数。"""
    heat = activity_heat(items)
    if not heat:
        return 0
    day = _dt.date.fromisoformat(today) if today else _dt.date.today()
    # 今天还没记录也不算断，从昨天起算
    if day.strftime("%Y-%m-%d") not in heat:
        day -= _dt.timedelta(days=1)
    n = 0
    while day.strftime("%Y-%m-%d") in heat:
        n += 1
        day -= _dt.timedelta(days=1)
    return n


def summarize(items: list[Item]) -> Summary:
    s = Summary(total=len(items))
    s.by_status = status_counts(items)
    s.by_priority = priority_counts(items)
    s.active = s.by_status.get(Status.DOING, 0)
    s.done = s.by_status.get(Status.DONE, 0)
    progresses = [i.progress for i in items if i.progress is not None]
    s.avg_progress = sum(progresses) / len(progresses) if progresses else 0.0
    s.total_notes = sum(len(i.thinking_notes) for i in items)
    s.streak = streak(items)
    lo, hi = date_range(items)
    try:
        s.span_days = (_dt.date.fromisoformat(hi) - _dt.date.fromisoformat(lo)).days + 1
    except ValueError:
        s.span_days = 0
    return s


def trajectory(items: list[Item]) -> list[tuple[str, str, Item]]:
    """全库思维轨迹：把所有思路注释按时间铺平，(日期, 注释, 所属记录)。"""
    out = [(n.t, n.note, it) for it in items for n in it.thinking_notes if n.note]
    out.sort(key=lambda x: x[0], reverse=True)
    return out


def progress_buckets(items: list[Item], buckets: int = 5) -> list[tuple[str, int]]:
    """进度分布，用于柱状图。"""
    edges = [(i * 100 // buckets, (i + 1) * 100 // buckets) for i in range(buckets)]
    counts = [0] * buckets
    for it in items:
        p = it.progress
        if p is None:
            continue
        idx = min(p * buckets // 100, buckets - 1)
        counts[idx] += 1
    return [(f"{lo}-{hi}%", c) for (lo, hi), c in zip(edges, counts)]
