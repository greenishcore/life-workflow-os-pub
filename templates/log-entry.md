# Agent 操作日志条目模板

```json
{
  "run_id": "{{run_id}}",
  "timestamp": "{{timestamp}}",
  "agent": "{{agent_name_or_session}}",
  "objective": "{{本次操作目标}}",
  "input_prompt_ref": "prompts/{{prompt_file}}.md",
  "tools_used": ["tool_a", "tool_b"],
  "process_summary": "{{过程摘要：关键步骤与决策}}",
  "outputs": ["{{产出文件路径1}}", "{{产出文件路径2}}"],
  "status": "success | partial | failed",
  "errors": ["{{错误信息}}"],
  "duration_seconds": 0,
  "model": "{{model_name}}",
  "notes": "{{复盘备注：哪些可沉淀为 skill}}"
}
```

> 说明：结构化日志建议以 JSONL 追加写入 `logs/run-log.jsonl`；同一目录可放一份可读的 `run-log.md` 便于人工浏览。日志中的 `input_prompt_ref` 指向 `prompts/` 下已重写润色的提示词文档，实现「提示词 → 执行 → 日志」闭环。
