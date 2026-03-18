# 当前代码结构设计说明

> 本文档说明 Edict 当前仓库的代码分层、目录职责，以及 `backend / kernel / frontend` 之间的关系。

---

## 1. 总体设计

当前仓库采用三层结构：

1. **`backend/`**：后端应用层
2. **`kernel/`**：可复用的工作流核心层
3. **`frontend/`**：前端展示层

目标是把：

- **业务编排与基础状态机** 拆到 `kernel/`
- **数据库 / API / Worker / 通知 / OpenClaw 集成** 放在 `backend/`
- **可视化与交互界面** 放在 `frontend/`

---

## 2. 顶层目录职责

```text
backend/         后端服务、数据库模型、API、Worker、迁移
frontend/        React + Vite 前端
kernel/          工作流核心与适配层
agents/          Agent SOUL 配置
tests/           仓库级测试
docs/            文档
scripts/         运维脚本
data/            运行态数据目录
```

---

## 3. backend/：后端应用层

```text
backend/
├── alembic.ini
├── app/
├── migration/
└── requirements.txt
```

### `backend/app/`

后端主代码目录。

- `api/`：HTTP / WebSocket 接口层
- `models/`：SQLAlchemy ORM 模型
- `services/`：服务层，封装任务、统计、通知、OpenClaw 运行时逻辑
- `workers/`：后台 Worker，负责消费事件并推进任务流转
- `notify/`：多通知渠道适配与发送
- `runtime_assets/`：运行时注入到 Agent workspace 的脚本资产

### `backend/migration/`

数据库迁移目录，配合 Alembic 管理 PostgreSQL schema 版本。

### `backend/alembic.ini`

Alembic 配置文件，和 `backend/migration/` 绑定使用。

---

## 4. kernel/：工作流核心层

```text
kernel/
├── __init__.py
├── pyproject.toml
├── setup.py
├── src/
│   ├── __init__.py
│   ├── state_machine.py
│   ├── task_entity.py
│   ├── workflow.py
│   ├── ports.py
│   └── adapters/
└── tests/
```

`kernel/` 的定位类似一个可安装 SDK / 核心库。

- `state_machine.py`：状态机定义与迁移校验
- `task_entity.py`：纯 Python 数据实体，不绑定 ORM
- `workflow.py`：核心工作流引擎
- `ports.py`：抽象接口定义（repo / bus / executor / routing）
- `adapters/`：把核心接口对接到 Postgres、Redis、OpenClaw、三省六部路由

### 为什么单独拆出 `kernel/`

1. 核心逻辑可独立测试
2. 应用层和流程规则解耦
3. 可以被安装/复用
4. 更容易替换底层基础设施

---

## 5. frontend/：前端展示层

```text
frontend/
├── src/
├── package.json
├── vite.config.ts
└── Dockerfile
```

这是 React + Vite 前端，负责：

- 看板展示
- 任务列表与详情交互
- 调用后端 API / WebSocket

它不直接接触数据库和 OpenClaw 运行时。

---

## 6. 三层如何协作

### backend 与 kernel

- `backend/` 使用 `kernel/`
- `kernel/` 不依赖后端 API 层

典型链路：

1. API / Worker 收到请求或事件
2. backend 调用 `kernel` 的工作流引擎
3. 引擎通过 ports 调 repo / bus / executor / routing
4. adapters 再落到 SQLAlchemy / Redis / OpenClaw

### frontend 与 backend

- `frontend/` 通过 HTTP / WebSocket 调 `backend/`
- 不直接 import Python 代码

### agents 与 backend

`agents/` 保存各 Agent 的 SOUL 配置。后端会读取并同步到 OpenClaw workspace，并注入运行时脚本。

---

## 7. 当前约定

1. `kernel/` 是可安装包，同时支持源码态测试
2. `backend/` 是主 Python 应用入口
3. `backend/alembic.ini` + `backend/migration/` 配套使用
4. `data/` 是运行态目录，不是主代码目录
5. `agents/` 是配置资产，不是 Python 包

---

## 8. 建议阅读顺序

建议按下面顺序理解代码：

1. `backend/app/main.py`
2. `backend/app/api/tasks.py`
3. `backend/app/services/task_service.py`
4. `kernel/src/workflow.py`
5. `kernel/src/state_machine.py`
6. `kernel/src/adapters/edict_routing.py`
7. `backend/app/workers/dispatch_worker.py`
8. `frontend/src/`
