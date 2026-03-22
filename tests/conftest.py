"""Pytest 配置 — 设置 PYTHONPATH 和共享 fixtures。"""

import sys
from pathlib import Path

root = Path(__file__).parent.parent
extra_paths = [
    root / "backend",
    root / "kernel" / "src",
    root,
]
for path in reversed(extra_paths):
    if str(path) not in sys.path:
        sys.path.insert(0, str(path))
