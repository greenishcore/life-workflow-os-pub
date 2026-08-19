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

CONFIG_HOME = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "lifeos"
CONFIG_FILE = CONFIG_HOME / "config.json"


@dataclass
class Config:
    """所有路径与偏好的唯一来源。"""

    vault_dir: str = str(REPO_ROOT / "vault")
    logs_dir: str = str(REPO_ROOT / "logs")
    prompts_dir: str = str(REPO_ROOT / "prompts")
    cache_dir: str = str(REPO_ROOT / ".cache")
    scripts_dir: str = str(REPO_ROOT / "scripts")
    skills_dir: str = str(REPO_ROOT / "skills")

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
    def run_log_jsonl(self) -> Path:
        return self.logs / "run-log.jsonl"

    @property
    def run_log_md(self) -> Path:
        return self.logs / "run-log.md"

    # ---------- 读写 ----------
    @classmethod
    def load(cls) -> "Config":
        data, source = {}, "default"
        if CONFIG_FILE.is_file():
            try:
                data = json.loads(CONFIG_FILE.read_text(encoding="utf-8"))
                source = str(CONFIG_FILE)
            except (OSError, json.JSONDecodeError):
                data = {}
        known = {f.name for f in fields(cls) if not f.name.startswith("_")}
        cfg = cls(**{k: v for k, v in data.items() if k in known})

        # 环境变量优先（沿用既有脚本的 VAULT_DIR / LOG_DIR / PROMPT_DIR 等约定）
        env_map = (
            ("VAULT_DIR", "vault_dir"),
            ("LOG_DIR", "logs_dir"),
            ("PROMPT_DIR", "prompts_dir"),
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
        CONFIG_HOME.mkdir(parents=True, exist_ok=True)
        data = {k: v for k, v in asdict(self).items() if not k.startswith("_")}
        CONFIG_FILE.write_text(
            json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
        )
        return CONFIG_FILE

    def ensure_dirs(self) -> None:
        for p in (self.vault, self.logs, self.prompts, self.cache):
            p.mkdir(parents=True, exist_ok=True)
        for sub in ("Inbox", "Daily", "Projects", "Areas", "Resources", "Archive", "Dashboard"):
            (self.vault / sub).mkdir(parents=True, exist_ok=True)
        for sub in ("00_inbox", "01_rewritten", "02_templates"):
            (self.prompts / sub).mkdir(parents=True, exist_ok=True)


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
