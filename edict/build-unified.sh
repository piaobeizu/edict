#!/bin/bash
# ══════════════════════════════════════════════════════
# 三省六部 · 统一镜像构建脚本
# ══════════════════════════════════════════════════════
#
# 用 tar 精确打包 openclaw/ 和 edict/ 发给 docker build，
# 排除 .git、node_modules 等大目录，无需 .dockerignore。
#
# 用法：
#   ./edict/build-unified.sh [--no-cache] [--push]
#
# ══════════════════════════════════════════════════════

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
EDICT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PARENT_DIR="$(cd "$EDICT_ROOT/.." && pwd)"

OPENCLAW_DIR="${OPENCLAW_DIR:-$PARENT_DIR/openclaw}"
IMAGE_NAME="${IMAGE_NAME:-edict-unified}"
IMAGE_TAG="${IMAGE_TAG:-latest}"

NO_CACHE=""
PUSH=""
for arg in "$@"; do
    case "$arg" in
        --no-cache) NO_CACHE="--no-cache" ;;
        --push) PUSH="true" ;;
    esac
done

if [ ! -f "$OPENCLAW_DIR/package.json" ]; then
    echo "ERROR: OpenClaw source not found at: $OPENCLAW_DIR"
    echo "  Ensure openclaw/ is alongside edict/, or set OPENCLAW_DIR"
    exit 1
fi

OPENCLAW_NAME="$(basename "$OPENCLAW_DIR")"
EDICT_NAME="$(basename "$EDICT_ROOT")"

echo "=========================================="
echo "  三省六部 · Build Unified Image"
echo "=========================================="
echo ""
echo "  Edict:    $EDICT_ROOT"
echo "  OpenClaw: $OPENCLAW_DIR"
echo "  Image:    $IMAGE_NAME:$IMAGE_TAG"
echo ""
echo "  Packing build context (tar)..."

# 用 tar 打包两个目录，排除不需要的大目录，管道传给 docker build
# 注意：tar 管道模式下 -f 必须用 context 内的相对路径
tar -cf - \
    -C "$PARENT_DIR" \
    --exclude='.git' \
    --exclude='node_modules' \
    --exclude='.vite' \
    --exclude='__pycache__' \
    --exclude='.ruff_cache' \
    "$OPENCLAW_NAME" "$EDICT_NAME" \
  | docker build \
    $NO_CACHE \
    -f "$EDICT_NAME/edict/Dockerfile.unified" \
    -t "$IMAGE_NAME:$IMAGE_TAG" \
    -

echo ""
echo "Build complete: $IMAGE_NAME:$IMAGE_TAG"
echo ""
echo "Quick start:"
echo "  docker run -d -p 7891:7891 -p 18789:18789 \\"
echo "    -v openclaw_data:/root/.openclaw \\"
echo "    -v edict_data:/app/data \\"
echo "    $IMAGE_NAME:$IMAGE_TAG"
echo ""
echo "Or with compose:"
echo "  docker compose -f $SCRIPT_DIR/docker-compose.unified.yml up -d"
echo ""
echo "Endpoints:"
echo "  Dashboard: http://localhost:7891"
echo "  OpenClaw:  http://localhost:18789"

if [ -n "$PUSH" ]; then
    echo ""
    echo "Pushing image..."
    docker push "$IMAGE_NAME:$IMAGE_TAG"
fi
