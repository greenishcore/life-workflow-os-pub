#!/usr/bin/env bash
# genfixtures.sh — 用 Python 版重新生成交叉验证夹具
#
# 什么时候要跑：改动了 Python 版的 models/frontmatter，或往 seed/examples 里加了新的示例笔记。
# 生成的夹具入库，Swift 测试直接比对，因此 CI 上跑测试**不需要**装 Python。
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$ROOT"
exec python3 - <<'PY'
import json, pathlib
from lifeos.models import Item

repo = pathlib.Path(".")
out = repo / "apple/LifeWorkflowKit/Tests/Fixtures"
out.mkdir(parents=True, exist_ok=True)
for stale in out.glob("*"):
    stale.unlink()

manifest = []
for p in sorted((repo / "seed" / "examples").rglob("*.md")):
    if any(part in {".obsidian", "Templates", "Dashboard", "Attachments", ".trash"} for part in p.parts):
        continue
    item = Item.from_text(p.read_text(encoding="utf-8"), p)
    if item is None:
        continue
    rel = p.relative_to(repo / "seed" / "examples").as_posix()
    key = rel.replace("/", "__")
    (out / f"{key}.expected.md").write_text(item.to_text(), encoding="utf-8")
    (out / f"{key}.model.json").write_text(json.dumps({
        "title": item.title, "type": item.type.value, "id": item.id,
        "created": item.created, "updated": item.updated,
        "status": item.status.value, "priority": item.priority.value,
        "energy": item.energy, "progress": item.progress, "tags": item.tags,
        "thinking_notes": [{"t": n.t, "note": n.note} for n in item.thinking_notes],
        "next_actions": item.next_actions, "links": item.links,
        "last_activity": item.last_activity, "body": item.body.strip(),
    }, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    manifest.append({"source": rel, "key": key})

(out / "manifest.json").write_text(
    json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(f"✅ 生成 {len(manifest)} 组交叉验证夹具 → {out}")
for m in manifest:
    print("   ", m["source"])
PY
