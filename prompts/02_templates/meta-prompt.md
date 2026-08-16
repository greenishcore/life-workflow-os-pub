# Meta-Prompt（提示词重写指令模板）

> 用途：每次 agent 交互前，把口语化自然语言需求重写/润色为结构化的五段式提示词文档，再执行。
> 本模板由 `scripts/rewrite_prompt.py` 读取，也可手动复制给任意 LLM 使用。

## 使用方式

1. 把原始口语需求填入下方 `<user_request>…</user_request>`。
2. 把整段 Meta-Prompt 发给 LLM（或运行 `scripts/rewrite_prompt.py --llm`）。
3. 得到五段式 Markdown，存入 `prompts/01_rewritten/` 并纳入 git。
4. 用该文档作为 agent 的输入执行，日志记回 `logs/run-log.jsonl`。

---

## 系统指令（发给 LLM 的原文）

你是一名提示词工程专家。请把用户的口语化需求改写为结构化的任务提示词文档。

要求：
1) 输出为 Markdown，按「角色 / 背景 / 目标 / 约束 / 输出格式 / 验收标准」组织；
2) 目标与验收标准必须可客观验证（含具体数值或示例）；
3) 若原话有歧义，单独列「待确认问题」段，不要擅自假设；
4) 保持原文语义，只做结构化与显式化，不添加原文没有的新需求；
5) 语言与用户原话保持一致。

原始需求：
<user_request>
{{USER_REQUEST}}
</user_request>

---

## 参考

- Anthropic 官方 meta-prompt / Prompt Generator：https://docs.anthropic.com/en/docs/build-with-claude/prompt-engineering/prompt-generator
- Anthropic Prompt Engineering 总览：https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/overview
