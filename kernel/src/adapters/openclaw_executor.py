"""OpenClaw CLI AgentExecutor 实现。"""

from __future__ import annotations

import asyncio
import logging
import subprocess
import time
from typing import Any

try:  # installed/package mode
    from ..ports import ExecutionResult
except ImportError:  # source-path test mode
    from ports import ExecutionResult

log = logging.getLogger("adapters.openclaw")


class OpenClawExecutor:
    """实现 kernel.ports.AgentExecutor，通过 OpenClaw CLI 执行 agent。

    调用方式: openclaw agent --agent {agent_id} -m "{message}" --timeout {timeout}
    """

    def __init__(self, openclaw_bin: str = "openclaw", project_dir: str | None = None):
        self.bin = openclaw_bin
        self.project_dir = project_dir

    async def execute(
        self,
        agent_id: str,
        message: str,
        context: dict[str, Any] | None = None,
        timeout: int = 300,
    ) -> ExecutionResult:
        """在线程池中执行 openclaw CLI 调用。"""
        loop = asyncio.get_event_loop()
        return await loop.run_in_executor(
            None, self._execute_sync, agent_id, message, context, timeout
        )

    def _execute_sync(
        self,
        agent_id: str,
        message: str,
        context: dict[str, Any] | None = None,
        timeout: int = 300,
    ) -> ExecutionResult:
        cmd = [self.bin, "agent", "--agent", agent_id, "-m", message, "--timeout", str(timeout)]
        env = None
        if self.project_dir:
            import os
            env = {**os.environ, "OPENCLAW_PROJECT_DIR": self.project_dir}

        start = time.monotonic()
        try:
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=timeout + 30,
                env=env,
            )
            duration = int((time.monotonic() - start) * 1000)
            if result.returncode == 0:
                return ExecutionResult(
                    success=True,
                    output=result.stdout,
                    duration_ms=duration,
                    metadata={"returncode": 0},
                )
            else:
                return ExecutionResult(
                    success=False,
                    output=result.stdout,
                    error=result.stderr,
                    duration_ms=duration,
                    metadata={"returncode": result.returncode},
                )
        except subprocess.TimeoutExpired:
            duration = int((time.monotonic() - start) * 1000)
            return ExecutionResult(
                success=False,
                error=f"Timeout after {timeout}s",
                duration_ms=duration,
                metadata={"timeout": True},
            )
        except FileNotFoundError:
            return ExecutionResult(
                success=False,
                error=f"openclaw binary not found: {self.bin}",
            )
        except Exception as e:
            duration = int((time.monotonic() - start) * 1000)
            return ExecutionResult(
                success=False,
                error=str(e),
                duration_ms=duration,
            )
