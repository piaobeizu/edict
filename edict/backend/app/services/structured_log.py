"""结构化日志服务 — JSON 格式日志 + trace_id 贯穿全链路。

所有日志统一格式：
{
    "time": "2026-03-13T10:00:00Z",
    "level": "INFO",
    "logger": "edict.orchestrator",
    "task_id": "JJC-20260313-001",
    "trace_id": "JJC-20260313-001",
    "stage": "dispatch",
    "error_code": null,
    "message": "Dispatching task to agent taizi",
    "extra": {}
}

用法：
    from ..services.structured_log import get_logger, set_trace_context

    log = get_logger("edict.orchestrator")
    set_trace_context(task_id="JJC-001", stage="dispatch")
    log.info("Dispatching task", agent="taizi")
"""

import contextvars
import json
import logging
import sys
import time
from datetime import datetime, timezone

# Context variables for trace propagation
_trace_task_id: contextvars.ContextVar[str] = contextvars.ContextVar("trace_task_id", default="")
_trace_stage: contextvars.ContextVar[str] = contextvars.ContextVar("trace_stage", default="")
_trace_id: contextvars.ContextVar[str] = contextvars.ContextVar("trace_id", default="")
_trace_error_code: contextvars.ContextVar[str] = contextvars.ContextVar("trace_error_code", default="")
_trace_request_id: contextvars.ContextVar[str] = contextvars.ContextVar("trace_request_id", default="")
_trace_start: contextvars.ContextVar[float] = contextvars.ContextVar("trace_start", default=0.0)


def trace_duration_ms() -> float:
    """Return milliseconds since trace context was set."""
    start = _trace_start.get(0.0)
    if not start:
        return 0.0
    return round((time.monotonic() - start) * 1000, 2)


def set_trace_context(
    task_id: str = "",
    stage: str = "",
    trace_id: str = "",
    request_id: str = "",
    error_code: str = "",
):
    """设置当前协程的 trace 上下文。trace_id 默认等于 task_id。"""
    if task_id:
        _trace_task_id.set(task_id)
    if stage:
        _trace_stage.set(stage)
    _trace_id.set(trace_id or task_id or _trace_id.get(""))
    _trace_request_id.set(request_id or _trace_request_id.get(""))
    _trace_error_code.set(error_code or _trace_error_code.get(""))
    _trace_start.set(time.monotonic())


def clear_trace_context():
    """清除 trace 上下文。"""
    _trace_task_id.set("")
    _trace_stage.set("")
    _trace_id.set("")
    _trace_request_id.set("")
    _trace_error_code.set("")
    _trace_start.set(0.0)


class JsonFormatter(logging.Formatter):
    """JSON 格式化器 — 输出结构化日志。"""

    def format(self, record: logging.LogRecord) -> str:
        log_entry = {
            "time": datetime.now(timezone.utc).isoformat(),
            "level": record.levelname,
            "logger": record.name,
            "task_id": _trace_task_id.get(""),
            "trace_id": _trace_id.get(""),
            "request_id": _trace_request_id.get(""),
            "stage": _trace_stage.get(""),
            "error_code": _trace_error_code.get("") or getattr(record, "error_code", None),
            "duration_ms": trace_duration_ms(),
            "message": record.getMessage(),
        }

        # Merge any extra fields passed via log.info("msg", extra={...})
        extra_fields = getattr(record, "extra_fields", None)
        if extra_fields is not None:
            log_entry["extra"] = extra_fields
        else:
            log_entry["extra"] = {}

        # Include exception info if present
        if record.exc_info and record.exc_info[0]:
            log_entry["exception"] = self.formatException(record.exc_info)

        return json.dumps(log_entry, ensure_ascii=False, default=str)


class StructuredLoggerAdapter(logging.LoggerAdapter):
    """Logger adapter that accepts keyword arguments as structured fields."""

    def process(self, msg, kwargs):
        # Extract extra structured fields from kwargs
        extra = kwargs.get("extra", {})
        # Pull out any non-standard kwargs and put them in extra_fields
        extra_fields = {}
        for key in list(kwargs.keys()):
            if key not in ("exc_info", "stack_info", "stacklevel", "extra"):
                extra_fields[key] = kwargs.pop(key)
        if extra_fields:
            extra["extra_fields"] = extra_fields
        kwargs["extra"] = extra
        return msg, kwargs


def setup_structured_logging(level: int = logging.INFO):
    """配置全局结构化日志。替换默认的 basicConfig。"""
    root = logging.getLogger()
    root.setLevel(level)

    # Remove existing handlers
    for handler in root.handlers[:]:
        root.removeHandler(handler)

    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(JsonFormatter())
    root.addHandler(handler)


def get_logger(name: str) -> StructuredLoggerAdapter:
    """获取结构化 logger。"""
    logger = logging.getLogger(name)
    return StructuredLoggerAdapter(logger, {})
