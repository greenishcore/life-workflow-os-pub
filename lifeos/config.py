"""lifeos.config — 全局配置（UI 无关）

配置优先级：环境变量 > 用户配置文件(~/.config/lifeos/config.json) > 仓库默认值。
GUI 与 CLI 共用同一份配置，保证「命令行改的、界面里看到的」是同一个 vault。
"""
from __future__ import annotations

import json
import os
from dataclasses import dataclass, asdict, field, fields
from pathlib import Path

# 仓库根目录 = 本文件的上两级（lifeos/config.py → lifeos/ → repo/）
REPO_ROOT = Path(__file__).resolve().parent.parent

# 个人数据根目录。**默认在仓库之外**，这一点是有意的：
# 仓库装的是代码，vault / 日志 / 提示词装的是你的私人内容。两者放一起，
# 「clone 下来试用」就会变成「把私人笔记提交进 git 仓库」。
LIFEOS_HOME = Path(os.environ.get("LIFEOS_HOME", Path.home() / "LifeWorkflowOS")).expanduser()

# 仓库自带的种子内容，首次运行复制到 LIFEOS_HOME，之后两边互不相干。
#   seed/vault、seed/skills、seed/prompts  骨架与模板 —— 缺了就补
#   seed/examples                          示例笔记   —— 只在 vault 还没有笔记时放一次
SEED_ROOT = REPO_ROOT / "seed"

def _config_home() -> Path:
    """配置目录：优先 `~/.config/lifeos`（与 Swift 版共用同一份），拿不到时退回
    `~/Library/Application Support/LifeWorkflowOS`。

    为什么要这个退路：`~/.config` 有可能不属于当前用户——某些工具用 sudo 安装时
    会以 root 建出这个目录（实测遇到过 `~/.config/fish` 把整个 `~/.config` 变成
    root:staff）。此时写配置会抛 PermissionError，「设置」页的保存就整个坏掉，
    而用户往往不知道为什么。Swift 版本来就有这条退路，这里对齐。
    """
    preferred = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "lifeos"
    try:
        preferred.mkdir(parents=True, exist_ok=True)
        # 目录存在不代表能写（root 建的目录对普通用户是 r-x）
        probe = preferred / ".write-probe"
        probe.touch()
        probe.unlink()
        return preferred
    except OSError:
        fallback = Path.home() / "Library/Application Support/LifeWorkflowOS"
        try:
            fallback.mkdir(parents=True, exist_ok=True)
        except OSError:
            return preferred   # 两处都不行就让原来的错误照常抛出，别静默吞掉
        return fallback


def config_file() -> Path:
    """配置文件路径。**每次现算**，不缓存成模块常量。

    原因有二：一是 `XDG_CONFIG_HOME` 在导入之后才设也要生效；
    二是模块常量会让单元测试读到用户的真实配置——`test_env_overrides_and_recomputes`
    就因此挂过：它调 `Config.load()`，读到了开发机上真实存在的 config.json。
    """
    return _config_home() / "config.json"


# 兼容既有引用（如设置页展示路径）。新代码请用 config_file()。
CONFIG_HOME = _config_home()
CONFIG_FILE = config_file()


