"""lifeos.services.proc — 子进程执行的统一封装

所有外部工具（pandoc / markitdown / git / gh / osascript）都经由这里调用，
好处是超时、编码、错误信息、日志回调只需在一个地方处理正确。
"""
from __future__ import annotations

import shutil
import subprocess
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Sequence

Logger = Callable[[str], None]


@dataclass
class Result:
    code: int
    out: str
    err: str

    @property
    def ok(self) -> bool:
        return self.code == 0

    @property
    def text(self) -> str:
        return (self.out + ("\n" + self.err if self.err.strip() else "")).strip()


def which(name: str) -> str | None:
    return shutil.which(name)


def have(name: str) -> bool:
    return which(name) is not None


def run(
    cmd: Sequence[str],
    cwd: str | Path | None = None,
    timeout: int = 300,
    log: Logger | None = None,
    env: dict | None = None,
    stdin: str | None = None,
) -> Result:
    """执行命令并返回结果；不抛异常（除内部错误），由调用方判断 ok。"""
    if log:
        log(f"$ {' '.join(str(c) for c in cmd)}")
    try:
        proc = subprocess.run(
            [str(c) for c in cmd],
            cwd=str(cwd) if cwd else None,
            capture_output=True,
            text=True,
            timeout=timeout,
            input=stdin,
            env=env,
        )
    except FileNotFoundError:
        msg = f"找不到命令：{cmd[0]}"
        if log:
            log("❌ " + msg)
        return Result(127, "", msg)
    except subprocess.TimeoutExpired:
        msg = f"命令超时（{timeout}s）：{cmd[0]}"
        if log:
            log("❌ " + msg)
        return Result(124, "", msg)

    res = Result(proc.returncode, proc.stdout or "", proc.stderr or "")
    if log:
        for line in res.text.splitlines():
            if line.strip():
                log(line)
    return res
