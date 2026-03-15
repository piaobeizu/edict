#!/usr/bin/env bash
set -euo pipefail

# Edict v2 统一重部署脚本
# 用法:
#   ./scripts/redeploy_v2.sh full      # 全量重部署（默认）
#   ./scripts/redeploy_v2.sh backend   # 仅后端/worker（并重启 frontend 规避 502）
#   ./scripts/redeploy_v2.sh frontend  # 仅前端（强制 no-cache 重建）
#
# 可选环境变量（用于自动配置 OpenClaw 鉴权）:
#   OPENAI_API_KEY / OPENAI_BASE_URL / OPENAI_MODEL   -> 第三方 OpenAI 兼容
#   OPENAI_PROVIDER_ID                                -> 可选，自定义 provider id（默认自动推断）
#   OPENAI_API_KEY                                    -> OpenAI 官方
#   ANTHROPIC_API_KEY                                 -> Anthropic 官方
#   SKIP_OPENCLAW_AUTH=1                              -> 跳过自动鉴权配置

MODE="${1:-full}"

ROOT_DIR="/root/code/python/agents/edict"
COMPOSE_FILE="$ROOT_DIR/edict/docker-compose.yml"

DC=(docker compose --project-directory "$ROOT_DIR" -f "$COMPOSE_FILE")

echo "==> MODE: $MODE"
echo "==> Compose: $COMPOSE_FILE"

ensure_up() {
  "${DC[@]}" ps
}

ensure_openclaw_agents() {
  echo "==> Ensure OpenClaw agent IDs"
  "${DC[@]}" exec -T dispatcher sh -lc '
    set -e
    for a in taizi zhongshu menxia shangshu hubu libu bingbu xingbu gongbu libu_hr zaochao; do
      openclaw agents add "$a" --non-interactive --workspace "/root/.openclaw/workspace-$a" >/tmp/oc_add_$a.log 2>&1 || true
    done
    openclaw agents list
  '
}

configure_openclaw_auth() {
  if [[ "${SKIP_OPENCLAW_AUTH:-0}" == "1" ]]; then
    echo "==> Skip OpenClaw auth config (SKIP_OPENCLAW_AUTH=1)"
    return
  fi

  echo "==> Configure OpenClaw auth (best effort)"
  "${DC[@]}" exec -T dispatcher sh -lc '
    set -e
    if [ -n "${OPENAI_API_KEY:-}" ] && [ -n "${OPENAI_BASE_URL:-}" ] && [ -n "${OPENAI_MODEL:-}" ]; then
      echo "Using custom OpenAI-compatible provider"
      openclaw onboard --non-interactive --accept-risk \
        --skip-channels --skip-daemon --skip-ui --skip-health \
        --auth-choice custom-api-key \
        --custom-compatibility openai \
        --custom-api-key "$OPENAI_API_KEY" \
        --custom-base-url "$OPENAI_BASE_URL" \
        --custom-model-id "$OPENAI_MODEL"
      exit 0
    fi

    if [ -n "${OPENAI_API_KEY:-}" ]; then
      echo "Using OpenAI provider"
      openclaw onboard --non-interactive --accept-risk \
        --skip-channels --skip-daemon --skip-ui --skip-health \
        --openai-api-key "$OPENAI_API_KEY"
      exit 0
    fi

    if [ -n "${ANTHROPIC_API_KEY:-}" ]; then
      echo "Using Anthropic provider"
      openclaw onboard --non-interactive --accept-risk \
        --skip-channels --skip-daemon --skip-ui --skip-health \
        --anthropic-api-key "$ANTHROPIC_API_KEY"
      exit 0
    fi

    echo "WARN: No API key found in dispatcher env; skip OpenClaw auth onboarding"
  '
}

sync_openclaw_auth_profiles() {
  echo "==> Sync auth-profiles.json to all agent IDs (best effort)"
  "${DC[@]}" exec -T dispatcher sh -lc '
    set -e
    src="/root/.openclaw/agents/main/agent/auth-profiles.json"
    if [ ! -f "$src" ]; then
      echo "WARN: $src not found; skip auth profile sync"
      exit 0
    fi

    for a in taizi zhongshu menxia shangshu hubu libu bingbu xingbu gongbu libu_hr zaochao; do
      mkdir -p "/root/.openclaw/agents/$a/agent"
      cp -f "$src" "/root/.openclaw/agents/$a/agent/auth-profiles.json"
    done
    echo "auth profile synced"
  '
}

