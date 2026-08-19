"""lifeos.cli — 统一命令行入口

GUI 和命令行共用 lifeos 这一套核心逻辑，不再各写一份。
  python3 -m lifeos            启动图形界面
  python3 -m lifeos.cli --help 查看全部子命令
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

from .config import get_config
from .models import RunLog
from .repository import VaultRepository


def _cmd_gui(args) -> int:
    from .gui.app import main as gui_main
    return gui_main([sys.argv[0]])


def _cmd_capture(args) -> int:
    cfg = get_config()
    text = " ".join(args.text).strip()
    if not text and not sys.stdin.isatty():
        text = sys.stdin.read().strip()
    if not text:
        import subprocess
        text = subprocess.run(["pbpaste"], capture_output=True, text=True).stdout.strip()
    if not text:
        print("无输入内容（参数/stdin/剪贴板均为空）", file=sys.stderr)
        return 1
    path = VaultRepository(cfg).capture(text)
    print(f"已捕获 → {path}")
    return 0


def _cmd_convert(args) -> int:
    from .services import convert as convert_svc
    res = convert_svc.convert(args.input, to=args.to, out=args.out,
                              config=get_config(), log=lambda s: print(s))
    print(("[done] " if res.ok else "❌ ") + res.message)
    return 0 if res.ok else 2


def _cmd_dashboard(args) -> int:
    from .html_dashboard import write_dashboard
    cfg = get_config()
    if args.vault:
        cfg.vault_dir = args.vault
    items = VaultRepository(cfg).load()
    out = write_dashboard(items, args.out, cfg)
    print(f"[dashboard] 共 {len(items)} 条记录 → {out}")
    return 0


def _cmd_log(args) -> int:
    from .services import runlog as runlog_svc
    def split(s):
        return [x.strip() for x in (s or "").split(",") if x.strip()]
    if args.json:
        import json
        rec = RunLog.from_dict(json.loads(args.json))
    else:
        rec = RunLog(
            objective=args.objective or "", agent=args.agent,
            input_prompt_ref=args.input_prompt_ref or "",
            tools_used=split(args.tools), process_summary=args.process_summary or "",
            outputs=split(args.outputs), status=args.status, errors=split(args.errors),
            duration_seconds=args.duration, model=args.model or "", notes=args.notes or "",
        )
    if not rec.objective:
        print("缺少 objective（--objective 或 --json）", file=sys.stderr)
        return 1
    cfg = get_config()
    rec = runlog_svc.append(rec, cfg)
    print(f"[logged] {rec.run_id} → {cfg.run_log_jsonl} / {cfg.run_log_md}")
    return 0


def _cmd_prompt(args) -> int:
    from .services import prompts as prompt_svc
    raw = " ".join(args.request).strip()
    if not raw and not sys.stdin.isatty():
        raw = sys.stdin.read().strip()
    if not raw:
        print("无输入需求（参数或 stdin）", file=sys.stderr)
        return 1
    try:
        doc = prompt_svc.rewrite(raw, use_llm=args.llm, config=get_config())
    except (RuntimeError, ValueError) as exc:
        print(f"❌ {exc}", file=sys.stderr)
        return 1
    print(f"[{doc.mode}] 原始需求 → {doc.raw_path}")
    print(f"[{doc.mode}] 重写结果 → {doc.out_path}")
    if doc.mode == "scaffold":
        print("提示：脚手架已生成，补齐各段即可；或加 --llm 让模型自动重写。")
    return 0


def _cmd_review(args) -> int:
    from .services import review as review_svc
    cfg = get_config()
    st = review_svc.aggregate(args.since, cfg)
    if st.total == 0:
        print(f"无日志（{st.since} 之后，{cfg.run_log_jsonl}）", file=sys.stderr)
        return 0
    if args.out:
        path = review_svc.write_report(st, args.out, cfg)
        print(f"[weekly-review] 已写入 {path}")
    else:
        print(review_svc.render_markdown(st))
    return 0


def _cmd_sync(args) -> int:
    from .services import archive as archive_svc
    ok, msg = archive_svc.sync(args.message, push=not args.no_push,
                               config=get_config(), log=lambda s: print(s))
    print(("✅ " if ok else "❌ ") + msg)
    return 0 if ok else 1


def _cmd_release(args) -> int:
    from .services import archive as archive_svc
    ok, msg = archive_svc.release(args.version, args.notes,
                                  config=get_config(), log=lambda s: print(s))
    print(("✅ " if ok else "❌ ") + msg)
    return 0 if ok else 1


def _cmd_doctor(args) -> int:
    """依赖与配置体检。"""
    from .services import convert as convert_svc
    cfg = get_config()
    print(f"配置来源: {cfg._source}")
    for name, path in [("vault", cfg.vault), ("logs", cfg.logs),
                       ("prompts", cfg.prompts), ("cache", cfg.cache)]:
        print(f"  {'✅' if Path(path).exists() else '⬜'} {name:8} {path}")
    print("\n外部工具:")
    for name, (ok, info) in convert_svc.tool_status().items():
        print(f"  {'✅' if ok else '⬜'} {name:12} {info}")
    try:
        n = len(VaultRepository(cfg).load())
        print(f"\n扫描到 {n} 条记录")
    except Exception as exc:
        print(f"\n❌ 扫描 vault 失败: {exc}")
        return 1
    return 0


def build_parser() -> argparse.ArgumentParser:
    ap = argparse.ArgumentParser(
        prog="lifeos", description="Life Workflow OS —— 生活工作流的捕捉/整理/执行/复盘/归档"
    )
    sub = ap.add_subparsers(dest="cmd")

    p = sub.add_parser("gui", help="启动图形界面（默认）")
    p.set_defaults(func=_cmd_gui)

    p = sub.add_parser("capture", help="快速捕获到 Inbox")
    p.add_argument("text", nargs="*")
    p.set_defaults(func=_cmd_capture)

    p = sub.add_parser("convert", help="格式转换：任意 → Markdown → 目标格式")
    p.add_argument("input")
    p.add_argument("--to", default="pdf", choices=["md", "pdf", "docx", "html"])
    p.add_argument("-o", "--out")
    p.set_defaults(func=_cmd_convert)

    p = sub.add_parser("dashboard", help="生成 HTML 看板（供 CI / 手机查看）")
    p.add_argument("--vault")
    p.add_argument("-o", "--out")
    p.set_defaults(func=_cmd_dashboard)

    p = sub.add_parser("log", help="记录一次 agent 操作")
    p.add_argument("--json")
    p.add_argument("--objective")
    p.add_argument("--agent", default="agent")
    p.add_argument("--input-prompt-ref", dest="input_prompt_ref")
    p.add_argument("--tools")
    p.add_argument("--process-summary", dest="process_summary")
    p.add_argument("--outputs")
    p.add_argument("--status", default="success", choices=["success", "partial", "failed"])
    p.add_argument("--errors")
    p.add_argument("--duration", type=float, default=0.0)
    p.add_argument("--model")
    p.add_argument("--notes")
    p.set_defaults(func=_cmd_log)

    p = sub.add_parser("prompt", help="把口语需求重写为五段式提示词")
    p.add_argument("request", nargs="*")
    p.add_argument("--llm", action="store_true")
    p.set_defaults(func=_cmd_prompt)

    p = sub.add_parser("review", help="从 run-log 生成周复盘")
    from .services.review import default_since
    p.add_argument("--since", default=default_since())
    p.add_argument("--out")
    p.set_defaults(func=_cmd_review)

    p = sub.add_parser("sync", help="git 提交并推送")
    p.add_argument("-m", "--message", default="")
    p.add_argument("--no-push", action="store_true")
    p.set_defaults(func=_cmd_sync)

    p = sub.add_parser("release", help="打里程碑 tag 并发布")
    p.add_argument("version")
    p.add_argument("notes", nargs="?", default="")
    p.set_defaults(func=_cmd_release)

    p = sub.add_parser("doctor", help="配置与依赖体检")
    p.set_defaults(func=_cmd_doctor)
    return ap


def main(argv: list[str] | None = None) -> int:
    ap = build_parser()
    args = ap.parse_args(argv)
    if not getattr(args, "func", None):
        return _cmd_gui(args)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
