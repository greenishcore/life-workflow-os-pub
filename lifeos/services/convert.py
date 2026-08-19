"""lifeos.services.convert — 格式互转 pipeline（算力经济层）

统一路径：任意格式 → Markdown（中间态，带缓存）→ 目标格式。
缓存键 = sha256(输入文件) + 转换器版本，命中即复用，省掉重复的 OCR / 模型调用。
（等价于 scripts/convert.sh，但可被 GUI 直接调用并回报进度。）
"""
from __future__ import annotations

import hashlib
import os
import shutil
from dataclasses import dataclass
from pathlib import Path

from ..config import Config, get_config
from .proc import Logger, have, run, which

TARGETS = ["md", "pdf", "docx", "html"]
CHROME_CANDIDATES = [
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
    "/Applications/Chromium.app/Contents/MacOS/Chromium",
    "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge",
]


@dataclass
class ConvertResult:
    ok: bool
    output: Path | None
    markdown: Path | None
    cached: bool
    message: str


def chrome_bin() -> str | None:
    return next((p for p in CHROME_CANDIDATES if os.access(p, os.X_OK)), None)


def md_tool() -> str | None:
    """选择「任意 → Markdown」的转换器。"""
    if have("markitdown"):
        return "markitdown"
    if have("pandoc"):
        return "pandoc"
    return None


def tool_status() -> dict[str, tuple[bool, str]]:
    """依赖体检：GUI 设置页据此显示每个工具装没装。"""
    out: dict[str, tuple[bool, str]] = {}
    for name, desc in [
        ("markitdown", "任意格式 → Markdown（推荐）"),
        ("pandoc", "Markdown ↔ docx/html/pdf 的主力"),
        ("xelatex", "生成中文 PDF（basictex）"),
        ("ocrmypdf", "扫描件 OCR"),
        ("tesseract", "OCR 引擎"),
        ("git", "版本归档"),
        ("gh", "GitHub release"),
    ]:
        p = which(name)
        out[name] = (p is not None, p or desc)
    c = chrome_bin()
    out["chrome"] = (c is not None, c or "PDF 备用渲染引擎")
    return out


def _converter_version(tool: str | None) -> str:
    if tool == "markitdown":
        r = run(["markitdown", "--version"], timeout=20)
        return "markitdown-" + (r.out.strip().splitlines() or ["0"])[0]
    if tool == "pandoc":
        r = run(["pandoc", "--version"], timeout=20)
        return "pandoc-" + (r.out.strip().splitlines() or ["0"])[0]
    return "none"


