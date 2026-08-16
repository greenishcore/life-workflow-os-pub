# 调研报告 R1-02：PDF/Markdown 互转、Agent 操作日志、提示词重写工作流

> 来源：后台检索 agent 调研，关键工具与 URL 均已 web 核实。日期见文件提交记录。

---

## 一、PDF ↔ Markdown 及文字格式互转固化路径

**核心思路**：统一收敛到「**任意输入格式 → 中间态 Markdown → 任意输出格式**」。Markdown 作为唯一可 diff、可 git、可缓存、可再生的中间表示，两端用不同工具桥接。关键事实：**pandoc 不读 PDF**（PDF 是 pandoc 的输出-only 格式），因此 PDF→Markdown 必须走 OCR 或文本抽取工具，再交给 pandoc 做二次转换。

### 1.1 pandoc（万能格式交换机）

- 工具：[pandoc](https://pandoc.org/MANUAL.html)，Haskell 编写，支持数十种格式互转。

```bash
# Markdown → PDF（中文需 xelatex + CJK 字体）
pandoc input.md -o output.pdf --pdf-engine=xelatex \
  -V CJKmainfont="Noto Sans CJK SC" -V geometry:margin=2cm
# Markdown → docx
pandoc input.md -o output.docx -f markdown -t docx
# docx → Markdown（GitHub 风格）
pandoc input.docx -o output.md -f docx -t gfm --extract-media=./media
# HTML → Markdown；Markdown → HTML
pandoc input.html -o output.md -f html -t gfm
pandoc input.md -o output.html -f gfm -t html --standalone
```

要点：生成 PDF 需 LaTeX 引擎（`xelatex`/`lualatex` 支持中文，`pdflatex` 不支持中文）；`--standalone`/`-s`、`--toc`、`--resource-path` 常用。

### 1.2 Microsoft markitdown（Office/PDF/图片/音频 → Markdown）

- 工具：[microsoft/markitdown](https://github.com/microsoft/markitdown)，微软官方开源 Python 库 + CLI。
- 支持：PDF、pptx、docx、xlsx、图片（EXIF + 可选 OCR）、音频（EXIF + 转写）、HTML、CSV/JSON/XML、ZIP、EPUB、YouTube URL 等。

```bash
pip install 'markitdown[all]'
markitdown 合同.pdf > 合同.md
markitdown -o out.md 报告.docx
markitdown -p url https://example.com/article
```

```python
from markitdown import MarkItDown
md = MarkItDown()
result = md.convert("slides.pptx")
print(result.text_content)
```

要点：文本型 PDF 可直接转；图片 OCR 需额外配置多模态 LLM；对 Office 复杂排版比纯 pandoc 更友好。

### 1.3 Markdown → PDF 方案对比

| 方案 | 工具 | 命令 | 特点 |
|---|---|---|---|
| pandoc + LaTeX | pandoc | 见 1.1 | 排版最好、学术引用、中文需 xelatex+CJK |
| md-to-pdf | [simonhaenisch/md-to-pdf](https://github.com/simonhaenisch/md-to-pdf) | `npm i -g md-to-pdf && md-to-pdf README.md` | headless Chrome 渲染，CSS 可定制，支持 Mermaid |
| wkhtmltopdf | [wkhtmltopdf.org](https://wkhtmltopdf.org/) | `wkhtmltopdf input.html output.pdf` | 需先 MD→HTML；对现代 CSS 支持差 |
| Chrome headless | Chrome | `chrome --headless=new --print-to-pdf=out.pdf --no-pdf-header-footer file:///in.html` | 无额外依赖，保真度最高 |

### 1.4 PDF → 文本/Markdown OCR 方案

1. **ocrmypdf**（首选，给 PDF 加可搜索文本层，保留原貌）：[ocrmypdf/OCRmyPDF](https://github.com/ocrmypdf/OCRmyPDF)
   ```bash
   pip install ocrmypdf
   ocrmypdf input.pdf output.pdf
   ocrmypdf --skip-text input.pdf output.pdf   # 只处理扫描页
   ```
2. **tesseract**（底层 OCR 引擎）：[tesseract-ocr/tesseract](https://github.com/tesseract-ocr/tesseract)
   ```bash
   tesseract input.png output -l chi_sim+eng
   tesseract input.pdf output pdf
   ```
3. **大模型视觉解析**（扫描件→结构化 Markdown，保表格/版面）：
   - [getomni-ai/zerox](https://github.com/getomni-ai/zerox)（Python 包 `py-zerox`），用视觉模型把 PDF 逐页转 Markdown，保留表格布局。
   - 直接调多模态 API：OpenAI [Vision](https://platform.openai.com/docs/guides/vision)、Anthropic [PDF support](https://docs.anthropic.com/en/docs/build-with-claude/pdf-support)。

要点：文本型 PDF 用抽取；扫描件先 ocrmypdf；需结构化 Markdown + 表格还原再用 zerox/视觉模型（最贵）。

### 1.5 固化为可复用 pipeline（目录约定 + 缓存，省算力）

```
pipeline/
  raw/            # 原始输入（只读归档）
  md/             # 中间态 Markdown（缓存，可 git）
  out/            # 最终产物
  .cache/         # 内容寻址缓存（sha256）
  convert.sh      # 单文件转换封装
  Makefile        # 批量转换 + 依赖
```

缓存策略：以「输入 sha256 + 转换器版本」为缓存键，命中直接复用，避免重复跑 OCR/LLM。

```bash
KEY=$(sha256sum "$SRC" | cut -d' ' -f1)-$(markitdown --version)
CACHE_FILE=".cache/$KEY.md"
if [ -f "$CACHE_FILE" ]; then cp "$CACHE_FILE" "md/$NAME.md"
else markitdown "$SRC" > "$CACHE_FILE" && cp "$CACHE_FILE" "md/$NAME.md"; fi
pandoc "md/$NAME.md" -o "out/$NAME.pdf" --pdf-engine=xelatex -V CJKmainfont="Noto Sans CJK SC"
```

---

## 二、Agent 操作日志系统（记录成果与过程，供复盘）

**核心思路**：**JSONL（每行一条结构化事件）为主、Markdown run-log 为辅**。

### 2.1 结构化日志格式（JSONL）

每个 agent 会话一个 `.jsonl`，每行一条不可变事件，含 `event_type` 区分事件种类：

```jsonl
{"ts":"2026-01-15T10:12:33Z","session_id":"s_abc123","event_type":"run_start","model":"gpt-4o","input_prompt_sha":"p_x9f2"}
{"ts":"2026-01-15T10:12:40Z","session_id":"s_abc123","event_type":"tool_call","tool":"bash","skill":null,"dur_ms":1820,"status":"ok"}
{"ts":"2026-01-15T10:12:41Z","session_id":"s_abc123","event_type":"tool_result","tool":"bash","output_file":"out/报告.md","bytes":18420}
{"ts":"2026-01-15T10:12:45Z","session_id":"s_abc123","event_type":"run_end","status":"success","dur_ms":12300,"cost_usd":0.0042,"tokens":{"in":3100,"out":950}}
{"ts":"2026-01-15T10:12:45Z","session_id":"s_abc123","event_type":"error","message":"pandoc: xelatex not found","retry":true}
```

### 2.2 字段清单

| 类别 | 字段 |
|---|---|
| 标识 | `session_id`、`run_id`、`agent_id`、`parent_session_id` |
| 时间 | `ts`（ISO8601 UTC）、`dur_ms` |
| 输入 | `input_prompt` + `input_prompt_sha`、`rewritten_prompt_sha` |
| 工具/技能 | `tool`、`skill`、`args_sha`、`status`（ok/fail/retry） |
| 产出 | `output_file`、`artifact_sha`、`bytes` |
| 错误 | `error`、`stack`、`retry` |
| 模型/成本 | `model`、`tokens.in/out`、`cost_usd`、`provider` |
| 元信息 | `git_commit`、`env` |

要点：敏感参数（API key、正文）存哈希或引用路径；日志按天/会话落盘 `logs/<date>/<session_id>.jsonl`。

### 2.3 复盘与演进出 skills

1. 聚合脚本从 JSONL 抽「失败率最高工具」「平均耗时最长步骤」「重复 error」。
   ```bash
   cat logs/2026-01-15/*.jsonl | jq -r 'select(.event_type=="error") | .message' | sort | uniq -c | sort -rn
   ```
2. 每周跑「失败 TopN + 耗时 TopN + 抽样 review」，共性坑写成 checklist。
3. 把「可复用、已验证」操作序列沉淀为 skill 文件（Markdown 指令 + 脚本）。
4. 记录 `skill_used` 与 `skill_effectiveness_rating`，用数据反哺 skill 去留。

### 2.4 现成方案

| 方案 | 定位 | URL |
|---|---|---|
| **Langfuse**（推荐，开源自托管） | LLM/agent 全链路 tracing、成本、评估 | [langfuse.com](https://langfuse.com) · [github.com/langfuse/langfuse](https://github.com/langfuse/langfuse) |
| **LangSmith** | LangChain 官方观测平台（SaaS） | [docs.smith.langchain.com](https://docs.smith.langchain.com) |
| **OpenTelemetry + GenAI 语义约定** | 厂商中立标准化 trace/metrics | [opentelemetry.io GenAI SemConv](https://opentelemetry.io/docs/specs/semconv/gen-ai/) |
| **轻量 JSONL + 脚本聚合**（自建） | 无外部依赖，完全可控 | 见 2.1–2.3 |

---

## 三、提示词重写润色工作流（先结构化，再执行）

**核心思路**：每次 agent 交互前，把口语化需求用「meta-prompt」重写成结构化提示词文档（Markdown，纳入 git），再执行；原始需求与重写稿分开存。

### 3.1 五段式模板

```markdown
# 任务标题
## 角色（Role）      ：你是一名 X 专家，面向 Y 受众
## 目标（Goal）      ：一句话可验收的最终产物
## 约束（Constraints）：语言/格式/禁止事项/边界
## 输出格式（Output） ：明确结构（JSON schema / Markdown 层级 / 文件路径）
## 验收标准（Acceptance）：可客观判断的通过条件（含数值、示例）
```

### 3.2 meta-prompt 要点

- 保留原始意图，不臆造；不确定处列「待确认问题」。
- 拆解模糊词（「弄好一点」→ 具体量化指标）。
- 补默认约束（语言、输出路径、验收标准）。
- 输出为五段式 Markdown。

现成参考：Anthropic [metaprompt / Prompt Generator](https://docs.anthropic.com/en/docs/build-with-claude/prompt-engineering/prompt-generator)、[Prompt Improver](https://claude.com/blog/prompt-improver)。

### 3.3 存放与版本管理约定

```
prompts/
  00_inbox/            # 口语化原始需求
  01_rewritten/        # 重写后结构化提示词（纳入 git）
  02_templates/        # 可复用模板
  CHANGELOG.md         # 记录每次重写为何改哪段
```

要点：原始需求与重写稿分目录，`git commit` 记录「谁在何时把什么口语需求改成了什么提示词」；提示词变更走 review；头部加元数据（`version/author/date/target_model/linked_log_session`）。

### 3.4 最佳实践权威来源

- [Anthropic Prompt Engineering 总览](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/overview)
- [Anthropic 结构化输出](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/structured-outputs)
- [OpenAI Structured Outputs](https://platform.openai.com/docs/guides/structured-outputs)
- [OpenAI Prompt Engineering](https://platform.openai.com/docs/guides/prompt-engineering)

---

## 最推荐落地组合

1. **互转**：`markitdown`（任意格式→MD）+ `pandoc`（MD→docx/PDF）+ `ocrmypdf`（扫描件加文本层），脚本以 `sha256+版本` 做缓存固化 pipeline。
2. **复杂扫描件→结构化 MD**：需要保表格时加 `zerox`（视觉模型）。
3. **日志**：自建 **JSONL** + `jq/Python` 聚合复盘，规模上来再迁 **Langfuse** 自托管。
4. **提示词**：用 Anthropic 官方 meta-prompt 要点写重写脚本，产出五段式 Markdown 存入 `prompts/` 纳入 git。
5. **闭环**：提示词文档 → agent 执行 → JSONL 日志 → 复盘沉淀为可复用 skill，skill 内固化转换 pipeline。

**关键 URL**：pandoc.org/MANUAL.html · github.com/microsoft/markitdown · github.com/ocrmypdf/OCRmyPDF · github.com/getomni-ai/zerox · langfuse.com · opentelemetry.io/docs/specs/semconv/gen-ai · platform.claude.com/docs/en/build-with-claude/prompt-engineering/overview
