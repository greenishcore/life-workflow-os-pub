"""lifeos.gui.worker — 后台任务

凡是可能卡住的操作（格式转换、git push、AppleScript、调 LLM）都丢到线程里跑，
界面永远不冻结。日志通过信号回主线程，不在子线程碰任何 Qt 控件。
"""
from __future__ import annotations

import traceback
from typing import Any, Callable

from PyQt5.QtCore import QObject, QThread, pyqtSignal


class Task(QObject):
    """在子线程执行 fn(log=...)，把日志与结果发回主线程。"""

    log = pyqtSignal(str)
    done = pyqtSignal(bool, object, str)   # (成功, 返回值, 错误信息)

    def __init__(self, fn: Callable[..., Any], *args, pass_log: bool = True, **kwargs):
        super().__init__()
        self._fn, self._args, self._kwargs = fn, args, kwargs
        self._pass_log = pass_log

    def run(self) -> None:
        try:
            if self._pass_log:
                self._kwargs.setdefault("log", self.log.emit)
            result = self._fn(*self._args, **self._kwargs)
            self.done.emit(True, result, "")
        except Exception as exc:                     # noqa: BLE001 — 后台任何异常都要显示给用户
            self.log.emit(f"❌ {exc}")
            self.done.emit(False, None, f"{exc}\n{traceback.format_exc(limit=3)}")


class TaskRunner(QObject):
    """管理一个任务线程的生命周期，避免线程被 GC 提前回收。"""

    def __init__(self, parent=None):
        super().__init__(parent)
        self._thread: QThread | None = None
        self._task: Task | None = None

    @property
    def busy(self) -> bool:
        return self._thread is not None and self._thread.isRunning()

    def start(
        self,
        fn: Callable[..., Any],
        *args,
        on_log: Callable[[str], None] | None = None,
        on_done: Callable[[bool, Any, str], None] | None = None,
        pass_log: bool = True,
        **kwargs,
    ) -> bool:
        if self.busy:
            if on_log:
                on_log("⚠️ 上一个任务还在执行，请稍候")
            return False

        thread = QThread()
        task = Task(fn, *args, pass_log=pass_log, **kwargs)
        task.moveToThread(thread)
        thread.started.connect(task.run)
        if on_log:
            task.log.connect(on_log)
        if on_done:
            task.done.connect(on_done)
        task.done.connect(lambda *_: thread.quit())
        thread.finished.connect(self._cleanup)
        self._thread, self._task = thread, task
        thread.start()
        return True

    def _cleanup(self) -> None:
        if self._thread is not None:
            self._thread.deleteLater()
        if self._task is not None:
            self._task.deleteLater()
        self._thread = self._task = None

    def wait(self, ms: int = 5000) -> None:
        if self._thread is not None:
            self._thread.quit()
            self._thread.wait(ms)
