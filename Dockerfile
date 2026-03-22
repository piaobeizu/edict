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

# 构建并安装 kernel wheel（走编译安装链路）
COPY kernel/ /tmp/kernel/
RUN python -m pip wheel --no-deps --wheel-dir /tmp/kernel-dist /tmp/kernel \
    && python -m pip install --no-cache-dir /tmp/kernel-dist/*.whl \
    && rm -rf /tmp/kernel /tmp/kernel-dist

# 复制后端代码
COPY backend/ /app/

# 防御式兜底：确保运行时可直接 import kernel.*
# （某些 wheel 构建场景下 package-dir 映射可能导致模块未被正确打包）
COPY kernel/src/ /app/kernel/

# 复制 Alembic 配置
COPY backend/alembic.ini /app/alembic.ini

EXPOSE 8000

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
