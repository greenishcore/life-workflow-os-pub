# Skills 库（可复用技能）

> 把「可复用、已验证」的操作序列沉淀为 skill：Markdown 指令 + 脚本 + 验收标准。
> 每个 skill 由周复盘（`weekly_review.py`）或人工识别后创建，随使用迭代版本化。

## 目录约定

```
skills/
├── README.md              # 本文件
├── _template.md           # 新建 skill 的模板
└── <skill-name>.md        # 每个 skill 一个文件
```

## 一个 skill 包含什么

见 `_template.md`，核心字段：`id / 名称 / 触发条件 / 依赖 / 状态 / 目标 / 步骤 / 脚本 / 验收标准 / 效果评分`。

## 从 run-log 演进 skills 的闭环

```
agent 操作 ──► logs/run-log.jsonl（成果+过程）
                    │  weekly_review.py 聚合
                    ▼
            复盘：识别「可复用成功操作」+「高频失败坑」
                    │
        ┌───────────┴───────────┐
        ▼                       ▼
  新建/更新 skill          修正脚本/checklist
        │
        └──► 下次同类任务直接调用 skill，而非重试试错
```

## 判定：什么值得沉淀为 skill

- 被多次执行、步骤固定的操作（如格式转换、日志记录、提示词重写）。
- 有明确输入/输出与可验证结果。
- 失败过一次、已找到稳定解法（把坑写进 skill 的「注意」）。

## 已收录 skills

| 名称 | 用途 |
|------|------|
| [convert-document](convert-document.md) | 任意格式 ↔ Markdown 的固化转换 pipeline |
