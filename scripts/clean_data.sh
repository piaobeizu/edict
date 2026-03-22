#!/usr/bin/env bash
set -euo pipefail

# Edict Workflow V2 数据清理脚本
# 用法:
#   ./scripts/clean_data.sh
#   ./scripts/clean_data.sh --safe
#   ./scripts/clean_data.sh --full
#
# 说明:
#   --safe (默认):
#     1) 清空 PostgreSQL 运行数据（含 workflow v2 全量业务表）
#     2) 清空 Redis edict:* 业务 key，但保留 edict:stream:* key 与 consumer groups
#        同时将 stream 消息裁剪为 0（保留 stream/group 结构）
#     3) 清空 artifacts 文件
#     4) 重启 backend（重建 in-process workflow workers）
#
#   --full:
#     1) 同 safe 的 PostgreSQL + artifacts 清理
#     2) Redis FLUSHDB（全量清空）
#     3) 重启 backend；若存在 orchestrator/dispatcher 服务则一并重启

ROOT_DIR="/root/code/python/agents/edict"
COMPOSE_FILE="$ROOT_DIR/docker-compose.yml"
DC=(docker compose --project-directory "$ROOT_DIR" -f "$COMPOSE_FILE")

MODE="${1:---safe}"

usage() {
  echo "Usage: $0 [--safe|--full]"
}

compose_service_exists() {
  local service="$1"
  "${DC[@]}" config --services | rg -x -- "$service" >/dev/null 2>&1
}

ensure_compose_up() {
  echo "==> Checking compose stack..."
  "${DC[@]}" ps >/dev/null
}

clean_postgres() {
  echo "==> Cleaning PostgreSQL workflow/runtime tables..."
  "${DC[@]}" exec -T postgres psql -v ON_ERROR_STOP=1 -U edict <<'SQL'
DO $$
DECLARE
  tbl text;
  tables text[] := ARRAY[
    -- workflow v2
    'public.workflow_artifacts',
    'public.workflow_decisions',
    'public.workflow_assemblies',
    'public.workflow_candidates',
    'public.workflow_nodes',
    'public.workflow_revisions',
    'public.workflow_outbox',
    'public.workflow_instances',
    -- legacy runtime data
    'public.thoughts',
    'public.todos',
    'public.events',
    'public.tasks'
  ];
BEGIN
  FOREACH tbl IN ARRAY tables LOOP
    IF to_regclass(tbl) IS NOT NULL THEN
      EXECUTE format('TRUNCATE TABLE %s RESTART IDENTITY CASCADE', tbl);
      RAISE NOTICE 'truncated: %', tbl;
    ELSE
      RAISE NOTICE 'skip missing table: %', tbl;
    END IF;
  END LOOP;
END $$;
SQL
  echo "✅ PostgreSQL tables cleaned"
}

clean_redis_safe() {
  echo "==> Safe Redis cleanup (keep streams/groups, clear messages)..."
  "${DC[@]}" exec -T redis redis-cli --no-auth-warning EVAL "
    local cursor = '0'
    local deleted = 0
    local trimmed = 0
    repeat
      local scan = redis.call('SCAN', cursor, 'MATCH', 'edict:*', 'COUNT', 500)
      cursor = scan[1]
      local keys = scan[2]
      for _, k in ipairs(keys) do
        if string.sub(k, 1, 13) == 'edict:stream:' then
          redis.call('XTRIM', k, 'MAXLEN', 0)
          trimmed = trimmed + 1
        else
          redis.call('DEL', k)
          deleted = deleted + 1
        end
      end
    until cursor == '0'
    return {deleted, trimmed}
  " 0
  echo "✅ Redis safe cleanup complete"
}

clean_redis_full() {
  echo "==> Full Redis flush..."
  "${DC[@]}" exec -T redis redis-cli --no-auth-warning FLUSHDB
  echo "✅ Redis FLUSHDB complete"
}

clean_artifacts() {
  echo "==> Cleaning artifact files..."
  "${DC[@]}" exec -T backend sh -lc 'rm -rf /app/data/artifacts/* 2>/dev/null || true'
  echo "✅ Artifacts cleaned"
}

restart_workers() {
  echo "==> Restarting backend (recreate in-process workers)..."
  if compose_service_exists backend; then
    "${DC[@]}" restart backend
  fi

  # 兼容 legacy 独立 worker 容器（如果 compose 里仍有）
  if compose_service_exists orchestrator; then
    "${DC[@]}" restart orchestrator
  fi
  if compose_service_exists dispatcher; then
    "${DC[@]}" restart dispatcher
  fi

  sleep 2
  echo "✅ Worker processes restarted"
}

case "$MODE" in
  --safe)
    ;;
  --full)
    ;;
  -h|--help)
    usage
    exit 0
    ;;
  *)
    echo "❌ Unknown mode: $MODE"
    usage
    exit 2
    ;;
esac

echo "==> Clean mode: $MODE"
ensure_compose_up
clean_postgres

if [[ "$MODE" == "--full" ]]; then
  clean_redis_full
else
  clean_redis_safe
fi

clean_artifacts
restart_workers

echo ""
echo "🧹 Data cleanup complete. System ready for fresh Workflow V2 testing."
