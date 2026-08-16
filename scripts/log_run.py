#!/usr/bin/env python3
"""log_run.py — agent 操作日志记录器（JSONL 为主，Markdown run-log 为辅）

用法:
  python3 log_run.py --objective "转换某 PDF" --status success \
      --tools bash,pandoc --outputs out/a.pdf --model deepseek-v4 --duration 12.3

  python3 log_run.py --json '{"objective":"...","status":"failed","errors":["x"]}'

输出:
  logs/run-log.jsonl  追加一行结构化事件（每行含 run_id + 全部字段）
  logs/run-log.md     追加一条可读条目（便于人工浏览）

字段（与 templates/log-entry.md 一致）:
  run_id, timestamp, agent, objective, input_prompt_ref, tools_used,
  process_summary, outputs, status, errors, duration_seconds, model, notes
"""
import argparse, json, os, sys, uuid
from datetime import datetime, timezone

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LOGS = os.environ.get("LOG_DIR", os.path.join(ROOT, "logs"))
JSONL = os.path.join(LOGS, "run-log.jsonl")
MD = os.path.join(LOGS, "run-log.md")


def now():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def main():
    ap = argparse.ArgumentParser(description="记录一次 agent 操作")
    ap.add_argument("--json", help="完整 JSON 字段（优先级最高）")
    ap.add_argument("--objective")
    ap.add_argument("--agent", default=os.environ.get("AGENT_NAME", "agent"))
    ap.add_argument("--input-prompt-ref", dest="input_prompt_ref")
    ap.add_argument("--tools", help="逗号分隔")
    ap.add_argument("--process-summary", dest="process_summary")
    ap.add_argument("--outputs", help="逗号分隔的产出路径")
    ap.add_argument("--status", default="success",
                    choices=["success", "partial", "failed"])
    ap.add_argument("--errors", help="逗号分隔")
    ap.add_argument("--duration", dest="duration_seconds", type=float, default=0.0)
    ap.add_argument("--model")
    ap.add_argument("--notes")
    args = ap.parse_args()

    if args.json:
        rec = json.loads(args.json)
    else:
        rec = {
            "objective": args.objective,
            "agent": args.agent,
            "input_prompt_ref": args.input_prompt_ref,
            "tools_used": [t.strip() for t in (args.tools or "").split(",") if t.strip()],
            "process_summary": args.process_summary,
            "outputs": [o.strip() for o in (args.outputs or "").split(",") if o.strip()],
            "status": args.status,
            "errors": [e.strip() for e in (args.errors or "").split(",") if e.strip()],
            "duration_seconds": args.duration_seconds,
            "model": args.model,
            "notes": args.notes,
        }

    if not rec.get("objective"):
        print("缺少 objective（--objective 或 --json）", file=sys.stderr)
        sys.exit(1)

    rec.setdefault("run_id", uuid.uuid4().hex[:12])
    rec.setdefault("timestamp", now())

    os.makedirs(LOGS, exist_ok=True)
    with open(JSONL, "a", encoding="utf-8") as f:
        f.write(json.dumps(rec, ensure_ascii=False) + "\n")

    # 可读 Markdown 条目
    tools = ", ".join(rec.get("tools_used") or [])
    outs = ", ".join(rec.get("outputs") or [])
    errs = "; ".join(rec.get("errors") or [])
    icon = {"success": "✅", "partial": "🟡", "failed": "❌"}[rec.get("status", "success")]
    line = (f"- {icon} `{rec['run_id']}` {rec['timestamp']} "
            f"**{rec.get('objective')}**")
    if tools:
        line += f" | 工具: {tools}"
    if rec.get("duration_seconds"):
        line += f" | {rec['duration_seconds']}s"
    if outs:
        line += f"\n  - 产出: {outs}"
    if errs:
        line += f"\n  - 错误: {errs}"
    if rec.get("notes"):
        line += f"\n  - 复盘: {rec['notes']}"
    with open(MD, "a", encoding="utf-8") as f:
        f.write(line + "\n")

    print(f"[logged] {rec['run_id']} → {JSONL} / {MD}")


if __name__ == "__main__":
    main()
