"""lifeos.models — 领域模型（UI 无关）

「想法」是一等公民：时间 + 状态 + 优先级 + 标签 + 思路注释（思维轨迹）五个维度，
这也是融合时间看板的数据基础。
"""
from __future__ import annotations

import datetime as _dt
import re
import uuid
from dataclasses import dataclass, field
from enum import Enum
from pathlib import Path
from typing import Any

from . import frontmatter as fmlib


def today() -> str:
    return _dt.date.today().strftime("%Y-%m-%d")


def norm_date(v: Any) -> str:
    """把任意日期表示归一化为 YYYY-MM-DD；无法识别时返回空串。"""
    if v is None:
        return ""
    if isinstance(v, (_dt.date, _dt.datetime)):
        return v.strftime("%Y-%m-%d")
    m = re.match(r"(\d{4})-(\d{1,2})-(\d{1,2})", str(v).strip())
    if not m:
        return ""
    y, mo, d = m.groups()
    return f"{y}-{int(mo):02d}-{int(d):02d}"


class Status(str, Enum):
    """想法状态机：seed → sprout → doing → done → archived"""
    SEED = "seed"
    SPROUT = "sprout"
    DOING = "doing"
    DONE = "done"
    ARCHIVED = "archived"

    @property
    def label(self) -> str:
        return {
            "seed": "种子", "sprout": "发芽", "doing": "推进中",
            "done": "完成", "archived": "归档",
        }[self.value]

    @property
    def color(self) -> str:
        return {
            "seed": "#f59e0b", "sprout": "#84cc16", "doing": "#3b82f6",
            "done": "#10b981", "archived": "#9ca3af",
        }[self.value]

    @classmethod
    def coerce(cls, v: Any) -> "Status":
        try:
            return cls(str(v).strip().lower())
        except Exception:
            return cls.SEED

    @classmethod
    def ordered(cls) -> list["Status"]:
        return [cls.SEED, cls.SPROUT, cls.DOING, cls.DONE, cls.ARCHIVED]

    def next(self) -> "Status":
        order = Status.ordered()
        return order[min(order.index(self) + 1, len(order) - 1)]


class Priority(str, Enum):
    HIGH = "high"
    MEDIUM = "medium"
    LOW = "low"

    @property
    def label(self) -> str:
        return {"high": "高", "medium": "中", "low": "低"}[self.value]

    @property
    def weight(self) -> int:
        """散点图里的点径。"""
        return {"high": 22, "medium": 15, "low": 10}[self.value]

    @property
    def color(self) -> str:
        return {"high": "#ef4444", "medium": "#f59e0b", "low": "#94a3b8"}[self.value]

    @classmethod
    def coerce(cls, v: Any) -> "Priority":
        try:
            return cls(str(v).strip().lower())
        except Exception:
            return cls.MEDIUM

    @classmethod
    def ordered(cls) -> list["Priority"]:
        return [cls.HIGH, cls.MEDIUM, cls.LOW]


class ItemType(str, Enum):
    IDEA = "idea"
    TASK = "task"
    DAILY = "daily"
    NOTE = "note"

    @property
    def label(self) -> str:
        return {"idea": "想法", "task": "任务", "daily": "日记", "note": "笔记"}[self.value]

    @classmethod
    def coerce(cls, v: Any) -> "ItemType":
        try:
            return cls(str(v).strip().lower())
        except Exception:
            return cls.NOTE


@dataclass
class ThinkingNote:
    """思路注释：带时间戳的思维轨迹增量。"""
    t: str = field(default_factory=today)
    note: str = ""

    @classmethod
    def coerce(cls, v: Any, fallback_date: str = "") -> "ThinkingNote":
        if isinstance(v, ThinkingNote):
            return v
        if isinstance(v, dict):
            return cls(
                t=norm_date(v.get("t") or v.get("date")) or fallback_date or today(),
                note=str(v.get("note") or "").strip(),
            )
        return cls(t=fallback_date or today(), note=str(v).strip())

    def to_dict(self) -> dict:
        return {"t": self.t, "note": self.note}


