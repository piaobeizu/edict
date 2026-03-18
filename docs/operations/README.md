# 三省六部 · 运维手册

> 本文档汇总 Edict 项目的运维相关文档和常见问题解决方案。
>
> 最后更新：2026-03-17

## 关联文档

- **架构总览**：[architecture/overview.md](../architecture/overview.md)
- **后端参考**：[reference/backend-reference.md](../reference/backend-reference.md)
- **快速上手**：[guides/getting-started.md](../guides/getting-started.md)

---

## 基础设施

### 服务组成

| 服务 | 技术 | 端口 | 说明 |
|------|------|------|------|
| frontend | Nginx + Flutter/React | 8002 | 看板前端 |
| backend | FastAPI + Uvicorn | 8001 | REST API + WebSocket |
| orchestrator | Python Worker | — | 任务编排 |
| dispatcher | Python Worker | — | Agent 派发 |
| postgres | PostgreSQL 16 | 5432 | 主数据库 |
| redis | Redis 7 | 6379 | 事件总线 + 缓存 |

### Docker Compose 管理

```bash
# 启动全部服务
docker compose up -d --build

# 查看服务状态
docker compose ps

# 查看日志
docker compose logs -f backend
docker compose logs -f orchestrator dispatcher

# 重启单个服务
docker compose restart backend

# 停止全部服务
docker compose down
```

---

## 常见问题排查

### 看板显示「服务器未启动」

```bash
# 确认容器运行状态
docker compose ps

# 检查后端健康
curl -s http://127.0.0.1:8001/api/live-status | python3 -m json.tool
```

### Agent 不响应

```bash
# 检查 Gateway 状态
openclaw gateway status

# 检查 Agent 在线
curl -s http://127.0.0.1:8001/api/agents-status | python3 -m json.tool

# 重启 Gateway
openclaw gateway restart
```

### 任务超时 / 下属完成但无法传回太子

排查步骤：

1. 检查 Agent 注册状态：
```bash
curl -s http://127.0.0.1:8001/api/agents-status | python3 -m json.tool
```

2. 检查 Gateway 日志：
```bash
ls /tmp/openclaw/ | tail -5
grep -i "error\|fail\|unknown" /tmp/openclaw/openclaw-*.log | tail -20
```

3. 常见原因：
   - Agent ID 不匹配（核对 `taizi` 是否存在且在线）
   - LLM provider 超时
   - 僵尸 Agent 进程

4. 强制触发调度扫描：
```bash
curl -X POST http://127.0.0.1:8001/api/scheduler-scan \
  -H 'Content-Type: application/json' -d '{"thresholdSec":60}'
```

### 数据不更新

```bash
# 检查后端实时状态
curl -s http://127.0.0.1:8001/api/live-status | python3 -m json.tool

# 重启 Worker
docker compose restart orchestrator dispatcher
```

### Docker: exec format error

镜像架构（arm64）与主机架构（amd64）不匹配：

```bash
DOCKER_DEFAULT_PLATFORM=linux/amd64 docker compose up -d --build
```

### Skill 下载失败

```bash
# 测试网络连通性
curl -I https://raw.githubusercontent.com/openclaw-ai/skills-hub/main/code_review/SKILL.md

# 代理配置
export https_proxy=http://your-proxy:port
```

### 模型切换后不生效

等待约 5 秒让 Gateway 重启完成。仍不生效：

```bash
openclaw gateway restart
```

### 心跳显示红色 / 告警

```bash
# 检查对应 Agent
openclaw agent status <agent-id>

# 重启指定 Agent
openclaw agent restart <agent-id>
```

---

## 数据库维护

### 数据库迁移

```bash
cd backend
alembic upgrade head
```

### 数据清理

```bash
# 清理运行时数据
bash scripts/clean_data.sh
```

---

## 监控

### 关键指标

- 任务完成率（Done / 总创建数）
- 平均流转时长（从 Pending 到 Done）
- Agent 在线率（活跃 / 总数）
- Token 消耗总量与趋势

### 实时状态检查

```bash
# 服务健康
curl -s http://127.0.0.1:8001/api/live-status

# Agent 状态
curl -s http://127.0.0.1:8001/api/agents-status

# 看板统计
curl -s http://127.0.0.1:8001/api/dashboard-stats
```

---

## 定期维护

| 频率 | 任务 | 命令 |
|------|------|------|
| 每日 | 检查 Agent 在线状态 | `curl .../api/agents-status` |
| 每周 | 检查磁盘空间（媒体文件、日志） | `df -h && du -sh data/` |
| 每月 | 清理已归档旧任务数据 | `scripts/clean_data.sh` |
| 按需 | 数据库备份 | `pg_dump ...` |

---

## 故障复盘

故障复盘记录位于 [postmortem/](postmortem/) 目录。

命名规范：`YYYY-MM-DD-简短描述.md`

结构模板：
1. 问题背景
2. 根因分析
3. 解决方案（方案对比）
4. 改进效果
5. 验证步骤
6. 后续改进

---

## 相关文档

- [故障复盘目录](postmortem/)
- [架构总览](../architecture/overview.md)
- [后端参考](../reference/backend-reference.md)
- [快速上手指南](../guides/getting-started.md)
