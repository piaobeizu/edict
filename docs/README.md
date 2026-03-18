# 三省六部 · Edict 文档入口

## 文档边界

- `docs/`：面向人类的正式文档与 SoT（Source of Truth）
- `AGENTS.md` 与仓库根目录规范：面向 AI 协作的规则入口
- 架构事实只在 `docs/architecture/**` 详写；AI 过程材料如需保留，建议放在 `docs/design/` 或外部协作空间

## 建议阅读顺序

1. [架构总览](architecture/overview.md)
2. [任务分发流转架构](architecture/task-dispatch-architecture.md)
3. [代码结构说明](architecture/code-structure.md)
4. [后端参考](reference/backend-reference.md)
5. [内核参考](reference/kernel-reference.md)
6. [运维手册](operations/README.md)
7. [快速上手指南](guides/getting-started.md)

## 目录说明

### `architecture/`

正式架构 SoT。十二部制 Agent 体系、状态机、任务流转、通信模型、代码分层等项目架构事实的权威来源。

当前已落地：
- [overview.md](architecture/overview.md) — 十二部制全景、Agent 体系、状态机、部署拓扑
- [task-dispatch-architecture.md](architecture/task-dispatch-architecture.md) — 任务分发流转完整架构
- [code-structure.md](architecture/code-structure.md) — backend / kernel / frontend 三层代码结构

### `reference/`

工程参考文档。代码映射、API 端点、配置参考、启动参数等。

当前已落地：
- [backend-reference.md](reference/backend-reference.md) — 后端进程、API 清单、配置、启动命令
- [kernel-reference.md](reference/kernel-reference.md) — 内核状态机、端口定义、适配器、工作流引擎

### `operations/`

部署、运维、排障、故障复盘相关文档。

当前已落地：
- [operations/README.md](operations/README.md) — 运维手册
- [operations/postmortem/](operations/postmortem/) — 故障复盘记录

### `guides/`

面向用户和开发者的操作指南。

当前已落地：
- [getting-started.md](guides/getting-started.md) — 快速上手
- [remote-skills-guide.md](guides/remote-skills-guide.md) — 远程 Skills 管理
- [remote-skills-quickstart.md](guides/remote-skills-quickstart.md) — Skills 快速入门

### `design/`

活跃的设计方案文档。默认不作为正式 SoT；方案稳定落地后才迁入 `architecture/` 或 `reference/`。

### `adr/`

架构决策记录（Architecture Decision Records）。记录"为什么这样设计"的重要决策。

### `articles/`

公众号文章与对外宣传内容。

### `archive/`

历史计划、草稿、报告归档。已被正式文档替代或不再活跃的内容迁入此处。

## 权威来源

| 主题 | 权威位置 |
|---|---|
| 项目首页 | [`README.md`](../README.md) |
| AI 规则 | [`AGENTS.md`](../AGENTS.md) |
| 架构事实 | [`architecture/`](architecture/) |
| 代码映射 / API / 配置 | [`reference/`](reference/) |
| 运维 / 排障 | [`operations/`](operations/) |
| 使用指南 | [`guides/`](guides/) |
| 历史资料 | [`archive/`](archive/) |
| 路线图 | [`ROADMAP.md`](../ROADMAP.md) |
| 贡献指南 | [`CONTRIBUTING.md`](../CONTRIBUTING.md) |

## 文档生命周期

- AI 生成文档默认先放在 `docs/design/`（或团队约定的临时协作空间）
- 只有在内容稳定、经过确认、且属于正式项目知识时，才迁入 `docs/`
- 活跃设计方案放在 `docs/design/`，落地后迁入 `docs/architecture/` 或 `docs/reference/`
- 被替代的正式文档应迁入 `archive/` 或明确标注替代关系
