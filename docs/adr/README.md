# ADR 目录

本目录存放仍有长期价值的架构决策记录（Architecture Decision Records）。

## 当前文档

（暂无 ADR。下方为推荐的首批 ADR 选题。）

### 推荐选题

- **ADR-0001**：三省六部制 vs 自由协作模式 —— 为什么选择制度化协作
- **ADR-0002**：kernel 独立包 vs 单体后端 —— 为什么将工作流内核拆分为独立包
- **ADR-0003**：PostgreSQL + Redis vs 纯 Redis —— 持久化与事件总线的技术选型
- **ADR-0004**：Flutter Web vs React —— 前端技术选型演进

## 说明

- `adr/` 记录的是"为什么这样设计"，而非"怎么设计的"
- 当前架构事实仍以 `docs/architecture/**` 为权威口径

## ADR 模板

```markdown
# ADR-NNNN: 标题

> Date: YYYY-MM-DD
> Status: proposed | accepted | deprecated | superseded
> 决策者：
> 触发事件：

## 背景

[问题描述和上下文]

## 方案对比

| 维度 | 方案 A | 方案 B |
|------|--------|--------|
| ... | ... | ... |

## 决策

[最终选择及理由]

## 影响

[该决策的影响和后续行动]
```
