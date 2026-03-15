"""Pytest 配置 — 设置 PYTHONPATH 和共享 fixtures。"""

import sys
from pathlib import Path

# 确保 edict 包可导入
root = Path(__file__).parent.parent
if str(root) not in sys.path:
    sys.path.insert(0, str(root))
