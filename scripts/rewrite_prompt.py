#!/usr/bin/env python3
"""rewrite_prompt.py — 交互前把口语化需求重写为五段式提示词文档

两种模式:
  1) 脚手架（默认，离线）: 把原始需求归档到 prompts/00_inbox/，生成五段式骨架到
     prompts/01_rewritten/<id>.md，原文填入「输入」段，其余段落留待补全。
  2) LLM 重写（--llm）: 用 Meta-Prompt 调用 LLM（OpenAI 兼容接口）真正重写。

用法:
  python3 rewrite_prompt.py "帮我做一个 PDF 转 Markdown 的工具"
  echo "需求..." | python3 rewrite_prompt.py
  python3 rewrite_prompt.py "需求..." --llm          # 需 OPENAI_API_KEY

环境变量（--llm 时）:
  OPENAI_API_KEY   必填
  OPENAI_BASE_URL  默认 https://api.openai.com/v1
  OPENAI_MODEL     默认 gpt-4o-mini
"""
import argparse, json, os, sys, urllib.request, uuid
from datetime import datetime

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PROMPTS = os.environ.get("PROMPT_DIR", os.path.join(ROOT, "prompts"))
INBOX = os.path.join(PROMPTS, "00_inbox")
REWRITTEN = os.path.join(PROMPTS, "01_rewritten")
META = os.path.join(PROMPTS, "02_templates", "meta-prompt.md")

META_INSTRUCTION = """你是一名提示词工程专家。请把用户的口语化需求改写为结构化的任务提示词文档。
要求：
1) 输出为 Markdown，按「角色 / 背景 / 目标 / 约束 / 输出格式 / 验收标准」组织；
2) 目标与验收标准必须可客观验证（含具体数值或示例）；
3) 若原话有歧义，单独列「待确认问题」段，不要擅自假设；
4) 保持原文语义，只做结构化与显式化，不添加原文没有的新需求；
5) 语言与用户原话保持一致。"""


def scaffold(raw):
    return f"""---
type: prompt
id: {{id}}
created: {{date}}
target: {{agent / model}}
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


def llm_rewrite(raw):
    key = os.environ.get("OPENAI_API_KEY")
    if not key:
        print("❌ --llm 需要 OPENAI_API_KEY 环境变量", file=sys.stderr)
        sys.exit(1)
    base = os.environ.get("OPENAI_BASE_URL", "https://api.openai.com/v1")
    model = os.environ.get("OPENAI_MODEL", "gpt-4o-mini")
    url = base.rstrip("/") + "/chat/completions"
    body = json.dumps({
        "model": model,
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
        with urllib.request.urlopen(req, timeout=120) as r:
            data = json.loads(r.read().decode("utf-8"))
        return data["choices"][0]["message"]["content"]
    except Exception as e:
        print(f"❌ LLM 调用失败: {e}", file=sys.stderr)
        sys.exit(1)


def main():
    ap = argparse.ArgumentParser(description="重写提示词")
    ap.add_argument("request", nargs="*", help="原始需求（可多段，或用 stdin）")
    ap.add_argument("--llm", action="store_true", help="用 LLM 重写（需 OPENAI_API_KEY）")
    args = ap.parse_args()

    raw = " ".join(args.request).strip()
    if not raw and not sys.stdin.isatty():
        raw = sys.stdin.read().strip()
    if not raw:
        print("无输入需求（参数或 stdin）", file=sys.stderr)
        sys.exit(1)

    os.makedirs(INBOX, exist_ok=True)
    os.makedirs(REWRITTEN, exist_ok=True)

    pid = datetime.now().strftime("%Y%m%d-%H%M%S-") + uuid.uuid4().hex[:6]
    # 归档原始需求
    with open(os.path.join(INBOX, f"{pid}.md"), "w", encoding="utf-8") as f:
        f.write(f"---\ntype: raw-request\nid: {pid}\ncreated: {datetime.now().isoformat()}\n---\n\n{raw}\n")

    if args.llm:
        content = llm_rewrite(raw)
        mode = "llm"
    else:
        content = scaffold(raw).replace("{id}", pid).replace("{date}", datetime.now().isoformat())
        mode = "scaffold"

    out = os.path.join(REWRITTEN, f"{pid}.md")
    with open(out, "w", encoding="utf-8") as f:
        f.write(content)

    print(f"[{mode}] 原始需求 → {INBOX}/{pid}.md")
    print(f"[{mode}] 重写结果 → {out}")
    if mode == "scaffold":
        print("提示：脚手架已生成，补齐各段即可；或加 --llm 让模型自动重写。")


if __name__ == "__main__":
    main()
