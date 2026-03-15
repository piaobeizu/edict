"""kernel — 重导出层，指向独立包 edict-kernel。

原项目中所有 `from kernel.xxx import ...` 的代码无需修改，
此模块会自动代理到 `edict_kernel` 包。

安装: pip install -e ../edict-kernel 或 pip install edict-kernel
"""

# Re-export everything from edict_kernel
from edict_kernel import *  # noqa: F401, F403
from edict_kernel import __version__