def _sha256(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def to_markdown(src: Path, config: Config | None = None, log: Logger | None = None
                ) -> tuple[Path | None, bool, str]:
    """第 1 步：任意 → Markdown（命中缓存则秒回）。返回 (md路径, 是否命中缓存, 说明)。"""
    cfg = config or get_config()
    src = Path(src).expanduser().resolve()
    if not src.is_file():
        return None, False, f"文件不存在：{src}"

    md_dir = Path(cfg.convert_md_dir)
    cache_dir = cfg.cache
    md_dir.mkdir(parents=True, exist_ok=True)
    cache_dir.mkdir(parents=True, exist_ok=True)

    if src.suffix.lower() in (".md", ".markdown"):
        if log:
            log("[is-md] 输入已是 Markdown，跳过转换")
        return src, True, "输入已是 Markdown"

    tool = md_tool()
    if tool is None:
        return None, False, "需要 markitdown 或 pandoc（brew install pandoc / pipx install markitdown）"

    key = f"{_sha256(src)}-{_converter_version(tool)}"
    cache_file = cache_dir / f"{key}.md"
    md_file = md_dir / f"{src.stem}.md"

    if cache_file.is_file() and cache_file.stat().st_size > 0:
        if log:
            log(f"[cache-hit] {src.name}（跳过重复计算）")
        shutil.copyfile(cache_file, md_file)
        return md_file, True, "命中缓存"

    if log:
        log(f"[to-md] {tool} {src.name}")
    tmp = cache_dir / f".tmp-{key[:12]}.md"
    if tool == "markitdown":
        res = run(["markitdown", str(src)], timeout=600)
        if res.ok and res.out.strip():
            tmp.write_text(res.out, encoding="utf-8")
    else:
        ext = src.suffix.lstrip(".").lower()
        res = run(
            ["pandoc", str(src), "-f", ext, "-t", "gfm",
             "--extract-media", str(md_dir / "media"), "-o", str(tmp)],
            timeout=600, log=log,
        )

    if not tmp.is_file() or tmp.stat().st_size == 0:
        tmp.unlink(missing_ok=True)
        return None, False, f"转换失败或结果为空：{src.name}\n{res.err.strip()}"

    os.replace(tmp, cache_file)          # 原子入缓存
    shutil.copyfile(cache_file, md_file)
    return md_file, False, "转换完成"


def convert(
    src: str | Path,
    to: str = "pdf",
    out: str | Path | None = None,
    config: Config | None = None,
    log: Logger | None = None,
) -> ConvertResult:
    """完整 pipeline：任意 → Markdown（缓存）→ 目标格式。"""
    cfg = config or get_config()
    src = Path(src).expanduser()
    to = (to or "pdf").lower().lstrip(".")
    if to not in TARGETS:
        return ConvertResult(False, None, None, False, f"不支持的目标格式：{to}（支持 {'/'.join(TARGETS)}）")

    md_file, cached, msg = to_markdown(src, cfg, log)
    if md_file is None:
        return ConvertResult(False, None, None, cached, msg)
    if log:
        log(f"  → 中间态：{md_file}")

    out_dir = Path(cfg.convert_out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    if to == "md":
        target = Path(out) if out else md_file
        if target != md_file:
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(md_file, target)
        return ConvertResult(True, target, md_file, cached, "完成（Markdown 中间态）")

    target = Path(out) if out else out_dir / f"{src.stem}.{to}"
    target.parent.mkdir(parents=True, exist_ok=True)

    if to == "pdf":
        if have("xelatex") and have("pandoc"):
            if log:
                log("[to-pdf] pandoc + xelatex")
            res = run(["pandoc", str(md_file), "-o", str(target), "--pdf-engine=xelatex",
                       "-V", "CJKmainfont=PingFang SC", "-V", "geometry:margin=2cm"],
                      timeout=900, log=log)
        elif (cb := chrome_bin()) and have("pandoc"):
            if log:
                log("[to-pdf] Chrome headless")
            tmp_html = target.with_suffix(".tmp.html")
            r1 = run(["pandoc", str(md_file), "-f", "gfm", "-t", "html",
                      "--standalone", "-o", str(tmp_html)], timeout=300, log=log)
            if not r1.ok:
                return ConvertResult(False, None, md_file, cached, "生成中间 HTML 失败")
            res = run([cb, "--headless=new", "--disable-gpu", "--no-pdf-header-footer",
                       f"--print-to-pdf={target}", tmp_html.as_uri()], timeout=300, log=log)
            tmp_html.unlink(missing_ok=True)
        else:
            return ConvertResult(False, None, md_file, cached,
                                 "生成 PDF 需要 pandoc + xelatex（brew install --cask basictex）或 Chrome")
    elif to == "docx":
        if not have("pandoc"):
            return ConvertResult(False, None, md_file, cached, "生成 docx 需要 pandoc")
        res = run(["pandoc", str(md_file), "-o", str(target), "-f", "gfm", "-t", "docx"],
                  timeout=300, log=log)
    else:  # html
        if not have("pandoc"):
            return ConvertResult(False, None, md_file, cached, "生成 html 需要 pandoc")
        res = run(["pandoc", str(md_file), "-o", str(target), "-f", "gfm",
                   "-t", "html", "--standalone"], timeout=300, log=log)

    if not res.ok or not target.exists():
        return ConvertResult(False, None, md_file, cached, f"生成 {to} 失败：{res.err.strip() or res.out.strip()}")
    return ConvertResult(True, target, md_file, cached, f"完成 → {target}")


def cache_stats(config: Config | None = None) -> tuple[int, int]:
    """返回 (缓存条目数, 总字节数)。"""
    cfg = config or get_config()
    if not cfg.cache.is_dir():
        return 0, 0
    files = [p for p in cfg.cache.glob("*.md") if p.is_file()]
    return len(files), sum(p.stat().st_size for p in files)


def clear_cache(config: Config | None = None) -> int:
    cfg = config or get_config()
    n = 0
    for p in cfg.cache.glob("*.md"):
        p.unlink(missing_ok=True)
        n += 1
    return n
