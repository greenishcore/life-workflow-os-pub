#!/usr/bin/env python3
"""dashboard.py — 从 vault 的 frontmatter 生成融合时间的可视化看板（单文件 HTML）

用法:
  python3 dashboard.py                 # 扫描 vault/，生成 vault/Dashboard/index.html
  python3 dashboard.py -o /tmp/d.html  # 指定输出
  python3 dashboard.py --vault ~/obs   # 指定 vault 根

看板内容（ECharts，融合时间/精力/优先级/状态/思路注释）:
  1. 日历热力图   —— 每天产生多少想法
  2. 状态分布     —— seed/sprout/doing/done/archived 计数
  3. 融合散点图   —— X=时间, Y=精力, 大小=优先级, 颜色=状态
  4. 想法表格     —— 含思路注释（思维轨迹）

依赖: PyYAML（解析 frontmatter）；ECharts 走 CDN（查看时需联网，可离线下载后内联）。
"""
import argparse, json, os, re, sys
from datetime import datetime

try:
    import yaml
except ImportError:
    print("需要 PyYAML: pip install pyyaml", file=sys.stderr)
    sys.exit(1)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SKIP_DIRS = {".obsidian", ".trash", "Templates", "Attachments", "Dashboard", "node_modules", ".git"}

STATUS_COLORS = {
    "seed": "#f59e0b", "sprout": "#84cc16", "doing": "#3b82f6",
    "done": "#10b981", "archived": "#9ca3af",
}
STATUS_ORDER = ["seed", "sprout", "doing", "done", "archived"]
PRIORITY_W = {"high": 24, "medium": 16, "low": 10}


def parse_frontmatter(text):
    """返回 (frontmatter_dict, body) 或 (None, text)。"""
    if not text.startswith("---"):
        return None, text
    m = re.match(r"^---\s*\n(.*?)\n---\s*\n?", text, re.S)
    if not m:
        return None, text
    try:
        fm = yaml.safe_load(m.group(1)) or {}
    except Exception:
        return None, text
    return fm, text[m.end():]


def norm_date(v):
    if isinstance(v, datetime):
        return v.strftime("%Y-%m-%d")
    s = str(v).strip()
    m = re.match(r"^(\d{4})-(\d{2})-(\d{2})", s)
    return m.group(0) if m else s[:10]


def collect(vault_dir):
    items = []
    for dirpath, dirnames, filenames in os.walk(vault_dir):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        for fn in filenames:
            if not fn.endswith(".md"):
                continue
            path = os.path.join(dirpath, fn)
            try:
                text = open(path, encoding="utf-8").read()
            except Exception:
                continue
            fm, body = parse_frontmatter(text)
            if not fm:
                continue
            # 只收「想法/任务」或有 status 的记录
            typ = fm.get("type")
            if typ not in ("idea", "task") and "status" not in fm:
                continue
            created = norm_date(fm.get("created") or fm.get("date") or "")
            if not created:
                continue
            title = fm.get("title") or fm.get("id") or os.path.splitext(fn)[0]
            status = fm.get("status") or "seed"
            if status not in STATUS_COLORS:
                status = "seed"
            # 思路注释归一化
            tn = fm.get("thinking_notes") or []
            notes = []
            for entry in tn:
                if isinstance(entry, dict):
                    notes.append({"t": norm_date(entry.get("t") or entry.get("date") or ""),
                                  "note": str(entry.get("note") or "")})
                else:
                    notes.append({"t": created, "note": str(entry)})
            energy = fm.get("energy")
            try:
                energy = int(energy) if energy is not None else None
            except Exception:
                energy = None
            items.append({
                "title": title, "id": str(fm.get("id") or ""), "type": typ,
                "created": created, "status": status,
                "priority": fm.get("priority") or "medium",
                "energy": energy, "progress": fm.get("progress"),
                "tags": fm.get("tags") or [],
                "thinking_notes": notes,
                "file": os.path.relpath(path, vault_dir),
            })
    items.sort(key=lambda x: x["created"])
    return items


