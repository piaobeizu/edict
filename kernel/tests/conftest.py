"""Kernel 子项目测试的 PYTHONPATH 引导。"""

import sys
from pathlib import Path

root = Path(__file__).resolve().parent.parent
for path in [root.parent]:
    if str(path) not in sys.path:
        sys.path.insert(0, str(path))
