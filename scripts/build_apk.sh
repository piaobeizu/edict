#!/usr/bin/env bash
# ─────────────────────────────────────────────
# Edict APK 一键构建 + 部署脚本
# 用法: ./scripts/build_apk.sh [--debug]
# ─────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="${SCRIPT_DIR}/../flutter_app"

cd "$PROJECT_DIR"

MODE="release"
[[ "${1:-}" == "--debug" ]] && MODE="debug"

CONTAINER="edict-frontend-1"
NGINX_PATH="/usr/share/nginx/html/edict.apk"
APK_PATH="build/app/outputs/flutter-apk/app-${MODE}.apk"

# 加载环境变量（flutter 路径等）
source ~/.zshrc 2>/dev/null || source ~/.bashrc 2>/dev/null || true

echo "🔨 构建 ${MODE} APK..."
echo "   项目: ${PROJECT_DIR}"

if ! flutter build apk --${MODE} --no-tree-shake-icons; then
  echo "❌ APK 构建失败"
  exit 1
fi

if [[ ! -f "$APK_PATH" ]]; then
  echo "❌ APK 文件不存在: ${APK_PATH}"
  exit 1
fi

SIZE=$(du -h "$APK_PATH" | cut -f1)
echo "✅ APK 构建成功: ${SIZE}"

echo "📦 部署到 Docker 容器..."
if docker cp "$APK_PATH" "${CONTAINER}:${NGINX_PATH}" 2>/dev/null; then
  echo "✅ 已部署，下载地址: http://35.241.111.186:8002/edict.apk"
else
  echo "⚠️  容器 ${CONTAINER} 不存在，跳过部署"
  echo "   APK 位置: $(pwd)/${APK_PATH}"
fi
