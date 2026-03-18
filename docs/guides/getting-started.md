# 🚀 快速上手指南

> 从零开始，5 分钟搭建你的三省六部 AI 协同系统

---

## 第一步：安装 OpenClaw

三省六部基于 [OpenClaw](https://openclaw.ai) 运行，请先安装：

```bash
# macOS
brew install openclaw

# 或下载安装包
# https://openclaw.ai/download
```

安装完成后初始化：

```bash
openclaw init
```

## 第二步：克隆并启动三省六部（Docker Compose）

```bash
git clone https://github.com/cft0808/edict.git
cd edict
docker compose up -d --build
```

Compose 会自动拉起 backend / worker / postgres / redis / frontend。
- ✅ 重启 Gateway 使配置生效

> 本地开发可选：如需直接调试内核包，可在仓库根目录执行 `pip install -e ./kernel`。

## 第三步：配置消息渠道

在 OpenClaw 中配置消息渠道（Feishu / Telegram / Signal），将 `taizi`（太子）Agent 设为旨意入口。太子会自动分拣闲聊与指令，指令类消息提炼标题后转发中书省。

```bash
# 查看当前渠道
openclaw channels list

# 添加飞书渠道（入口设为太子）
openclaw channels add --type feishu --agent taizi
```

参考 OpenClaw 文档：https://docs.openclaw.ai/channels

## 第四步：启动服务

```bash
# 启动 v2 前后端 + worker
docker compose up -d --build

# 打开浏览器
open http://127.0.0.1:8002
```

> 💡 `docker compose ps` 可查看 backend/frontend/orchestrator/dispatcher 状态。

如果你想先理解目录分层和代码职责，再继续往下看：

- [当前代码结构设计说明](../architecture/code-structure.md)

## 第五步：发送第一道旨意

通过消息渠道发送任务（太子会自动识别并转发到中书省）：

```
请帮我用 Python 写一个文本分类器：
1. 使用 scikit-learn
2. 支持多分类
3. 输出混淆矩阵
4. 写完整的文档
```

## 第六步：观察执行过程

打开看板 http://127.0.0.1:8002

1. **📋 旨意看板** — 观察任务在各状态之间流转
2. **🔭 省部调度** — 查看各部门工作分布
3. **📜 奏折阁** — 任务完成后自动归档为奏折

任务流转路径：
```
收件 → 太子分拣 → 中书规划 → 门下审议 → 已派发 → 执行中 → 已完成
```

---

## 🎯 进阶用法

### 使用圣旨模板

> 看板 → 📜 旨库 → 选择模板 → 填写参数 → 下旨

9 个预设模板：周报生成 · 代码审查 · API 设计 · 竞品分析 · 数据报告 · 博客文章 · 部署方案 · 邮件文案 · 站会摘要

### 切换 Agent 模型

> 看板 → ⚙️ 模型配置 → 选择新模型 → 应用更改

约 5 秒后 Gateway 自动重启生效。

### 管理技能

> 看板 → 🛠️ 技能配置 → 查看已安装技能 → 点击添加新技能

### 叫停 / 取消任务

> 在旨意看板或任务详情中，点击 **⏸ 叫停** 或 **🚫 取消** 按钮

### 订阅天下要闻

> 看板 → 📰 天下要闻 → ⚙️ 订阅管理 → 选择分类 / 添加源 / 配飞书推送

---

## ❓ 故障排查

### 看板显示「服务器未启动」
```bash
# 确认前后端容器正在运行
docker compose ps
```

### Agent 不响应
```bash
# 检查 Gateway 状态
openclaw gateway status

# 必要时重启
openclaw gateway restart
```

### 数据不更新
```bash
# 检查后端实时状态接口
curl -s http://127.0.0.1:8001/api/live-status | python3 -m json.tool

# 必要时重启 v2 服务
docker compose restart backend orchestrator dispatcher
```

### 心跳显示红色 / 告警
```bash
# 检查对应 Agent 的进程
openclaw agent status <agent-id>

# 重启指定 Agent
openclaw agent restart <agent-id>
```

### 模型切换后不生效
等待约 5 秒让 Gateway 重启完成。仍不生效则：
```bash
openclaw gateway restart
```

---

## 📚 更多资源

- [🏠 项目首页](https://github.com/cft0808/edict)
- [📖 README](../../README.md)
- [🤝 贡献指南](../../CONTRIBUTING.md)
- [💬 OpenClaw 文档](https://docs.openclaw.ai)
- [📮 公众号 · cft0808](../articles/wechat.md) — 架构拆解 / 踩坑复盘 / Token 省钱术
