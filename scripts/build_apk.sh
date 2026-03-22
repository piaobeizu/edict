#!/usr/bin/env bash
# ─────────────────────────────────────────────
# Edict APK 一键构建 + 部署脚本
# 用法: ./scripts/build_apk.sh [--debug]
# ─────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="${SCRIPT_DIR}/../flutter_app"
ROOT_DIR="${SCRIPT_DIR}/.."
COMPOSE_FILE="${ROOT_DIR}/docker-compose.yml"

cd "$PROJECT_DIR"

MODE="release"
[[ "${1:-}" == "--debug" ]] && MODE="debug"

APK_PATH="build/app/outputs/flutter-apk/app-${MODE}.apk"
WEB_APK_PATH="build/web/edict.apk"
APK_URL="${APK_URL:-http://35.241.111.186:8002/edict.apk}"

DC=(docker compose --project-directory "$ROOT_DIR" -f "$COMPOSE_FILE")

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

echo "📦 写入 Flutter Web 静态目录..."
mkdir -p "$(dirname "$WEB_APK_PATH")"
cp -f "$APK_PATH" "$WEB_APK_PATH"
echo "✅ 已写入: $(pwd)/${WEB_APK_PATH}"

echo "🚀 重建并重启 frontend 服务（将 APK 烘焙进镜像）..."
"${DC[@]}" build --no-cache frontend
"${DC[@]}" up -d --force-recreate frontend

echo "🔍 验证下载端点..."
if curl -I -s "$APK_URL" | awk 'BEGIN{ok=0} /^Content-Type:/ {if ($2 !~ /text\/html/) ok=1} END{exit ok?0:1}'; then
  echo "✅ 已部署，下载地址: $APK_URL"
else
  echo "⚠️  APK 端点仍返回 HTML，可能是前端还在重启，稍后重试：$APK_URL"
fi
