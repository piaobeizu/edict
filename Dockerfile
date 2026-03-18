FROM python:3.12-slim

WORKDIR /app

# 安装系统依赖 + Node.js 22（openclaw CLI 运行时需要）
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    curl \
    ca-certificates \
    gnupg \
    git \
    && mkdir -p /etc/apt/keyrings \
    && curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
       | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg \
    && echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_22.x nodistro main" \
       > /etc/apt/sources.list.d/nodesource.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*

# 安装 OpenClaw CLI（dispatcher 调用 `openclaw agent` 需要）
ARG OPENCLAW_VERSION=latest
RUN npm install -g "openclaw@${OPENCLAW_VERSION}" \
    && openclaw --version

# 安装 Python 依赖
COPY backend/requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir -r /tmp/requirements.txt

# 复制后端代码
COPY backend/ /app/

# 复制独立 kernel 包源码
COPY kernel/src/ /app/kernel/

# 复制 Alembic 配置
COPY backend/alembic.ini /app/alembic.ini

EXPOSE 8000

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