normalize_openclaw_model_config() {
  echo "==> Normalize OpenClaw model defaults (v1-compatible)"
  "${DC[@]}" exec -T dispatcher sh -lc '
    set -e
    python - <<"PY"
import json
import os
import pathlib

cfg_path = pathlib.Path("/root/.openclaw/openclaw.json")
if not cfg_path.exists():
    print("WARN: openclaw.json not found; skip normalize")
    raise SystemExit(0)

cfg = json.loads(cfg_path.read_text(encoding="utf-8"))
models = (cfg.get("models") or {})
providers = (models.get("providers") or {})
if not providers:
    print("WARN: no models.providers found; skip normalize")
    raise SystemExit(0)

env_provider = (os.getenv("OPENAI_PROVIDER_ID") or "").strip()
provider_id = env_provider if env_provider in providers else next(iter(providers.keys()))

provider = providers.get(provider_id) or {}
provider_models = provider.get("models") or []
if not provider_models:
    print("WARN: provider has no models; skip normalize")
    raise SystemExit(0)

model_id = (os.getenv("OPENAI_MODEL") or "").strip() or provider_models[0].get("id")

# 确保 provider 下存在 model_id
exists = any((m or {}).get("id") == model_id for m in provider_models)
if not exists:
    template = dict(provider_models[0])
    template["id"] = model_id
    template["name"] = template.get("name") or model_id
    template["api"] = template.get("api") or provider.get("api") or "openai-completions"
    provider_models.append(template)
    provider["models"] = provider_models
    providers[provider_id] = provider

# OpenAI 兼容端（尤其 GPT-5.x）常要求 max_completion_tokens
for m in provider_models:
    if not isinstance(m, dict):
        continue
    mid = (m.get("id") or "")
    if mid == model_id or mid.startswith("openai/gpt-5"):
        compat = m.setdefault("compat", {})
        compat["maxTokensField"] = "max_completion_tokens"
        m["api"] = m.get("api") or provider.get("api") or "openai-completions"

provider["models"] = provider_models
providers[provider_id] = provider
cfg.setdefault("models", {})["providers"] = providers

default_model = f"{provider_id}/{model_id}"
agents = cfg.setdefault("agents", {})
defaults = agents.setdefault("defaults", {})
defaults["model"] = {"primary": default_model}

# 清掉 agent 级 model 覆盖，统一走默认模型（与 v1 行为一致）
for ag in agents.get("list", []) or []:
    if isinstance(ag, dict) and "model" in ag:
      ag.pop("model", None)

cfg_path.write_text(json.dumps(cfg, ensure_ascii=False, indent=2), encoding="utf-8")
print("normalized default model:", default_model)
PY
  '
}

smoke_test() {
  echo "==> Smoke test"

  code_health="$(curl -s -o /tmp/edict_health.json -w "%{http_code}" http://127.0.0.1:8001/health || true)"
  code_live="$(curl -s -o /tmp/edict_live.json -w "%{http_code}" http://127.0.0.1:8002/api/live-status || true)"
  code_officials="$(curl -s -o /tmp/edict_officials.json -w "%{http_code}" http://127.0.0.1:8002/api/officials-stats || true)"
  code_create="$(curl -s -o /tmp/edict_create.json -w "%{http_code}" \
    -X POST http://127.0.0.1:8002/api/create-task \
    -H "Content-Type: application/json" \
    -d "{\"title\":\"SOP验收-$(date +%Y%m%d-%H%M%S)\",\"org\":\"太子\",\"priority\":\"高\"}" || true)"

  echo "health:         $code_health"
  echo "live-status:    $code_live"
  echo "officials:      $code_officials"
  echo "create-task:    $code_create"

  if [[ "$code_health" != "200" || "$code_live" != "200" || "$code_officials" != "200" || "$code_create" != "200" ]]; then
    echo "❌ Smoke test failed."
    echo "--- /health ---" && cat /tmp/edict_health.json || true
    echo "--- /api/live-status ---" && cat /tmp/edict_live.json || true
    echo "--- /api/officials-stats ---" && cat /tmp/edict_officials.json || true
    echo "--- POST /api/create-task ---" && cat /tmp/edict_create.json || true
    exit 1
  fi

  echo "✅ Smoke test passed."
}

case "$MODE" in
  full)
    echo "==> Full redeploy"
    "${DC[@]}" down
    "${DC[@]}" up -d --build
    # backend 重建后，重启 frontend，避免 nginx upstream 指向旧容器IP导致 502
    "${DC[@]}" restart frontend
    ensure_openclaw_agents
    configure_openclaw_auth
    normalize_openclaw_model_config
    sync_openclaw_auth_profiles
    ;;

  backend)
    echo "==> Backend/worker redeploy"
    "${DC[@]}" up -d --build backend orchestrator dispatcher
    # 关键步骤：规避 502
    "${DC[@]}" restart frontend
    ensure_openclaw_agents
    configure_openclaw_auth
    normalize_openclaw_model_config
    sync_openclaw_auth_profiles
    ;;

  frontend)
    echo "==> Frontend redeploy"
    "${DC[@]}" build --no-cache frontend
    "${DC[@]}" up -d --force-recreate frontend
    ;;

  *)
    echo "Unknown mode: $MODE"
    echo "Usage: $0 [full|backend|frontend]"
    exit 2
    ;;
esac

ensure_up
smoke_test

echo "🎉 Redeploy complete."