@dataclass
class Config:
    """所有路径与偏好的唯一来源。"""

    vault_dir: str = str(LIFEOS_HOME / "vault")
    logs_dir: str = str(LIFEOS_HOME / "logs")
    prompts_dir: str = str(LIFEOS_HOME / "prompts")
    cache_dir: str = str(LIFEOS_HOME / ".cache")
    scripts_dir: str = str(REPO_ROOT / "scripts")   # 代码，跟着仓库走
    skills_dir: str = str(LIFEOS_HOME / "skills")

    # 格式转换 pipeline 的落点
    convert_raw_dir: str = ""
    convert_md_dir: str = ""
    convert_out_dir: str = ""

    # 提示词重写用的 LLM（OpenAI 兼容接口；留空则只生成脚手架）
    openai_base_url: str = "https://api.openai.com/v1"
    openai_model: str = "gpt-4o-mini"

    theme: str = "light"          # light | dark
    default_calendar: str = "个人"
    default_reminder_list: str = "提醒事项"

    # 不落盘的运行期字段
    _source: str = field(default="default", repr=False, compare=False)
    # 配置文件里我们不认识的键（Swift 版的 roots / logsPath 等）。
    # 原样带着，保存时写回去——否则命令行存一次就会把应用端的复合 vault 配置抹掉。
    _foreign: dict = field(default_factory=dict, repr=False, compare=False)

    # ---------- 派生路径 ----------
    def __post_init__(self) -> None:
        attach = Path(self.vault_dir).expanduser() / "Attachments"
        self.convert_raw_dir = self.convert_raw_dir or str(attach / "_raw")
        self.convert_md_dir = self.convert_md_dir or str(attach / "_md")
        self.convert_out_dir = self.convert_out_dir or str(attach / "_out")

    @property
    def vault(self) -> Path:
        return Path(self.vault_dir).expanduser()

    @property
    def logs(self) -> Path:
        return Path(self.logs_dir).expanduser()

    @property
    def prompts(self) -> Path:
        return Path(self.prompts_dir).expanduser()

    @property
    def cache(self) -> Path:
        return Path(self.cache_dir).expanduser()

    @property
    def scripts(self) -> Path:
        return Path(self.scripts_dir).expanduser()

    @property
    def skills(self) -> Path:
        return Path(self.skills_dir).expanduser()

    @property
    def run_log_jsonl(self) -> Path:
        return self.logs / "run-log.jsonl"

    @property
    def run_log_md(self) -> Path:
        return self.logs / "run-log.md"

    # ---------- 读写 ----------
    @classmethod
    def load(cls) -> "Config":
        data, source = {}, "default"
        path = config_file()
        if path.is_file():
            try:
                data = json.loads(path.read_text(encoding="utf-8"))
                source = str(path)
            except (OSError, json.JSONDecodeError):
                data = {}
        known = {f.name for f in fields(cls) if not f.name.startswith("_")}
        cfg = cls(**{k: v for k, v in data.items() if k in known})
        cfg._foreign = {k: v for k, v in data.items() if k not in known}

        # 环境变量优先（沿用既有脚本的 VAULT_DIR / LOG_DIR / PROMPT_DIR 等约定）
        env_map = (
            ("VAULT_DIR", "vault_dir"),
            ("LOG_DIR", "logs_dir"),
            ("PROMPT_DIR", "prompts_dir"),
            ("SKILLS_DIR", "skills_dir"),
            ("CONVERT_CACHE_DIR", "cache_dir"),
            ("CONVERT_RAW_DIR", "convert_raw_dir"),
            ("CONVERT_MD_DIR", "convert_md_dir"),
            ("CONVERT_OUT_DIR", "convert_out_dir"),
            ("OPENAI_BASE_URL", "openai_base_url"),
            ("OPENAI_MODEL", "openai_model"),
        )
        from_env = set()
        for env, attr in env_map:
            if os.environ.get(env):
                setattr(cfg, attr, os.environ[env])
                from_env.add(attr)
                source = source if source.endswith("+env") else f"{source}+env"

        # vault 换了位置时，未被显式指定的转换目录要跟着挪，
        # 否则会出现「vault 在 A，转换产物却落在 B」的错位。
        for attr in ("convert_raw_dir", "convert_md_dir", "convert_out_dir"):
            if attr not in from_env and not data.get(attr):
                setattr(cfg, attr, "")
        cfg.__post_init__()
        cfg._source = source
        return cfg

    def save(self) -> Path:
        path = config_file()
        path.parent.mkdir(parents=True, exist_ok=True)   # _config_home 已挑好可写的那个
        data = {k: v for k, v in asdict(self).items() if not k.startswith("_")}
        # 先铺对方的字段，再让自己的覆盖同名项；这样 roots 之类的能原样留住，
        # 而 vault_dir 这类双方都写的，以本次改动为准
        merged = dict(self._foreign)
        # Swift 用 roots 表达 vault；这边改了 vault_dir 就要让 roots 跟上，
        # 否则应用端读 roots 会看到旧路径
        if "roots" in merged:
            merged["roots"] = [{"id": "local", "path": self.vault_dir, "folders": [],
                                "needsCoordination": False, "displayName": "本地"}]
        merged.update(data)
        data = merged
        path.write_text(
            json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
        )
        return path

    def ensure_dirs(self) -> None:
        for p in (self.vault, self.logs, self.prompts, self.cache, self.skills):
            p.mkdir(parents=True, exist_ok=True)
        for sub in ("Inbox", "Daily", "Projects", "Areas", "Resources", "Archive", "Dashboard"):
            (self.vault / sub).mkdir(parents=True, exist_ok=True)
        for sub in ("00_inbox", "01_rewritten", "02_templates"):
            (self.prompts / sub).mkdir(parents=True, exist_ok=True)

    # ---------- 首次运行播种 ----------
    def seed_once(self) -> None:
        """把仓库自带的模板 / 内置 skills / 提示词模板补进个人数据目录。

        **只在目标文件不存在时复制，从不覆盖**：升级仓库不会动你改过的模板，
        误删了某个模板则会在下次启动时自动补回来。

        示例笔记走另一条规则（见 `_has_notes`）——只在 vault 里还一条笔记都没有时
        放一次。否则你删掉示例之后，每次启动它们又会冒出来。

        刻意**不放在 `ensure_dirs()` 里**：那个方法的职责是建目录，
        往用户的 vault 里写内容是另一回事，混在一起会让测试和脚本意外多出文件。
        """
        for sub, target in (("vault", self.vault), ("skills", self.skills),
                            ("prompts", self.prompts)):
            _copy_missing(SEED_ROOT / sub, target)
        if not self._has_notes():
            _copy_missing(SEED_ROOT / "examples", self.vault)

    def _has_notes(self) -> bool:
        """vault 里有没有真正的笔记（模板与目录说明不算）。"""
        return any(
            p for p in self.vault.rglob("*.md")
            if "Templates" not in p.parts and p.name != "README.md"
        )


def _copy_missing(src: Path, target: Path) -> None:
    """把 src 下的文件补到 target，已存在的一律跳过。"""
    if not src.is_dir():
        return
    for item in sorted(src.rglob("*")):
        if item.is_dir() or item.name == ".gitkeep":
            continue
        dst = target / item.relative_to(src)
        if dst.exists():
            continue
        dst.parent.mkdir(parents=True, exist_ok=True)
        dst.write_bytes(item.read_bytes())


_cached: Config | None = None


def get_config(reload: bool = False) -> Config:
    global _cached
    if _cached is None or reload:
        _cached = Config.load()
    return _cached


def set_config(cfg: Config) -> Config:
    global _cached
    _cached = cfg
    return cfg