def build_html(items):
    # 统计
    by_status = {s: 0 for s in STATUS_ORDER}
    for it in items:
        by_status[it["status"]] = by_status.get(it["status"], 0) + 1

    heat = {}  # date -> count
    for it in items:
        heat[it["created"]] = heat.get(it["created"], 0) + 1

    scatter = []
    for it in items:
        scatter.append({
            "value": [it["created"], it["energy"] if it["energy"] is not None else 0,
                      PRIORITY_W.get(it["priority"], 14)],
            "status": it["status"], "title": it["title"], "priority": it["priority"],
        })

    years = sorted({d[:4] for d in heat} or {str(datetime.now().year)})
    year_range = years[0] if len(years) == 1 else f"{years[0]}-{years[-1]}"

    data = {
        "items": items,
        "heat": [[d, v] for d, v in sorted(heat.items())],
        "heatRange": year_range,
        "status": [{"name": s, "value": by_status[s]} for s in STATUS_ORDER],
        "scatter": scatter,
    }

    rows = []
    for it in reversed(items):
        tn = "".join(
            f'<div class="tn"><span class="tn-t">{n["t"]}</span>{_esc(n["note"])}</div>'
            for n in it["thinking_notes"]
        ) or '<span class="muted">（无思路注释）</span>'
        tags = " ".join(f'<span class="tag">#{t}</span>' for t in it["tags"])
        prog = it["progress"] if it["progress"] is not None else ""
        rows.append(f"""
        <tr>
          <td>{_esc(it['created'])}</td>
          <td><span class="dot" style="background:{STATUS_COLORS[it['status']]}"></span>{_esc(it['status'])}</td>
          <td class="t-title">{_esc(it['title'])}</td>
          <td>{_esc(it['priority'])}</td>
          <td>{prog}</td>
          <td class="tn-cell">{tn}</td>
        </tr>""")

    html = f"""<!DOCTYPE html>
<html lang="zh">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>生活工作流 · 融合时间看板</title>
<script src="https://cdn.jsdelivr.net/npm/echarts@5/dist/echarts.min.js"></script>
<style>
  body {{ font-family: -apple-system, "PingFang SC", sans-serif; margin: 0; background: #f6f7f9; color: #1f2937; }}
  header {{ background: #fff; padding: 18px 28px; border-bottom: 1px solid #e5e7eb; }}
  h1 {{ margin: 0 0 4px; font-size: 20px; }}
  .sub {{ color: #6b7280; font-size: 13px; }}
  .grid {{ display: grid; grid-template-columns: 1fr 1fr; gap: 16px; padding: 16px 20px; }}
  .card {{ background: #fff; border-radius: 10px; padding: 12px; box-shadow: 0 1px 3px rgba(0,0,0,.06); }}
  .card h2 {{ font-size: 14px; margin: 0 0 6px; color: #374151; }}
  .chart {{ width: 100%; height: 260px; }}
  #scatter {{ height: 320px; }}
  table {{ width: 100%; border-collapse: collapse; font-size: 13px; }}
  th, td {{ text-align: left; padding: 8px 10px; border-bottom: 1px solid #eef0f2; vertical-align: top; }}
  th {{ color: #6b7280; font-weight: 600; background: #fafafa; }}
  .dot {{ display: inline-block; width: 9px; height: 9px; border-radius: 50%; margin-right: 6px; }}
  .t-title {{ font-weight: 600; }}
  .tag {{ background: #eef2ff; color: #4f46e5; border-radius: 4px; padding: 1px 6px; margin-right: 4px; font-size: 12px; }}
  .tn-cell {{ max-width: 420px; }}
  .tn {{ margin: 2px 0; color: #4b5563; }}
  .tn-t {{ color: #9ca3af; font-size: 12px; margin-right: 6px; font-family: ui-monospace, monospace; }}
  .muted {{ color: #9ca3af; }}
  .full {{ grid-column: 1 / -1; }}
</style>
</head>
<body>
<header>
  <h1>生活工作流 · 融合时间看板</h1>
  <div class="sub">共 {len(items)} 条想法/任务 · 数据来自 vault 的 frontmatter（输出确定性，可安全纳入版本控制）</div>
</header>
<div class="grid">
  <div class="card"><h2>日历热力图（每日产生想法数）</h2><div id="heat" class="chart"></div></div>
  <div class="card"><h2>状态分布</h2><div id="status" class="chart"></div></div>
  <div class="card full"><h2>融合散点（X=时间 · Y=精力 · 大小=优先级 · 颜色=状态）</h2><div id="scatter" class="chart"></div></div>
  <div class="card full"><h2>想法清单（含思路注释 / 思维轨迹）</h2>
    <table><thead><tr><th>日期</th><th>状态</th><th>标题</th><th>优先级</th><th>进度</th><th>思路注释</th></tr></thead>
    <tbody>{''.join(rows)}</tbody></table>
  </div>
</div>
<script>
const DATA = {json.dumps(data, ensure_ascii=False)};
const STATUS_COLORS = {json.dumps(STATUS_COLORS)};
function mk(id) {{ const c = echarts.init(document.getElementById(id)); window.addEventListener('resize', () => c.resize()); return c; }}
mk('heat').setOption({{
  tooltip: {{ formatter: p => p.value[0] + '：' + p.value[1] + ' 条' }},
  visualMap: {{ min: 0, max: Math.max(1, ...DATA.heat.map(d => d[1])), orient: 'horizontal', left: 'center', bottom: 0 }},
  calendar: {{ range: DATA.heatRange, cellSize: ['auto', 16], top: 30, left: 30, right: 20, itemStyle: {{ color: '#eee' }} }},
  series: [{{ type: 'heatmap', coordinateSystem: 'calendar', data: DATA.heat }}]
}});
mk('status').setOption({{
  tooltip: {{ trigger: 'item' }},
  xAxis: {{ type: 'category', data: DATA.status.map(s => s.name) }},
  yAxis: {{ type: 'value', minInterval: 1 }},
  series: [{{ type: 'bar', barMaxWidth: 40, data: DATA.status.map(s => ({{
    value: s.value, itemStyle: {{ color: STATUS_COLORS[s.name] }}
  }})), label: {{ show: true, position: 'top' }} }}]
}});
mk('scatter').setOption({{
  tooltip: {{ formatter: p => p.data.title + '<br>' + p.value[0] + ' · 精力 ' + p.value[1] + ' · ' + p.data.priority }},
  xAxis: {{ type: 'time', name: '时间' }},
  yAxis: {{ type: 'value', name: '精力', min: 0, max: 10 }},
  series: DATA.status.map(s => ({{
    name: s.name, type: 'scatter', symbolSize: d => d[2],
    data: DATA.scatter.filter(d => d.status === s.name).map(d => d.value),
    itemStyle: {{ color: STATUS_COLORS[s.name], opacity: 0.85 }}
  }})),
  legend: {{ bottom: 0 }}
}});
</script>
</body>
</html>"""
    return html


def _esc(s):
    return str(s).replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def main():
    ap = argparse.ArgumentParser(description="生成融合时间看板")
    ap.add_argument("--vault", default=os.path.join(ROOT, "vault"))
    ap.add_argument("-o", "--out", default=None)
    args = ap.parse_args()

    vault_dir = os.path.abspath(args.vault)
    if not os.path.isdir(vault_dir):
        print(f"vault 不存在: {vault_dir}", file=sys.stderr)
        sys.exit(1)

    items = collect(vault_dir)
    html = build_html(items)
    out = args.out or os.path.join(vault_dir, "Dashboard", "index.html")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(out, "w", encoding="utf-8") as f:
        f.write(html)
    print(f"[dashboard] 共 {len(items)} 条记录 → {out}")


if __name__ == "__main__":
    main()
