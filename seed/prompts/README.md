# 提示词库（prompts/）

交互前「先重写、再执行」的提示词文档存放与版本管理约定。

```
prompts/
├── 00_inbox/            # 口语化原始需求（只读原话，自动归档）
├── 01_rewritten/        # 重写后的五段式提示词（纳入 git）
├── 02_templates/        # 可复用模板（meta-prompt、五段式骨架）
└── CHANGELOG.md         # 记录每次重写为何改哪段（建议追加）
```

## 工作流

1. `python3 scripts/rewrite_prompt.py "你的口语需求"`（或加 `--llm` 自动重写）。
2. 编辑 `01_rewritten/<id>.md` 补齐「角色/目标/约束/输出格式/验收标准」。
3. 把该文档作为 agent 输入执行。
4. 执行后用 `scripts/log_run.py --input-prompt-ref prompts/01_rewritten/<id>.md ...` 记日志。
5. `git commit` 记录「谁在何时把什么口语需求改成了什么提示词」。

## 模板

- `02_templates/meta-prompt.md` — 重写指令模板（发给 LLM 的 Meta-Prompt）
- 五段式骨架见 `rewrite_prompt.py` 的 scaffold 输出，或 `templates/prompt.md`
