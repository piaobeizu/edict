#!/usr/bin/env bash
set -euo pipefail

# Edict 安全数据清理脚本
# 用法:
#   ./scripts/clean_data.sh          # 清空任务+事件，保留 Streams/Groups
#   ./scripts/clean_data.sh --full   # 清空全部（含 Redis Streams），然后重建

ROOT_DIR="/root/code/python/agents/edict"
COMPOSE_FILE="$ROOT_DIR/docker-compose.yml"
DC=(docker compose --project-directory "$ROOT_DIR" -f "$COMPOSE_FILE")

MODE="${1:-safe}"

echo "==> Clean mode: $MODE"

# ── 1. 清空 PostgreSQL 任务和事件表 ──
echo "==> Cleaning PostgreSQL tables..."
"${DC[@]}" exec -T postgres psql -U edict -c "
  DELETE FROM events;
  DELETE FROM tasks;
"
echo "✅ PostgreSQL: tasks + events cleared"

# ── 2. 清空 Redis 业务数据（保留 Streams 和 Consumer Groups）──
if [[ "$MODE" == "--full" ]]; then
  echo "==> Full Redis flush (will recreate streams)..."
  "${DC[@]}" exec -T redis redis-cli FLUSHDB
  echo "⚠️  Redis FLUSHDB done — restarting workers to recreate consumer groups..."
  "${DC[@]}" restart orchestrator dispatcher
  sleep 3
  echo "✅ Workers restarted, streams recreated"
else
  echo "==> Safe Redis cleanup (keeping streams & consumer groups)..."
  "${DC[@]}" exec -T redis redis-cli --no-auth-warning eval "
    local keys = redis.call('KEYS', 'edict:orch:*')
    for i, k in ipairs(keys) do redis.call('DEL', k) end
    local keys2 = redis.call('KEYS', 'edict:dispatch:*')
    for i, k in ipairs(keys2) do redis.call('DEL', k) end
    local keys3 = redis.call('KEYS', 'edict:pubsub:*')
    for i, k in ipairs(keys3) do redis.call('DEL', k) end
    local keys4 = redis.call('KEYS', 'edict:throttle:*')
    for i, k in ipairs(keys4) do redis.call('DEL', k) end
    -- Trim streams to 0 (keep stream + group, remove all messages)
    local streams = redis.call('KEYS', 'edict:stream:*')
    for i, s in ipairs(streams) do redis.call('XTRIM', s, 'MAXLEN', 0) end
    return #keys + #keys2 + #keys3 + #keys4 + #streams
  " 0
  echo "✅ Redis: business keys + stream messages cleared, groups preserved"
fi

# ── 3. 清空产出文件 ──
echo "==> Cleaning artifact files..."
"${DC[@]}" exec -T backend sh -c 'rm -rf /app/data/artifacts/* 2>/dev/null; echo "done"'
echo "✅ Artifacts cleared"

echo ""
echo "🧹 Data cleanup complete. System ready for new tasks."
