# 文生图 / 文生视频 — 升级方案

## 1. 现状分析

### 1.1 OpenClaw 侧（已具备）

OpenClaw 在“调用外部能力并产出媒体文件”方面已经具备较完整基础设施，可直接复用：

- 已有 `openai-image-gen` skill（可调用 OpenAI Images API）
- 已有 `MEDIA:/path` 指令机制，允许工具输出媒体文件路径供上游系统识别
- 已有 `~/.openclaw/media/` 存储流水线
- Agent 可通过 `bash/exec` 执行任意脚本调用第三方 API
- 已有 `web_fetch` 工具用于 HTTP 请求

结论：OpenClaw 端能力已可作为“媒体生成执行层”，核心改造重点在 Edict 对媒体产物的接入、存储、回显与类型化。

### 1.2 Edict 侧（主要瓶颈）

当前 Edict 对媒体产物支持不足，主要缺口如下：

- 缺少文件上传 API 端点（`files.py` 目前仅下载）
- 缺少二进制/媒体存储路径（`_persist_text_artifact` 只写入 `.md`）
- `output_normalizer._looks_like_file_path()` 未覆盖图片/视频扩展名
- 前端 `TaskModal` 当前仅渲染纯文本，无 `img/video` 标签渲染
- `kanban_update.py` 缺少媒体 artifact 上报命令
- `ActivityEntry` 类型缺少媒体 kind（无法声明 `image/video`）

---

## 2. 升级工作清单

### Phase 1: 最小可用（文生图跑通）

目标：在不重构全链路的前提下，尽快实现“任务触发 -> 生成图片 -> 前端可见”。

1. **新增 OpenClaw Skills（图像/视频）**
   - 文生图候选 provider：Stability AI、DALL-E、Midjourney（如通过中转 API）
   - 文生视频候选 provider：Runway、Kling（可灵）、Pika
   - 技术要求：每个 skill 统一输出 `MEDIA:/absolute/path`，并在失败时提供可读错误信息
   - 下面示例为视频 skill 的 `SKILL.md` YAML frontmatter 结构：

```markdown
---
name: video-gen-generic
description: 使用第三方 API 执行文生视频并输出本地 mp4 文件路径
metadata:
  openclaw.emoji: "🎬"
requires:
  bins: ["python3"]
  env: ["VIDEO_API_KEY"]
primaryEnv: VIDEO_API_KEY
---

输入 prompt，调用视频生成 API，轮询任务状态，下载 mp4 到本地并输出 `MEDIA:/path/to/file.mp4`。
```

2. **将 skills 注册到 agent 工作区**
   - 目录：`edict/agents/{agent}/skills/`
   - 建议优先在 `gongbu` 下挂载媒体生成技能

3. **扩展 `output_normalizer.py`**
   - 在 `_looks_like_file_path()` 中增加以下扩展名：
   - `.png .jpg .jpeg .gif .webp .mp4 .webm .mov`

4. **增强 `/api/files/download` MIME 处理**
   - 根据文件 MIME 返回正确 `Content-Type`
   - 避免浏览器将图片/视频当作二进制流直接下载，支持内联预览

5. **前端 `TaskModal.tsx` 增加图片渲染**
   - 识别 image artifact
   - 渲染 `<img>`
   - 支持 lightbox（点击放大）

6. **更新 shangshu dispatch skill 路由表**
   - 将图像/视频请求优先路由到 `gongbu`（工部）

7. **更新 `gongbu/SOUL.md`**
   - 增补图像/视频生成工作流说明
   - 定义失败重试、超时、文件命名、产物上报规范

### Phase 2: 完整链路

目标：形成可维护的“上传-存储-索引-回放”全流程，覆盖图片与视频。

1. 创建媒体存储目录：`/app/data/media/{task_id}/`
2. 在 `files.py` 新增 `POST /api/files/upload`（multipart）
3. 扩展 `kanban_update.py`，增加 `artifact` 子命令用于媒体上报
4. 扩展 `dispatch_worker._backfill_task_output()` 处理媒体 artifact 类型
5. 扩展 Task 模型 `progress_log`，增加 `media_artifacts` 字段
6. 扩展前端 TypeScript 类型（`ActivityEntry/Artifact`）：
   - 增加 `kind: image | video | text`
   - 增加 `url` 字段
