"""lifeos.frontmatter — Markdown frontmatter 的解析与「确定性」序列化

为什么自己写序列化而不是 yaml.dump：
  1. 输出必须**确定性**（字段顺序固定），否则每次保存都产生噪音 diff，污染 git 历史；
  2. 必须与仓库既有笔记的书写风格逐字节兼容（`tags: [a, b]`、
     `- {t: 2026-08-16, note: ...}`），保证 Obsidian / Dataview 与手写笔记互不打架；
  3. yaml.dump 会把中文转义、重排键、给日期加引号，可读性与 Obsidian 兼容性都变差。
"""
from __future__ import annotations

import datetime as _dt
import re
from typing import Any

import yaml

# 字段规范顺序（与 docs/02-architecture/data-model.md 一致）
FIELD_ORDER = [
    "type", "id", "title", "created", "updated", "status", "priority",
    "energy", "progress", "tags", "thinking_notes", "next_actions",
    "links", "source",
]
INLINE_LIST_FIELDS = {"tags"}
# 日期字段：以裸 YYYY-MM-DD 输出。读回时 models.norm_date 会归一化，
# 因此无需加引号——加了反而与手写笔记 / Dataview 的惯例不一致。
DATE_FIELDS = {"created", "updated"}

_FM_RE = re.compile(r"^---\s*\n(.*?)\n---[ \t]*\n?", re.S)
_PLAIN_UNSAFE_START = set("-?:,[]{}#&*!|>'\"%@`")
_YAML_KEYWORDS = {
    "true", "false", "null", "yes", "no", "on", "off", "~", "y", "n",
    "True", "False", "Null", "None",
}


# --------------------------------------------------------------------------
# 解析
# --------------------------------------------------------------------------
def split(text: str) -> tuple[str | None, str]:
    """拆出 (frontmatter 原文, 正文)；无 frontmatter 时返回 (None, 全文)。"""
    if not text.startswith("---"):
        return None, text
    m = _FM_RE.match(text)
    if not m:
        return None, text
    return m.group(1), text[m.end():]


def parse(text: str) -> tuple[dict[str, Any], str]:
    """返回 (frontmatter 字典, 正文)。解析失败按「无 frontmatter」处理，绝不抛。"""
    raw, body = split(text)
    if raw is None:
        return {}, body
    try:
        data = yaml.safe_load(raw)
    except Exception:
        return {}, text
    return (data if isinstance(data, dict) else {}), body


# --------------------------------------------------------------------------
# 序列化
# --------------------------------------------------------------------------
def _fmt_date(v: Any) -> str:
    if isinstance(v, (_dt.date, _dt.datetime)):
        return v.strftime("%Y-%m-%d")
    return str(v)


def _date_scalar(v: Any) -> str:
    """日期字段专用：裸 YYYY-MM-DD，识别不出来时退回普通标量。"""
    if isinstance(v, (_dt.date, _dt.datetime)):
        return v.strftime("%Y-%m-%d")
    s = str(v or "").strip()
    return s if re.fullmatch(r"\d{4}-\d{2}-\d{2}", s) else _scalar(v)


def _needs_quote(s: str, flow: bool = False) -> bool:
    if s == "":
        return True
    if s.strip() != s:
        return True
    if s[0] in _PLAIN_UNSAFE_START:
        return True
    if s in _YAML_KEYWORDS:
        return True
    if ": " in s or s.endswith(":") or " #" in s:
        return True
    if "\n" in s:
        return True
    # 纯数字/日期形态的字符串必须加引号，否则读回来会变成 int/date
    if re.fullmatch(r"[-+]?\d+(\.\d+)?|\d{4}-\d{2}-\d{2}", s):
        return True
    if flow and re.search(r"[,\[\]{}]", s):
        return True
    return False


def _scalar(v: Any, flow: bool = False) -> str:
    """把一个标量渲染成 YAML 片段。"""
    if v is None:
        return ""
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return str(v)
    if isinstance(v, (_dt.date, _dt.datetime)):
        return _fmt_date(v)
    s = str(v)
    if _needs_quote(s, flow):
        esc = s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")
        return f'"{esc}"'
    return s


def _emit_thinking_notes(notes: list) -> list[str]:
    """思路注释：优先 `- {t: 日期, note: 文本}` 单行流式，含换行时退化为块式。"""
    out = ["thinking_notes:"]
    if not notes:
        return ["thinking_notes: []"]
    for n in notes:
        if isinstance(n, dict):
            t, note = n.get("t") or n.get("date") or "", n.get("note") or ""
        else:
            t, note = "", str(n)
        note_s = str(note)
        if "\n" in note_s:
            out.append(f"  - t: {_date_scalar(t)}")
            indented = "\n".join("      " + ln for ln in note_s.splitlines())
            out.append("    note: |-")
            out.append(indented)
        else:
            out.append(f"  - {{t: {_date_scalar(t)}, note: {_scalar(note_s, flow=True)}}}")
    return out


def _emit_list(key: str, values: list) -> list[str]:
    values = [v for v in values if v is not None and str(v).strip() != ""]
    if not values:
        return [f"{key}: []"]
    if key in INLINE_LIST_FIELDS:
        return [f"{key}: [{', '.join(_scalar(v, flow=True) for v in values)}]"]
    return [f"{key}:"] + [f"  - {_scalar(v)}" for v in values]


def dump_frontmatter(fm: dict[str, Any]) -> str:
    """把字典渲染为确定性的 frontmatter 文本块（不含 --- 分隔线）。"""
    lines: list[str] = []
    seen: set[str] = set()

    for key in FIELD_ORDER:
        if key not in fm:
            continue
        seen.add(key)
        val = fm[key]
        if val is None:
            continue
        if key == "thinking_notes":
            lines += _emit_thinking_notes(val or [])
        elif isinstance(val, (list, tuple)):
            lines += _emit_list(key, list(val))
        elif key in DATE_FIELDS:
            lines.append(f"{key}: {_date_scalar(val)}")
        else:
            lines.append(f"{key}: {_scalar(val)}")

    # 未知字段：保留下来（不丢用户手写的东西），用标准 yaml 渲染
    extra = {k: v for k, v in fm.items() if k not in seen}
    if extra:
        dumped = yaml.safe_dump(
            extra, allow_unicode=True, sort_keys=True, default_flow_style=False
        ).rstrip("\n")
        lines += dumped.splitlines()

    return "\n".join(lines)


def dump(fm: dict[str, Any], body: str = "") -> str:
    """渲染完整文件内容（frontmatter + 正文）。"""
    head = dump_frontmatter(fm)
    body = (body or "").lstrip("\n").rstrip() + "\n"
    return f"---\n{head}\n---\n\n{body}"
