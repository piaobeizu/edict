# Edict 文档归档索引

> 本索引记录所有已归档文档的位置和来源。
>
> 最后更新：2026-03-17

## 关联文档

- **当前实现口径**：[后端参考](reference/backend-reference.md)
- **架构事实**：[architecture/](architecture/)
- **文档管理规则**：[docs/README.md](README.md)

## 目录结构

| 目录 | 内容 | 来源 |
|------|------|------|
| `docs/archive/drafts/` | 历史架构草稿 | `docs/architecture/drafts/` |
| `docs/adr/` | 架构决策记录（ADR） | 决策文档 |
| `docs/design/` | 活跃设计方案 | 各阶段设计 |

## 文档清单

### 活跃设计方案 (docs/design/)

- [文生图/文生视频升级方案](design/media-generation-upgrade.md) — 媒体生成能力接入方案

### 历史草稿 (docs/archive/drafts/)

- [Edict Agent 架构重设计草案](archive/drafts/edict_agent_architecture.md) — 早期架构设计草案，已被正式架构文档替代

### 架构文档 (docs/architecture/)

- [架构总览](architecture/overview.md) — 十二部制全景
- [任务分发流转架构](architecture/task-dispatch-architecture.md) — 完整业务 + 技术架构
- [代码结构说明](architecture/code-structure.md) — 三层代码分层

### 参考文档 (docs/reference/)

- [后端参考](reference/backend-reference.md) — API、代码目录、配置
- [内核参考](reference/kernel-reference.md) — 状态机、端口、适配器

### 运维文档 (docs/operations/)

- [运维手册](operations/README.md) — 部署、排障、监控
- [故障复盘目录](operations/postmortem/) — Postmortem 记录

### 使用指南 (docs/guides/)

- [快速上手指南](guides/getting-started.md)
- [远程 Skills 管理指南](guides/remote-skills-guide.md)
- [Skills 快速入门](guides/remote-skills-quickstart.md)

### 文章 (docs/articles/)

- [公众号文章](articles/wechat.md)
- [公众号长文](articles/wechat-article.md)
