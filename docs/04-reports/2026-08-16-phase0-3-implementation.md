# 实施记录：Phase 0–3 落地

> 日期：2026-08-16
> 对应路线图：`docs/03-roadmap/roadmap.md` 的 Phase 0–3
> 仓库：本仓库（main 分支）

## 完成情况

| Phase | 内容 | 状态 | 产物 |
|-------|------|------|------|
| 0 基础设施 | git 初始化、PARA 目录、模板、.gitignore、GitHub 私有仓库 | ✅ | `vault/`、`templates/`、`.gitignore`、远程 origin |
| 1 捕捉层 | Apple 便签/提醒/日历 → Markdown 脚本 + 快速捕获 | ✅ 脚本就绪（首次运行需授权自动化权限） | `scripts/capture.sh`、`reminders2obsidian.*`、`calendar2md.*`、`notes2obsidian.sh` |
| 2 知识库 | Obsidian vault 结构 + 插件配置说明 + 模板落地 | ✅ | `SETUP.md`、`vault/Templates/` |
| 3 转换层 | 格式互转 pipeline + sha256 缓存 | ✅ 脚本就绪 | `scripts/convert.sh`、`scripts/Makefile` |
| 附加 | agent JSONL 日志 + 提示词重写 + Actions 归档 | ✅ | `scripts/log_run.py`、`scripts/rewrite_prompt.py`、`prompts/02_templates/meta-prompt.md`、`.github/workflows/vault-backup.yml`、`scripts/launchd/*.plist` |

## 验证

- Shell 脚本：`bash -n` 全部通过。
- AppleScript：`osacompile` 编译通过（修复了 `line` 保留字与 `≥` 运算符问题）。
- Python：`py_compile` 通过；`log_run.py`、`rewrite_prompt.py`、`capture.sh` 冒烟测试通过。
- 依赖已安装：pandoc 3.10.2、markitdown 0.1.7（含 pdf/docx/pptx/xlsx/xls extras）、ocrmypdf 17.10.0、tesseract 5.5.3、fswatch 1.22.0、icalBuddy 1.10.1。
- 格式互转端到端验证通过：`md→html`、`md→docx`、`md→pdf`（Chrome headless 回退，因未装 xelatex）、`docx→md`、`pdf→md`，且 `sha256+版本` 缓存二次命中、`--to md -o` 正确落盘。
- 修复：`convert.sh` 缓存原子性（临时文件+mv，失败不留空缓存）、Markdown 输入直通、`--to md` 输出拷贝。

## 待用户操作（需要授权/交互）

1. Obsidian 指向 `vault/`（此前打开的是项目根目录，已把 `.obsidian/` 移入 `vault/`，请关闭后重新「打开文件夹作为库」选 `vault/`）。
2. 首次运行 `reminders2obsidian.sh` / `calendar2md.sh` 时，在「系统设置 → 隐私与安全性 → 自动化」允许终端控制「提醒事项 / 日历」。
3. 装好 markitdown 后首次跑 `notes2obsidian.sh` 导出 Apple Notes。
4. Obsidian Git / Remindian 的插件内授权（见 `SETUP.md`）。

## 下一步（Phase 5 可视化看板）

按 `docs/03-roadmap/roadmap.md` 进入 Phase 5：frontmatter 统一字段 + Kanban/Dataview/Heatmap/Timeline 组合看板，以及可选本地 HTML 看板（gray-matter → ECharts）。
