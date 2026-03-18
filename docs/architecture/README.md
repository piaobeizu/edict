# architecture 目录

本目录是三省六部 · Edict 的正式架构 SoT。

## 当前文档

- [overview.md](overview.md)：十二部制全景、Agent 体系、状态机、权限矩阵、部署拓扑、核心数据流
- [task-dispatch-architecture.md](task-dispatch-architecture.md)：任务分发流转完整架构（业务层 + 技术层 + 观测层）
- [code-structure.md](code-structure.md)：backend / kernel / frontend 三层代码结构与协作关系

## 规则

- 架构、Agent 体系、状态机、权限矩阵、通信、调度等项目事实只在本目录详写
- 其他目录可引用本目录，但不应复制架构正文
- 设计方案在 `docs/design/` 中演进，落地后才迁入本目录
