"""lifeos.repository — vault 读写（唯一事实源的访问层）

GUI、CLI、脚本都只经由这里碰文件，保证：
  · 扫描规则一致（跳过 .obsidian/Templates/Attachments 等）
  · 写入走「先写临时文件再原子替换」，中途崩溃不会留下半截笔记
  · 保存时才更新 updated，避免只读浏览也污染 git diff
"""
from __future__ import annotations

import datetime as _dt
import os
import re
import shutil
from pathlib import Path

from .config import Config, get_config
from .models import Item, ItemType, Status, today

SKIP_DIRS = {
    ".obsidian", ".trash", ".git", "Templates", "Attachments",
    "Dashboard", "node_modules", "__pycache__", ".cache",
}

# 新建记录的默认落点
FOLDER_FOR_TYPE = {
    ItemType.IDEA: "Inbox",
    ItemType.TASK: "Projects",
    ItemType.DAILY: "Daily",
    ItemType.NOTE: "Resources",
}

_UNSAFE_FILENAME = re.compile(r'[/\\:*?"<>|\n\r\t]')


def safe_filename(name: str, fallback: str = "未命名") -> str:
    name = _UNSAFE_FILENAME.sub("-", (name or "").strip()).strip(" .")
    name = re.sub(r"-{2,}", "-", name)
    return (name or fallback)[:80]


