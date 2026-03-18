# 后端参考

> 本文档以当前代码实现为准，不承担架构 SoT 角色。架构事实请参考 [architecture/](../architecture/)。
>
> 最后更新：2026-03-17

## 关联文档

- [架构总览](../architecture/overview.md)
- [代码结构说明](../architecture/code-structure.md)
- [内核参考](kernel-reference.md)
- [运维手册](../operations/README.md)

---

## 1. 进程与职责

| 进程 | 入口 | 端口 | 职责 |
|------|------|------|------|
| backend | `backend/app/main.py` | 8001 | FastAPI 主服务，REST API + WebSocket |
| orchestrator | `backend/app/workers/orchestrator_worker.py` | — | 消费事件，推进任务状态流转 |
| dispatcher | `backend/app/workers/dispatch_worker.py` | — | 执行 OpenClaw Agent 派发，回填任务产出 |
| frontend | `frontend/` (Nginx) | 8002 | React 看板静态资源托管 |
| flutter_app | `flutter_app/` (Nginx) | 8002 | Flutter Web 主前端 |

---

## 2. 代码目录

```
backend/
├── alembic.ini                  # Alembic 配置
├── requirements.txt             # Python 依赖
├── app/
│   ├── main.py                  # FastAPI 入口，路由注册，CORS，生命周期
│   ├── config.py                # 配置管理（环境变量、常量）
│   ├── db.py                    # 数据库连接池
│   ├── api/                     # HTTP / WebSocket 接口层
│   │   ├── tasks.py             # 任务 CRUD、状态推进、审批
│   │   ├── agents.py            # Agent 状态查询
│   │   ├── events.py            # 事件查询
│   │   ├── admin.py             # 管理接口
│   │   ├── websocket.py         # WebSocket 推送
│   │   ├── dashboard.py         # 看板数据聚合
│   │   ├── insights.py          # 数据洞察
│   │   ├── metrics.py           # 指标查询
│   │   ├── files.py             # 文件下载
│   │   ├── notify.py            # 通知管理
│   │   ├── compat.py            # v1 兼容层
│   │   └── legacy.py            # 旧接口
│   ├── models/                  # SQLAlchemy ORM 模型
│   │   ├── task.py              # 任务模型
│   │   ├── event.py             # 事件模型
│   │   ├── thought.py           # 思考过程模型
│   │   └── todo.py              # 待办模型
│   ├── services/                # 业务服务层
│   │   ├── task_service.py      # 任务业务逻辑
│   │   ├── event_bus.py         # Redis 事件总线
│   │   ├── openclaw_runtime.py  # OpenClaw 运行时封装
│   │   ├── morning_brief.py     # 天下要闻服务
│   │   ├── officials_stats.py   # 官员统计
│   │   ├── metrics.py           # 指标计算
│   │   ├── output_normalizer.py # 产出归一化
│   │   ├── structured_log.py    # 结构化日志
│   │   └── task_notifier.py     # 任务通知服务
│   ├── workers/                 # 后台 Worker
│   │   ├── orchestrator_worker.py  # 编排 Worker
│   │   └── dispatch_worker.py      # 派发 Worker
│   ├── notify/                  # 通知渠道
│   │   └── channels/            # bark, dingtalk, discord, email,
│   │                            # feishu, pushplus, serverchan,
│   │                            # slack, telegram, wecom
│   ├── runtime_assets/          # 注入到 Agent workspace 的运行时脚本
│   │   └── kanban_update.py     # 看板 CLI（Agent 用来上报状态/进展）
│   └── cli/
│       └── ops.py               # 运维 CLI
└── migration/                   # Alembic 迁移
    ├── env.py
    ├── migrate_json_to_pg.py
    └── versions/
        └── 001_initial.py
```

---

## 3. 核心 API 端点

### 任务管理

| 方法 | 路径 | 说明 |
|------|------|------|
| `POST` | `/api/create-task` | 创建旨意 |
| `GET` | `/api/tasks` | 获取任务列表 |
| `GET` | `/api/task-activity/{task_id}` | 获取任务完整活动流 |
| `POST` | `/api/advance-state/{task_id}` | 推进任务状态 |
| `POST` | `/api/review-action/{task_id}` | 审批操作（准奏/封驳） |
| `POST` | `/api/stop-task/{task_id}` | 叫停任务 |
| `POST` | `/api/resume-task/{task_id}` | 恢复任务 |
| `POST` | `/api/cancel-task/{task_id}` | 取消任务 |

### Agent 管理

| 方法 | 路径 | 说明 |
|------|------|------|
| `GET` | `/api/agents-status` | 获取所有 Agent 在线状态 |
| `GET` | `/api/agent-sessions/{agent_id}` | 获取 Agent 会话列表 |
| `POST` | `/api/scheduler-scan` | 手动触发调度扫描 |

### 看板数据

| 方法 | 路径 | 说明 |
|------|------|------|
| `GET` | `/api/live-status` | 实时状态概览 |
| `GET` | `/api/dashboard-stats` | 看板统计数据 |
| `GET` | `/api/officials-stats` | 官员统计（Token 消耗、活跃度） |

### Skills 管理

| 方法 | 路径 | 说明 |
|------|------|------|
| `GET` | `/api/remote-skills-list` | 查看所有远程 Skills |
| `POST` | `/api/add-remote-skill` | 添加远程 Skill |

### 其他

| 方法 | 路径 | 说明 |
|------|------|------|
| `GET` | `/api/files/download/{path}` | 文件下载 |
| `GET` | `/api/morning-brief` | 天下要闻 |
| `WS` | `/ws` | WebSocket 实时推送 |

---

## 4. CLI 工具：kanban_update.py

Agent 通过此工具与看板交互。路径：`backend/app/runtime_assets/kanban_update.py`

| 命令 | 用途 | 示例 |
|------|------|------|
| `create` | 创建任务 | `kanban_update.py create <id> <title> <state> <org> <official>` |
| `state` | 更新状态 | `kanban_update.py state <id> Menxia "提交审议"` |
| `flow` | 添加流转记录 | `kanban_update.py flow <id> "中书省" "门下省" "提交审核"` |
| `progress` | 实时进展汇报 | `kanban_update.py progress <id> "进展文本" "todo1✅\|todo2🔄"` |
| `done` | 标记完成 | `kanban_update.py done <id> <output_url> "总结"` |
| `stop` | 叫停 | `kanban_update.py stop <id> "原因"` |
| `resume` | 恢复 | `kanban_update.py resume <id> "原因"` |
| `cancel` | 取消 | `kanban_update.py cancel <id> "原因"` |

---

## 5. 配置与环境变量

| 变量 | 说明 | 默认值 |
|------|------|--------|
| `DATABASE_URL` | PostgreSQL 连接字符串 | `postgresql+asyncpg://...` |
| `REDIS_URL` | Redis 连接字符串 | `redis://localhost:6379/0` |
| `BACKEND_PORT` | 后端服务端口 | `8001` |
| `OPENCLAW_HOME` | OpenClaw 工作目录 | `~/.openclaw` |

---

## 6. 启动命令

```bash
# Docker Compose 一键启动（推荐）
docker compose up -d --build

# 本地开发
cd backend && uvicorn app.main:app --host 0.0.0.0 --port 8001 --reload

# 安装内核包（本地开发）
pip install -e ./kernel

# 数据库迁移
cd backend && alembic upgrade head

# 运行测试
python3 -m pytest tests/
```
