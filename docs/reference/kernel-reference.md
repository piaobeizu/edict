# 内核参考

> 本文档以当前代码实现为准。架构事实请参考 [architecture/](../architecture/)。
>
> 最后更新：2026-03-17

## 关联文档

- [架构总览](../architecture/overview.md)
- [代码结构说明](../architecture/code-structure.md)
- [后端参考](backend-reference.md)

---

## 1. 内核定位

`kernel/` 是一个可安装的 Python 包，封装了 Edict 的核心工作流逻辑。

**设计原则**：
- 不依赖 FastAPI、SQLAlchemy 等应用层框架
- 通过端口（Ports）定义抽象接口，通过适配器（Adapters）对接具体基础设施
- 可独立测试和复用

---

## 2. 代码目录

```
kernel/
├── pyproject.toml
├── setup.py
├── src/
│   ├── __init__.py
│   ├── state_machine.py       # 状态机定义与迁移校验
│   ├── task_entity.py         # 纯 Python 数据实体
│   ├── workflow.py            # 核心工作流引擎
│   ├── ports.py               # 抽象接口（Protocol）
│   └── adapters/
│       ├── pg_task_repo.py    # PostgreSQL 任务仓库
│       ├── redis_event_bus.py # Redis 事件总线
│       ├── openclaw_executor.py # OpenClaw Agent 执行器
│       └── edict_routing.py   # 三省六部路由策略
└── tests/
```

---

## 3. 状态机（state_machine.py）

定义任务的有限状态机和合法迁移规则。

### 状态枚举

```
Pending → Taizi → Zhongshu → Menxia → Assigned → Doing → Review → Done
                                                    ↕
                                                   Next
特殊状态：Blocked（叫停）、Cancelled（取消）
```

### 迁移校验

状态机负责校验状态迁移是否合法。非法迁移会被拒绝，保障流程严格递进。

---

## 4. 任务实体（task_entity.py）

纯 Python 数据类，不绑定 ORM。

### 核心字段

| 字段 | 类型 | 说明 |
|------|------|------|
| `id` | str | 全局唯一 ID（JJC-日期-序号） |
| `title` | str | 旨意标题 |
| `state` | str | 当前状态 |
| `org` | str | 当前负责部门 |
| `official` | str | 负责官职 |
| `priority` | str | 优先级（critical/high/normal/low） |
| `flow_log` | list | 流转记录 |
| `progress_log` | list | Agent 进展汇报 |
| `output` | str | 最终产出 |
| `_scheduler` | dict | 调度元数据 |

---

## 5. 端口定义（ports.py）

使用 Python Protocol 定义四个核心抽象接口：

### TaskRepo

任务持久化接口。

| 方法 | 说明 |
|------|------|
| `save(task)` | 保存任务 |
| `get(task_id)` | 获取任务 |
| `list(filters)` | 列表查询 |
| `update(task)` | 更新任务 |

### EventBusPort

事件总线接口。

| 方法 | 说明 |
|------|------|
| `publish(event)` | 发布事件 |
| `subscribe(topic, handler)` | 订阅事件 |

### AgentExecutor

Agent 执行接口。

| 方法 | 说明 |
|------|------|
| `dispatch(agent_id, message)` | 派发消息给 Agent |
| `status(agent_id)` | 查询 Agent 状态 |

### RoutingPolicy

任务路由策略接口。

| 方法 | 说明 |
|------|------|
| `resolve_agent(task)` | 根据任务状态和部门推断目标 Agent |
| `resolve_org(state)` | 根据状态推断目标部门 |

---

## 6. 适配器实现（adapters/）

| 适配器 | 文件 | 对接端口 | 实现说明 |
|--------|------|---------|---------|
| PgTaskRepo | `pg_task_repo.py` | TaskRepo | PostgreSQL + SQLAlchemy 异步 |
| RedisEventBus | `redis_event_bus.py` | EventBusPort | Redis Pub/Sub |
| OpenClawExecutor | `openclaw_executor.py` | AgentExecutor | `openclaw agent --deliver` CLI |
| EdictRouting | `edict_routing.py` | RoutingPolicy | 三省六部权限矩阵 + 状态-Agent 映射 |

### 路由策略（edict_routing.py）

核心映射表：

```python
_STATE_AGENT_MAP = {
    'Taizi':    'taizi',
    'Zhongshu': 'zhongshu',
    'Menxia':   'menxia',
    'Assigned': 'shangshu',
    'Doing':    None,       # 从 task.org 推断
    'Next':     None,       # 从 task.org 推断
    'Review':   'shangshu',
    'Pending':  'zhongshu',
}

_ORG_AGENT_MAP = {
    '户部': 'hubu',
    '礼部': 'libu',
    '兵部': 'bingbu',
    '刑部': 'xingbu',
    '工部': 'gongbu',
    '吏部': 'libu_hr',
}
```

---

## 7. 工作流引擎（workflow.py）

协调创建、迁移、派发、进展上报的核心流程。

### 主要方法

| 方法 | 说明 |
|------|------|
| `create(task)` | 创建任务，初始化状态机 |
| `advance(task_id)` | 推进到下一状态 |
| `dispatch(task)` | 根据当前状态派发 Agent |
| `report_progress(task_id, progress)` | 记录进展 |
| `review(task_id, action)` | 执行审批（准奏/封驳） |

---

## 8. 安装与使用

```bash
# 从仓库根目录安装
pip install -e ./kernel

# 快速使用
from kernel import TaskEntity, WorkflowEngine

task = TaskEntity(id="JJC-demo-001", title="demo")
engine = WorkflowEngine(...)
engine.create(task)
```