7. 在 `TaskModal` 增加视频播放器组件
8. 在活动流（activity feed）增加媒体卡片渲染
9. 更新 `taizi/SOUL.md`，增强“识别图像/视频生成请求”能力

### Phase 3: 生产就绪

目标：提升稳定性、可扩展性、成本可控与安全性。

1. 多 provider 支持（扩展更多图像/视频 API）
2. 在 `.env.example` 声明相关环境变量
3. Docker 配置升级：媒体卷挂载、安装 `ffmpeg`
4. 存储策略升级：本地存储 vs MinIO/S3（大视频对象存储）
5. 为生成媒体引入 CDN/缓存层
6. API 调用限流与成本控制（配额、熔断、预算告警）

---

## 3. 关键代码改动点

| 改动项 | 目标文件 | 具体修改 | 目的 |
|---|---|---|---|
| 媒体路径识别 | `output_normalizer.py` | 为 `_looks_like_file_path()` 增加图片/视频后缀 | 让 `MEDIA:/path` 与普通路径输出被正确识别为媒体产物 |
| 文件接口增强 | `files.py` | 新增上传端点 + 下载接口 MIME 感知 | 支持媒体入库与前端在线预览 |
| 产物上报命令 | `kanban_update.py` | 增加 `artifact` 子命令 | 让 agent 能结构化上报图片/视频结果 |
| 回填逻辑扩展 | `dispatch_worker.py` | 在 `_backfill_task_output` 处理媒体类型 artifact | 保证任务输出、日志、活动流一致 |
| 数据模型扩展 | `task.py` | `progress_log` schema 新增 `media_artifacts` | 后端持久化媒体元数据 |
| 前端 API 类型 | `api.ts` | 扩展 `ActivityEntry/Artifact` 类型字段 | 前后端协议显式支持 image/video/text |
| 弹窗渲染增强 | `TaskModal.tsx` | 新增图片/视频渲染逻辑 | 用户可直接查看生成结果 |
| 调度路由 | `shangshu` dispatch `SKILL.md` | 增加图像/视频任务分发规则 | 将媒体任务路由至 `gongbu` |
| 执行规范 | `gongbu/SOUL.md` | 补充媒体生成工作流 | 统一工部执行方式与异常处理 |
| 容器编排 | `docker-compose.yml` | 增加媒体 volume 挂载 | 容器重启后媒体文件可持久化 |
| 容器镜像 | `Dockerfile` | 安装 `ffmpeg`、注入新 env | 支持视频转码/探测及配置化运行 |
| 配置样例 | `.env.example` | 增加图像/视频 API key 变量 | 降低部署接入门槛 |

---

## 4. Skill 编写示例

以下示例遵循 OpenClaw skill 规范，包含 YAML frontmatter 与可执行 bash 片段。

### 4.1 文生图 Skill（Stability AI）

```markdown
---
name: stability-text-to-image
description: 使用 Stability AI 文生图并输出本地图片路径
metadata:
  openclaw.emoji: "🖼️"
requires:
  bins: ["python3"]
  env: ["STABILITY_API_KEY"]
primaryEnv: STABILITY_API_KEY
---

根据输入提示词生成图片，保存到本地后输出 `MEDIA:/abs/path/to/image.png`。

```bash
python3 - <<'PY'
import os
import uuid
import pathlib
import requests

prompt = os.environ.get("PROMPT", "A futuristic city at sunrise, cinematic, ultra detailed")
api_key = os.environ["STABILITY_API_KEY"]

out_dir = pathlib.Path.home() / ".openclaw" / "media"
out_dir.mkdir(parents=True, exist_ok=True)
out_path = out_dir / f"stability_{uuid.uuid4().hex}.png"

url = "https://api.stability.ai/v2beta/stable-image/generate/core"
headers = {
    "Authorization": f"Bearer {api_key}",
    "Accept": "image/*",
}
files = {
    "prompt": (None, prompt),
    "output_format": (None, "png"),
}