@dataclass
class Item:
    """vault 中的一条记录（想法/任务/日记/笔记）。"""

    title: str = ""
    type: ItemType = ItemType.IDEA
    id: str = ""
    created: str = field(default_factory=today)
    updated: str = ""
    status: Status = Status.SEED
    priority: Priority = Priority.MEDIUM
    energy: int | None = None
    progress: int | None = None
    tags: list[str] = field(default_factory=list)
    thinking_notes: list[ThinkingNote] = field(default_factory=list)
    next_actions: list[str] = field(default_factory=list)
    links: list[str] = field(default_factory=list)
    body: str = ""
    path: Path | None = None
    extra: dict[str, Any] = field(default_factory=dict)

    # ---------- 读 ----------
    @classmethod
    def from_text(cls, text: str, path: Path | None = None) -> "Item | None":
        """从 Markdown 文本构造；无 frontmatter 或缺少可视化必需字段时返回 None。"""
        fm, body = fmlib.parse(text)
        if not fm:
            return None
        typ = fm.get("type")
        # 收录条件：显式 type 为 idea/task，或带 status 的任意记录
        if str(typ).lower() not in ("idea", "task") and "status" not in fm:
            return None

        created = norm_date(fm.get("created") or fm.get("date"))
        if not created and path is not None:
            m = re.search(r"(\d{4}-\d{2}-\d{2})", path.name)
            created = m.group(1) if m else ""
        if not created:
            created = today()

        known = set(fmlib.FIELD_ORDER)
        item = cls(
            title=str(fm.get("title") or fm.get("id") or (path.stem if path else "")),
            type=ItemType.coerce(typ),
            id=str(fm.get("id") or ""),
            created=created,
            updated=norm_date(fm.get("updated")),
            status=Status.coerce(fm.get("status")),
            priority=Priority.coerce(fm.get("priority")),
            energy=_as_int(fm.get("energy"), 0, 10),
            progress=_as_int(fm.get("progress"), 0, 100),
            tags=[str(t) for t in (fm.get("tags") or []) if str(t).strip()],
            thinking_notes=[
                ThinkingNote.coerce(n, created) for n in (fm.get("thinking_notes") or [])
            ],
            next_actions=[str(a) for a in (fm.get("next_actions") or []) if str(a).strip()],
            links=[str(l) for l in (fm.get("links") or []) if str(l).strip()],
            body=body,
            path=path,
            extra={k: v for k, v in fm.items() if k not in known},
        )
        return item

    # ---------- 写 ----------
    def to_frontmatter(self) -> dict[str, Any]:
        fm: dict[str, Any] = {
            "type": self.type.value,
            "id": self.id or self.new_id(),
            "title": self.title,
            "created": self.created or today(),
            "status": self.status.value,
            "priority": self.priority.value,
        }
        # updated 只在确实有值时写出：由 touch()/仓库层在内容变更时设置，
        # 避免「只读打开也产生 diff」。
        if self.updated:
            fm["updated"] = self.updated
        if self.energy is not None:
            fm["energy"] = self.energy
        if self.progress is not None:
            fm["progress"] = self.progress
        fm["tags"] = list(self.tags)
        fm["thinking_notes"] = [n.to_dict() for n in self.thinking_notes]
        fm["next_actions"] = list(self.next_actions)
        fm["links"] = list(self.links)
        fm.update(self.extra)
        return fm

    def to_text(self) -> str:
        body = self.body.strip()
        if not body:
            body = f"# {self.title}\n"
        return fmlib.dump(self.to_frontmatter(), body)

    # ---------- 辅助 ----------
    @staticmethod
    def new_id() -> str:
        return f"{today()}-{uuid.uuid4().hex[:4]}"

    def touch(self) -> None:
        self.updated = today()

    def add_thinking_note(self, note: str, when: str | None = None) -> ThinkingNote:
        tn = ThinkingNote(t=when or today(), note=note.strip())
        self.thinking_notes.append(tn)
        self.touch()
        return tn

    @property
    def last_activity(self) -> str:
        """最近一次「有动静」的日期：思路注释 > updated > created。"""
        dates = [self.created, self.updated] + [n.t for n in self.thinking_notes]
        return max([d for d in dates if d] or [self.created])

    def matches(self, query: str) -> bool:
        if not query:
            return True
        q = query.lower()
        haystack = " ".join(
            [self.title, self.id, " ".join(self.tags), self.body]
            + [n.note for n in self.thinking_notes]
            + self.next_actions
        ).lower()
        return q in haystack


def _as_int(v: Any, lo: int, hi: int) -> int | None:
    if v is None or v == "":
        return None
    try:
        return max(lo, min(hi, int(float(v))))
    except Exception:
        return None


@dataclass
class RunLog:
    """一次 agent 操作的留痕。"""
    run_id: str = ""
    timestamp: str = ""
    agent: str = "agent"
    objective: str = ""
    input_prompt_ref: str = ""
    tools_used: list[str] = field(default_factory=list)
    process_summary: str = ""
    outputs: list[str] = field(default_factory=list)
    status: str = "success"          # success | partial | failed
    errors: list[str] = field(default_factory=list)
    duration_seconds: float = 0.0
    model: str = ""
    notes: str = ""

    STATUS_ICON = {"success": "✅", "partial": "🟡", "failed": "❌"}
    STATUS_COLOR = {"success": "#10b981", "partial": "#f59e0b", "failed": "#ef4444"}

    @classmethod
    def from_dict(cls, d: dict) -> "RunLog":
        def as_list(v):
            if isinstance(v, list):
                return [str(x) for x in v]
            return [s.strip() for s in str(v or "").split(",") if s.strip()]
        return cls(
            run_id=str(d.get("run_id") or ""),
            timestamp=str(d.get("timestamp") or ""),
            agent=str(d.get("agent") or "agent"),
            objective=str(d.get("objective") or ""),
            input_prompt_ref=str(d.get("input_prompt_ref") or ""),
            tools_used=as_list(d.get("tools_used")),
            process_summary=str(d.get("process_summary") or ""),
            outputs=as_list(d.get("outputs")),
            status=str(d.get("status") or "success"),
            errors=as_list(d.get("errors")),
            duration_seconds=float(d.get("duration_seconds") or 0),
            model=str(d.get("model") or ""),
            notes=str(d.get("notes") or ""),
        )

    def to_dict(self) -> dict:
        return {
            "run_id": self.run_id, "timestamp": self.timestamp, "agent": self.agent,
            "objective": self.objective, "input_prompt_ref": self.input_prompt_ref,
            "tools_used": self.tools_used, "process_summary": self.process_summary,
            "outputs": self.outputs, "status": self.status, "errors": self.errors,
            "duration_seconds": self.duration_seconds, "model": self.model,
            "notes": self.notes,
        }

    @property
    def icon(self) -> str:
        return self.STATUS_ICON.get(self.status, "•")

    @property
    def color(self) -> str:
        return self.STATUS_COLOR.get(self.status, "#94a3b8")

    @property
    def date(self) -> str:
        return self.timestamp[:10]