class VaultRepository:
    """vault 的内存索引 + 落盘操作。"""

    def __init__(self, config: Config | None = None) -> None:
        self.config = config or get_config()
        self._items: list[Item] = []
        self._loaded = False

    # ---------------- 读 ----------------
    @property
    def vault(self) -> Path:
        return self.config.vault

    def iter_markdown(self):
        root = self.vault
        if not root.is_dir():
            return
        for dirpath, dirnames, filenames in os.walk(root):
            dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS and not d.startswith(".")]
            for fn in sorted(filenames):
                if fn.endswith(".md"):
                    yield Path(dirpath) / fn

    def load(self, force: bool = False) -> list[Item]:
        """扫描 vault，返回全部可视化记录（按创建时间升序）。"""
        if self._loaded and not force:
            return self._items
        items: list[Item] = []
        for path in self.iter_markdown():
            try:
                text = path.read_text(encoding="utf-8")
            except (OSError, UnicodeDecodeError):
                continue
            item = Item.from_text(text, path)
            if item is not None:
                items.append(item)
        items.sort(key=lambda i: (i.created, i.title))
        self._items, self._loaded = items, True
        return items

    @property
    def items(self) -> list[Item]:
        return self.load()

    def reload(self) -> list[Item]:
        return self.load(force=True)

    def get(self, item_id: str) -> Item | None:
        return next((i for i in self.items if i.id == item_id), None)

    def by_path(self, path: Path) -> Item | None:
        p = Path(path)
        return next((i for i in self.items if i.path == p), None)

    def query(
        self,
        text: str = "",
        statuses: set[Status] | None = None,
        types: set[ItemType] | None = None,
        tags: set[str] | None = None,
    ) -> list[Item]:
        out = []
        for it in self.items:
            if statuses and it.status not in statuses:
                continue
            if types and it.type not in types:
                continue
            if tags and not (tags & set(it.tags)):
                continue
            if not it.matches(text):
                continue
            out.append(it)
        return out

    def all_tags(self) -> list[tuple[str, int]]:
        counts: dict[str, int] = {}
        for it in self.items:
            for t in it.tags:
                counts[t] = counts.get(t, 0) + 1
        return sorted(counts.items(), key=lambda kv: (-kv[1], kv[0]))

    # ---------------- 写 ----------------
    def path_for(self, item: Item) -> Path:
        """决定一条新记录的落点（已有 path 则沿用）。"""
        if item.path is not None:
            return item.path
        folder = self.vault / FOLDER_FOR_TYPE.get(item.type, "Inbox")
        folder.mkdir(parents=True, exist_ok=True)
        base = safe_filename(item.title or item.id or "未命名")
        path = folder / f"{base}.md"
        n = 2
        while path.exists():
            path = folder / f"{base}-{n}.md"
            n += 1
        return path

    def save(self, item: Item, touch: bool = True) -> Path:
        """写回磁盘（原子替换）。touch=True 时刷新 updated。"""
        if touch:
            item.touch()
        if not item.id:
            item.id = Item.new_id()
        path = self.path_for(item)
        path.parent.mkdir(parents=True, exist_ok=True)
        _atomic_write(path, item.to_text())
        item.path = path
        if item not in self._items:
            self._items.append(item)
            self._items.sort(key=lambda i: (i.created, i.title))
        return path

    def create(
        self,
        title: str,
        type: ItemType = ItemType.IDEA,
        status: Status = Status.SEED,
        body: str = "",
        **kwargs,
    ) -> Item:
        item = Item(title=title, type=type, status=status, body=body,
                    id=Item.new_id(), created=today(), **kwargs)
        if not item.body.strip():
            item.body = f"# {title}\n\n"
        self.save(item)
        return item

    def rename(self, item: Item, new_title: str) -> Path:
        """改标题并同步重命名文件（保持文件名与标题一致，便于 Obsidian 链接）。"""
        old = item.path
        item.title = new_title
        if old is not None and old.exists():
            target = old.parent / f"{safe_filename(new_title)}.md"
            if target != old and not target.exists():
                item.path = None
                item.path = target
                _atomic_write(target, item.to_text())
                old.unlink()
                return target
        return self.save(item)

    def delete(self, item: Item, to_trash: bool = True) -> Path | None:
        """删除：默认移入 vault/.trash/（可恢复），而不是真删。"""
        if item in self._items:
            self._items.remove(item)
        if item.path is None or not item.path.exists():
            return None
        if not to_trash:
            item.path.unlink()
            return None
        trash = self.vault / ".trash" / _dt.date.today().strftime("%Y-%m-%d")
        trash.mkdir(parents=True, exist_ok=True)
        target = trash / item.path.name
        n = 2
        while target.exists():
            target = trash / f"{item.path.stem}-{n}{item.path.suffix}"
            n += 1
        shutil.move(str(item.path), str(target))
        return target

    def archive(self, item: Item) -> Path:
        """归档：状态置 archived 并移入 Archive/。"""
        item.status = Status.ARCHIVED
        dest_dir = self.vault / "Archive"
        dest_dir.mkdir(parents=True, exist_ok=True)
        old = item.path
        target = dest_dir / (old.name if old else f"{safe_filename(item.title)}.md")
        n = 2
        while target.exists() and target != old:
            target = dest_dir / f"{Path(target).stem}-{n}.md"
            n += 1
        item.touch()
        _atomic_write(target, item.to_text())
        if old and old.exists() and old != target:
            old.unlink()
        item.path = target
        return target

    # ---------------- 捕捉 ----------------
    def capture(self, text: str, when: _dt.datetime | None = None) -> Path:
        """快速捕获：追加一条待办到 Inbox/当日.md（对齐 scripts/capture.sh 的行为）。"""
        text = (text or "").strip()
        if not text:
            raise ValueError("捕获内容为空")
        now = when or _dt.datetime.now()
        target = self.vault / "Inbox" / f"{now.strftime('%Y-%m-%d')}.md"
        target.parent.mkdir(parents=True, exist_ok=True)
        line = f"- [ ] {now.strftime('%H:%M')} {text}\n"
        with open(target, "a", encoding="utf-8") as f:
            if target.stat().st_size == 0:
                f.write(f"# 收件箱 {now.strftime('%Y-%m-%d')}\n\n")
            f.write(line)
        return target

    def read_capture_log(self, days: int = 14) -> list[tuple[str, list[str]]]:
        """读取最近 N 天的 Inbox 捕获记录，供 GUI 展示。"""
        out: list[tuple[str, list[str]]] = []
        inbox = self.vault / "Inbox"
        if not inbox.is_dir():
            return out
        files = sorted(
            (p for p in inbox.glob("*.md") if re.fullmatch(r"\d{4}-\d{2}-\d{2}", p.stem)),
            key=lambda p: p.stem, reverse=True,
        )[:days]
        for p in files:
            try:
                lines = [
                    ln.strip() for ln in p.read_text(encoding="utf-8").splitlines()
                    if ln.strip().startswith("- ")
                ]
            except OSError:
                continue
            if lines:
                out.append((p.stem, lines))
        return out

    def toggle_capture_line(self, date: str, raw_line: str) -> bool:
        """勾选/取消勾选 Inbox 中的某一条捕获。返回是否成功。"""
        path = self.vault / "Inbox" / f"{date}.md"
        if not path.is_file():
            return False
        text = path.read_text(encoding="utf-8")
        lines = text.splitlines()
        for i, ln in enumerate(lines):
            if ln.strip() == raw_line.strip():
                if "- [ ]" in ln:
                    lines[i] = ln.replace("- [ ]", "- [x]", 1)
                elif "- [x]" in ln:
                    lines[i] = ln.replace("- [x]", "- [ ]", 1)
                else:
                    return False
                _atomic_write(path, "\n".join(lines) + "\n")
                return True
        return False

    def daily_note(self, date: str | None = None) -> Path:
        d = date or today()
        return self.vault / "Daily" / f"{d}.md"

    def upsert_section(self, path: Path, heading: str, content: str) -> Path:
        """把 content 写入 path 的 `## heading` 段（有则替换，无则追加）。

        对齐 reminders2obsidian.sh / calendar2md.sh 的写法，但收敛到一处实现。
        """
        path.parent.mkdir(parents=True, exist_ok=True)
        existing = path.read_text(encoding="utf-8") if path.is_file() else ""
        block = f"## {heading}\n\n{content.strip()}\n"
        pattern = re.compile(rf"^## {re.escape(heading)}\s*\n.*?(?=^## |\Z)", re.S | re.M)
        if pattern.search(existing):
            new = pattern.sub(block + "\n", existing)
        else:
            sep = "" if not existing or existing.endswith("\n\n") else ("\n" if existing.endswith("\n") else "\n\n")
            new = existing + sep + block
        _atomic_write(path, new)
        return path


def _atomic_write(path: Path, text: str) -> None:
    """先写临时文件再 os.replace：避免写一半崩溃导致笔记损坏。"""
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(text, encoding="utf-8")
    os.replace(tmp, path)
