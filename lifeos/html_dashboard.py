"""lifeos.html_dashboard — 生成自包含的 HTML 看板

用途：GitHub Actions 自动生成、手机/其它设备上查看。桌面端请直接用 GUI。

相比重构前的版本：
  · 图表改为**服务端生成的内联 SVG**，不再依赖 ECharts CDN —— 离线可看、
    不受网络与第三方可用性影响；
  · 输出严格确定性（不含时间戳），CI 重复生成不会产生噪音提交。
"""
from __future__ import annotations

import datetime as _dt
import html
from pathlib import Path

from .config import Config, get_config
from .models import Item, Status
from . import stats

HEAT_COLORS = ["#eef0f4", "#c7d7f7", "#8fb3ef", "#5b8ae6", "#2f63cf"]


def _esc(s) -> str:
    return html.escape(str(s), quote=True)


def _heatmap_svg(heat: dict[str, int], weeks: int = 40) -> str:
    if not heat:
        return '<p class="muted">暂无数据</p>'
    end = _dt.date.today()
    end += _dt.timedelta(days=(6 - end.weekday()))
    start = end - _dt.timedelta(days=weeks * 7 - 1)
    vmax = max(heat.values())
    cell, gap = 11, 3
    step = cell + gap
    w, h = weeks * step + 30, 7 * step + 22

    parts = [f'<svg viewBox="0 0 {w} {h}" width="100%" role="img" aria-label="活跃热力图">']
    last_month, last_label = None, -99
    for wi in range(weeks):
        for di in range(7):
            day = start + _dt.timedelta(days=wi * 7 + di)
            if day > _dt.date.today():
                continue
            key = day.strftime("%Y-%m-%d")
            v = heat.get(key, 0)
            idx = 0 if v <= 0 else 1 + min(3, int((v - 1) / max(1, vmax) * 4))
            parts.append(
                f'<rect x="{30 + wi * step}" y="{18 + di * step}" width="{cell}" height="{cell}" '
                f'rx="2" fill="{HEAT_COLORS[idx]}"><title>{key}：{v} 次活动</title></rect>'
            )
        first = start + _dt.timedelta(days=wi * 7)
        if first.month != last_month and wi - last_label >= 3:
            last_month, last_label = first.month, wi
            parts.append(
                f'<text x="{30 + wi * step}" y="12" class="ax">{first.month}月</text>'
            )
    for i, lab in enumerate(["一", "", "三", "", "五", "", "日"]):
        if lab:
            parts.append(f'<text x="20" y="{18 + i * step + 9}" class="ax" text-anchor="end">{lab}</text>')
    parts.append("</svg>")
    return "".join(parts)


def _timeline_svg(items: list[Item]) -> str:
    """融合时间轴：X=时间 Y=精力 点径=优先级 颜色=状态 横线=思维轨迹。"""
    pts = [i for i in items if i.created]
    if not pts:
        return '<p class="muted">暂无数据</p>'
    dates = [_d(i.created) for i in pts]
    for i in pts:
        dates += [_d(n.t) for n in i.thinking_notes if _d(n.t)]
    dates = [d for d in dates if d]
    lo, hi = min(dates), max(dates)
    if lo == hi:
        lo -= _dt.timedelta(days=1)
        hi += _dt.timedelta(days=1)
    span = max(1, (hi - lo).days)

    W, H, L, R, T, B = 900, 300, 40, 20, 16, 30
    def x(d): return L + (W - L - R) * ((d - lo).days / span)
    def y(e): return T + (H - T - B) * (1 - (min(10, max(0, e or 0)) / 10))

    parts = [f'<svg viewBox="0 0 {W} {H}" width="100%" role="img" aria-label="融合时间轴">']
    for v in (0, 2, 4, 6, 8, 10):
        parts.append(f'<line x1="{L}" y1="{y(v):.1f}" x2="{W - R}" y2="{y(v):.1f}" class="grid"/>')
        parts.append(f'<text x="{L - 8}" y="{y(v) + 4:.1f}" class="ax" text-anchor="end">{v}</text>')
    for i in range(6):
        day = lo + _dt.timedelta(days=round(span * i / 5))
        parts.append(
            f'<text x="{x(day):.1f}" y="{H - 8}" class="ax" text-anchor="middle">'
            f'{day.strftime("%m-%d")}</text>'
        )
    for it in pts:
        start = _d(it.created)
        note_days = sorted({d for n in it.thinking_notes if (d := _d(n.t))})
        span_days = note_days + [start]
        begin, end = min(span_days), max(span_days)
        yy = y(it.energy)
        if end > begin:
            parts.append(
                f'<line x1="{x(begin):.1f}" y1="{yy:.1f}" x2="{x(end):.1f}" y2="{yy:.1f}" '
                f'stroke="{it.status.color}" stroke-width="2" stroke-opacity=".38" stroke-linecap="round"/>'
            )
            for d in note_days:
                if d != start:
                    parts.append(
                        f'<line x1="{x(d):.1f}" y1="{yy - 4:.1f}" x2="{x(d):.1f}" y2="{yy + 4:.1f}" '
                        f'stroke="{it.status.color}" stroke-width="2" stroke-opacity=".75"/>'
                    )
        r = it.priority.weight / 2.6
        parts.append(
            f'<circle cx="{x(start):.1f}" cy="{yy:.1f}" r="{r:.1f}" fill="{it.status.color}" '
            f'fill-opacity=".85" stroke="#fff" stroke-width="2">'
            f'<title>{_esc(it.title)}\n{it.created} · {it.status.label} · '
            f'{it.priority.label}优先级 · 精力 {it.energy if it.energy is not None else "—"} · '
            f'思路注释 {len(it.thinking_notes)} 条</title></circle>'
        )
    parts.append("</svg>")
    return "".join(parts)


