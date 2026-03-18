# Edict Agent Rules

## Verification / Debugging Priority

在这个仓库里，后续排查与验证默认遵循下面优先顺序：

1. `read`
2. `grep`
3. `pytest`
4. `pyright`
5. `python -m compileall`
6. `lsp_diagnostics`（仅在必要时）

## LSP Usage Rule

- 默认少依赖 `lsp_diagnostics`
- 优先使用文件读取、文本检索、测试、类型检查、编译检查完成定位和验证
- 只有在需要单文件语义诊断时才调用 `lsp_diagnostics`
- 不要并发调用多个 `lsp_diagnostics`
- 如果 `lsp_diagnostics` 中断或结果异常，不要反复重试，改用 `pytest` / `pyright` / `compileall` / `read` / `grep`

## Execution Rule

- 修改后优先做最小充分验证
- 能单文件验证就不要直接跑全量重型检查
- 如果仓库存在已知工具不稳定现象，优先使用更稳定的替代路径继续推进，不要卡在单一工具上