resp = requests.post(url, headers=headers, files=files, timeout=180)
resp.raise_for_status()

out_path.write_bytes(resp.content)
print(f"MEDIA:{out_path}")
PY
```
```

### 4.2 文生视频 Skill（通用第三方视频 API）

```markdown
---
name: generic-text-to-video
description: 调用通用视频生成 API，轮询并下载 mp4
metadata:
  openclaw.emoji: "🎬"
requires:
  bins: ["python3"]
  env: ["VIDEO_API_KEY", "VIDEO_API_BASE"]
primaryEnv: VIDEO_API_KEY
---

输入 prompt 创建视频任务，轮询完成后下载 mp4 到本地并输出 `MEDIA:/abs/path/to/video.mp4`。

```bash
python3 - <<'PY'
import os
import time
import uuid
import pathlib
import requests

prompt = os.environ.get("PROMPT", "A robot walking through rainy neon street, cinematic")
api_key = os.environ["VIDEO_API_KEY"]
base = os.environ.get("VIDEO_API_BASE", "https://api.example.com")

headers = {
    "Authorization": f"Bearer {api_key}",
    "Content-Type": "application/json",
}

# 1) 创建任务
create_resp = requests.post(
    f"{base}/v1/video/generations",
    headers=headers,
    json={"prompt": prompt, "duration": 5, "aspect_ratio": "16:9"},
    timeout=60,
)
create_resp.raise_for_status()
job_id = create_resp.json()["id"]

# 2) 轮询状态
video_url = None
for _ in range(120):
    st = requests.get(f"{base}/v1/video/generations/{job_id}", headers=headers, timeout=30)
    st.raise_for_status()
    data = st.json()
    if data.get("status") == "succeeded":
        video_url = data["output"]["url"]
        break
    if data.get("status") in {"failed", "canceled"}:
        raise RuntimeError(f"video generation failed: {data}")
    time.sleep(5)

if not video_url:
    raise TimeoutError("video generation timeout")

# 3) 下载到本地
out_dir = pathlib.Path.home() / ".openclaw" / "media"
out_dir.mkdir(parents=True, exist_ok=True)
out_path = out_dir / f"video_{uuid.uuid4().hex}.mp4"

dl = requests.get(video_url, timeout=300)
dl.raise_for_status()
out_path.write_bytes(dl.content)

print(f"MEDIA:{out_path}")
PY
```
```

---

## 5. 数据流全景

```text
用户创建任务
   |
   v
taizi（识别是否为文生图/文生视频）
   |
   v
zhongshu（任务分解与计划）
   |
   v
menxia（计划审阅与质量把关）
   |
   v
shangshu（路由分发到 gongbu）
   |
   v
gongbu agent 调用 image/video generation skill
   |
   v
skill 调用第三方 API（Stability/Runway/Kling/Pika/...）
   |
   v
下载结果到本地文件
   |
   v
输出 MEDIA:/path/to/file.(png|jpg|mp4...)
   |
   v
dispatch_worker 捕获 artifact
   |
   v
存储到 /app/data/media/{task_id}/
   |
   v
前端 TaskModal / Activity Feed 渲染图片与视频
```

---

## 6. 推荐实施顺序

- **Phase 1（1-2 天）**
  - Skill 接入 + `output_normalizer` 扩展 + 前端图片展示
  - 目标：最小改动打通文生图端到端链路

- **Phase 2（3-5 天）**
  - 完整上传/存储/视频播放/类型系统建设
  - 目标：图片与视频在任务系统中统一可追踪、可回放

- **Phase 3（持续进行）**
  - 生产加固（多 provider、对象存储、CDN、限流与成本控制）

---

## 7. 风险与注意事项

- 第三方 API 成本与速率限制（需预算与配额策略）
- 视频文件体积大（建议异步生成 + 轮询）
- API Key 安全（严禁提交到仓库，统一走环境变量/密钥管理）
- 生成超时（视频常需数分钟，必须采用异步任务模式）
- 提供商内容安全审核（需处理拒绝生成、违规内容回退）
- 媒体存储清理策略（TTL、归档、冷存储、定期清理）