def _status_svg(counts: dict[Status, int]) -> str:
    total = sum(counts.values())
    if not total:
        return '<p class="muted">暂无数据</p>'
    W, H, B = 900, 190, 26
    n = len(counts)
    slot = W / n
    vmax = max(counts.values()) or 1
    parts = [f'<svg viewBox="0 0 {W} {H}" width="100%" role="img" aria-label="状态分布">']
    for i, (st, c) in enumerate(counts.items()):
        bh = (c / vmax) * (H - B - 24)
        cx = slot * (i + 0.5)
        parts.append(
            f'<rect x="{cx - 26:.1f}" y="{H - B - bh:.1f}" width="52" height="{bh:.1f}" rx="4" '
            f'fill="{st.color}"><title>{st.label}：{c}</title></rect>'
        )
        parts.append(f'<text x="{cx:.1f}" y="{H - B - bh - 6:.1f}" class="val" text-anchor="middle">{c}</text>')
        parts.append(f'<text x="{cx:.1f}" y="{H - 8}" class="ax" text-anchor="middle">{st.label}</text>')
    parts.append("</svg>")
    return "".join(parts)


def render(items: list[Item]) -> str:
    s = stats.summarize(items)
    rows = []
    for it in sorted(items, key=lambda i: i.last_activity, reverse=True):
        notes = "".join(
            f'<div class="tn"><span class="tn-t">{_esc(n.t)}</span>{_esc(n.note)}</div>'
            for n in it.thinking_notes
        ) or '<span class="muted">（无思路注释）</span>'
        tags = " ".join(f'<span class="tag">#{_esc(t)}</span>' for t in it.tags)
        rows.append(f"""      <tr>
        <td class="nowrap">{_esc(it.created)}</td>
        <td class="nowrap"><span class="dot" style="background:{it.status.color}"></span>{_esc(it.status.label)}</td>
        <td class="t-title">{_esc(it.title)}<div>{tags}</div></td>
        <td class="nowrap">{_esc(it.priority.label)}</td>
        <td class="nowrap">{it.progress if it.progress is not None else ''}</td>
        <td>{notes}</td>
      </tr>""")

    kpis = [
        ("想法总数", s.total, f"跨度 {s.span_days} 天"),
        ("推进中", s.active, f"平均进度 {s.avg_progress:.0f}%"),
        ("已完成", s.done, f"完成率 {(s.done / s.total * 100 if s.total else 0):.0f}%"),
        ("思路注释", s.total_notes, f"人均 {(s.total_notes / s.total if s.total else 0):.1f} 条"),
    ]
    kpi_html = "".join(
        f'<div class="kpi"><div class="kpi-v">{v}</div><div class="kpi-l">{_esc(l)}</div>'
        f'<div class="kpi-d">{_esc(d)}</div></div>' for l, v, d in kpis
    )
    legend = "".join(
        f'<span class="lg"><i style="background:{st.color}"></i>{st.label}</span>'
        for st in Status.ordered()
    )

    return f"""<!DOCTYPE html>
<html lang="zh">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>生活工作流 · 融合时间看板</title>
<style>
  :root {{ --bg:#f4f5f7; --card:#fff; --text:#1f2430; --muted:#6b7280; --faint:#9ca3af;
           --border:#e4e7ec; --accent:#4f46e5; }}
  @media (prefers-color-scheme: dark) {{
    :root {{ --bg:#14161b; --card:#1c2028; --text:#e6e9ef; --muted:#9aa3b2; --faint:#6b7280;
             --border:#2a2f3a; --accent:#818cf8; }}
  }}
  * {{ box-sizing: border-box; }}
  body {{ font-family:-apple-system,"PingFang SC","Helvetica Neue",sans-serif; margin:0;
         background:var(--bg); color:var(--text); }}
  header {{ padding:20px 24px; border-bottom:1px solid var(--border); background:var(--card); }}
  h1 {{ margin:0 0 4px; font-size:19px; }}
  .sub {{ color:var(--muted); font-size:13px; }}
  .wrap {{ padding:16px 20px; max-width:1180px; margin:0 auto; }}
  .kpis {{ display:grid; grid-template-columns:repeat(auto-fit,minmax(150px,1fr)); gap:12px; margin-bottom:14px; }}
  .kpi {{ background:var(--card); border:1px solid var(--border); border-radius:10px; padding:14px 16px; }}
  .kpi-v {{ font-size:26px; font-weight:700; }}
  .kpi-l {{ font-size:12px; color:var(--muted); }}
  .kpi-d {{ font-size:11px; color:var(--faint); }}
  .card {{ background:var(--card); border:1px solid var(--border); border-radius:10px;
           padding:14px 16px; margin-bottom:14px; overflow-x:auto; }}
  .card h2 {{ font-size:13px; margin:0 0 4px; }}
  .card .hint {{ font-size:11px; color:var(--faint); margin-bottom:10px; }}
  .grid {{ stroke:var(--border); stroke-width:1; }}
  .ax {{ fill:var(--faint); font-size:10px; }}
  .val {{ fill:var(--text); font-size:11px; font-weight:600; }}
  .lg {{ font-size:11px; color:var(--muted); margin-right:12px; }}
  .lg i {{ display:inline-block; width:8px; height:8px; border-radius:50%; margin-right:4px; }}
  table {{ width:100%; border-collapse:collapse; font-size:13px; }}
  th,td {{ text-align:left; padding:8px 10px; border-bottom:1px solid var(--border); vertical-align:top; }}
  th {{ color:var(--muted); font-weight:600; font-size:12px; }}
  .nowrap {{ white-space:nowrap; }}
  .dot {{ display:inline-block; width:8px; height:8px; border-radius:50%; margin-right:6px; }}
  .t-title {{ font-weight:600; min-width:150px; }}
  .tag {{ background:rgba(79,70,229,.12); color:var(--accent); border-radius:4px;
          padding:1px 6px; margin-right:4px; font-size:11px; font-weight:400; }}
  .tn {{ margin:2px 0; color:var(--muted); font-size:12px; }}
  .tn-t {{ color:var(--faint); font-size:11px; margin-right:6px; font-family:ui-monospace,monospace; }}
  .muted {{ color:var(--faint); }}
</style>
</head>
<body>
<header>
  <h1>生活工作流 · 融合时间看板</h1>
  <div class="sub">数据源：vault 的 frontmatter · 图表为内联 SVG，离线可看 · 桌面端请用 Life Workflow OS 应用</div>
</header>
<div class="wrap">
  <div class="kpis">{kpi_html}</div>
  <div class="card"><h2>活跃热力图</h2>
    <div class="hint">每格 = 当天新建想法 + 写下的思路注释</div>{_heatmap_svg(stats.activity_heat(items))}</div>
  <div class="card"><h2>融合时间轴</h2>
    <div class="hint">X=时间 · Y=精力 · 点径=优先级 · 颜色=状态 · 横线=思维轨迹</div>
    {_timeline_svg(items)}<div>{legend}</div></div>
  <div class="card"><h2>状态分布</h2>
    <div class="hint">seed → sprout → doing → done → archived</div>{_status_svg(stats.status_counts(items))}</div>
  <div class="card"><h2>想法清单（含思路注释 / 思维轨迹）</h2>
    <table><thead><tr><th>创建</th><th>状态</th><th>标题</th><th>优先级</th><th>进度</th><th>思路注释</th></tr></thead>
    <tbody>
{chr(10).join(rows) if rows else '      <tr><td colspan="6" class="muted">暂无记录</td></tr>'}
    </tbody></table>
  </div>
</div>
</body>
</html>
"""


def write_dashboard(items: list[Item], out: str | Path | None = None,
                    config: Config | None = None) -> Path:
    cfg = config or get_config()
    target = Path(out) if out else cfg.vault / "Dashboard" / "index.html"
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(render(items), encoding="utf-8")
    return target


def _d(s) -> _dt.date | None:
    try:
        return _dt.date.fromisoformat(str(s)[:10])
    except (ValueError, TypeError):
        return None
