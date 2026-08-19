"""lifeos.services.prompts — 交互前把口语需求重写为结构化提示词

两种模式：
  · 脚手架（离线）：生成五段式骨架，原话填入「背景」，其余待补；
  · LLM 重写：用 Meta-Prompt 调 OpenAI 兼容接口真正改写。
原始需求归档到 prompts/00_inbox/，重写结果落 prompts/01_rewritten/，都纳入版本控制。
"""
from __future__ import annotations

import json
import os
import urllib.error
import urllib.request
import uuid
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path

from ..config import Config, get_config

META_INSTRUCTION = """你是一名提示词工程专家。请把用户的口语化需求改写为结构化的任务提示词文档。
要求：
1) 输出为 Markdown，按「角色 / 背景 / 目标 / 约束 / 输出格式 / 验收标准」组织；
2) 目标与验收标准必须可客观验证（含具体数值或示例）；
3) 若原话有歧义，单独列「待确认问题」段，不要擅自假设；
4) 保持原文语义，只做结构化与显式化，不添加原文没有的新需求；
5) 语言与用户原话保持一致。"""


@dataclass
class PromptDoc:
    pid: str
    raw_path: Path
    out_path: Path
    content: str
    mode: str      # scaffold | llm


def _scaffold(raw: str, pid: str) -> str:
    return f"""---
type: prompt
id: {pid}
created: {datetime.now().strftime('%Y-%m-%d')}
target: agent
tags: [prompt]
---

# 任务标题（一句话概括）

## 1. 角色（Role）
> 你是一名…

## 2. 背景（Context）
- 原始需求（口语化）：
  > {raw}

## 3. 目标（Objective）
- 需要交付的明确结果

## 4. 约束（Constraints）
- 语言/格式/范围/禁止事项

## 5. 输出格式（Output Format）
- 指定结构、语言、长度

## 6. 验收标准（Acceptance Criteria）
- [ ] 可客观验证的完成条件

## 7. 待确认问题（如有歧义）
- 
"""


def llm_available() -> bool:
    return bool(os.environ.get("OPENAI_API_KEY"))


def llm_rewrite(raw: str, config: Config | None = None, timeout: int = 120) -> str:
    """调用 OpenAI 兼容接口重写。失败时抛 RuntimeError，由调用方展示。"""
    cfg = config or get_config()
    key = os.environ.get("OPENAI_API_KEY")
    if not key:
        raise RuntimeError("未设置 OPENAI_API_KEY 环境变量，无法使用 LLM 重写")
    url = cfg.openai_base_url.rstrip("/") + "/chat/completions"
    body = json.dumps({
        "model": cfg.openai_model,
        "messages": [
            {"role": "system", "content": META_INSTRUCTION},
            {"role": "user", "content": raw},
        ],
        "temperature": 0.3,
    }).encode("utf-8")
    req = urllib.request.Request(url, data=body, headers={
        "Content-Type": "application/json",
        "Authorization": f"Bearer {key}",
    })
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            data = json.loads(r.read().decode("utf-8"))
        return data["choices"][0]["message"]["content"]
    except urllib.error.HTTPError as e:
        raise RuntimeError(f"LLM 接口返回 {e.code}：{e.read().decode('utf-8', 'ignore')[:300]}") from e
    except Exception as e:
        raise RuntimeError(f"LLM 调用失败：{e}") from e


def rewrite(raw: str, use_llm: bool = False, config: Config | None = None) -> PromptDoc:
    cfg = config or get_config()
    raw = (raw or "").strip()
    if not raw:
        raise ValueError("需求为空")

    inbox = cfg.prompts / "00_inbox"
    rewritten = cfg.prompts / "01_rewritten"
    inbox.mkdir(parents=True, exist_ok=True)
    rewritten.mkdir(parents=True, exist_ok=True)

    pid = datetime.now().strftime("%Y%m%d-%H%M%S-") + uuid.uuid4().hex[:6]
    raw_path = inbox / f"{pid}.md"
    raw_path.write_text(
        f"---\ntype: raw-request\nid: {pid}\ncreated: {datetime.now().isoformat(timespec='seconds')}\n---\n\n{raw}\n",
        encoding="utf-8",
    )

    if use_llm:
        content, mode = llm_rewrite(raw, cfg), "llm"
    else:
        content, mode = _scaffold(raw, pid), "scaffold"

    out_path = rewritten / f"{pid}.md"
    out_path.write_text(content, encoding="utf-8")
    return PromptDoc(pid, raw_path, out_path, content, mode)


def list_prompts(config: Config | None = None) -> list[Path]:
    cfg = config or get_config()
    d = cfg.prompts / "01_rewritten"
    if not d.is_dir():
        return []
    return sorted((p for p in d.glob("*.md")), key=lambda p: p.stem, reverse=True)
