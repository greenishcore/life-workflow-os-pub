#!/usr/bin/env python3
"""weekly_review.py — 从 run-log.jsonl 聚合生成周复盘报告

用法:
  python3 weekly_review.py                 # 统计全部日志
  python3 weekly_review.py --since 2026-08-11   # 只统计该日期之后
  python3 weekly_review.py --out vault/Daily/周复盘.md

输出 Markdown：总览、成功率、错误 TopN、工具 TopN、耗时、近期产出、待沉淀建议。
"""
import argparse, json, os, sys
from collections import Counter
from datetime import datetime, timedelta, timezone

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LOGS = os.environ.get("LOG_DIR", os.path.join(ROOT, "logs"))
JSONL = os.path.join(LOGS, "run-log.jsonl")


def load(since=None):
    if not os.path.isfile(JSONL):
        return []
    recs = []
    with open(JSONL, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                rec = json.loads(line)
            except Exception:
                continue
            ts = rec.get("timestamp", "")
            if since and ts[:10] < since:
                continue
            recs.append(rec)
    return recs


def main():
    default_since = (datetime.now() - timedelta(days=7)).strftime("%Y-%m-%d")
    ap = argparse.ArgumentParser(description="从 run-log 生成周复盘")
    ap.add_argument("--since", default=default_since)
    ap.add_argument("--out")
    args = ap.parse_args()

    recs = load(args.since)
    total = len(recs)
    if total == 0:
        print(f"无日志（{args.since} 之后，{JSONL}）", file=sys.stderr)
        sys.exit(0)

    status = Counter(r.get("status", "?") for r in recs)
    tools = Counter()
    errors = Counter()
    outputs = []
    dur = 0.0
    for r in recs:
        for t in r.get("tools_used") or []:
            tools[t] += 1
        for e in r.get("errors") or []:
            errors[e] += 1
        outputs += (r.get("outputs") or [])
        dur += float(r.get("duration_seconds") or 0)

    ok = status.get("success", 0)
    rate = (ok / total * 100) if total else 0

    lines = []
    lines.append(f"# 周复盘 {args.since} 起")
    lines.append("")
    lines.append(f"> 自动生成于 {datetime.now().strftime('%Y-%m-%d %H:%M')}，数据源 `logs/run-log.jsonl`")
    lines.append("")
    lines.append("## 总览")
    lines.append(f"- 运行次数：{total}")
    lines.append(f"- 成功率：{rate:.0f}%（成功 {ok} / 失败 {status.get('failed',0) + status.get('partial',0)}）")
    lines.append(f"- 总耗时：{dur:.0f} 秒")
    lines.append(f"- 状态分布：{dict(status)}")
    lines.append("")
    lines.append("## 工具使用 TopN")
    for t, c in tools.most_common(10):
        lines.append(f"- {t}: {c}")
    lines.append("")
    lines.append("## 错误 TopN（可沉淀为 checklist / skill）")
    if errors:
        for e, c in errors.most_common(10):
            lines.append(f"- [{c}次] {e}")
    else:
        lines.append("- （无）")
    lines.append("")
    lines.append("## 近期产出")
    seen = set()
    for o in outputs[-30:]:
        if o not in seen:
            lines.append(f"- `{o}`")
            seen.add(o)
    lines.append("")
    lines.append("## 复盘结论与待沉淀")
    lines.append("- [ ] 把高频错误写成 checklist / 修正脚本")
    lines.append("- [ ] 把可复用的成功操作沉淀为 `skills/` 下的 skill")
    lines.append("- [ ] 更新提示词库 `prompts/` 的模板")
    lines.append("")
    report = "\n".join(lines)

    if args.out:
        os.makedirs(os.path.dirname(args.out), exist_ok=True)
        with open(args.out, "w", encoding="utf-8") as f:
            f.write(report)
        print(f"[weekly-review] 已写入 {args.out}")
    else:
        print(report)


if __name__ == "__main__":
    main()
