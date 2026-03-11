#!/bin/bash
# ══════════════════════════════════════════════════════
# 三省六部 · 统一镜像启动入口
# ══════════════════════════════════════════════════════

set -e

echo "=========================================="
echo "  三省六部 · Unified Container Starting"
echo "=========================================="

OC_HOME="$HOME/.openclaw"
OC_CFG="$OC_HOME/openclaw.json"
mkdir -p "$OC_HOME"

# ── 首次启动：生成 openclaw.json 基础配置 ──
if [ ! -f "$OC_CFG" ]; then
    echo "[entrypoint] 首次启动，生成 openclaw.json 基础配置..."
    # 环境变量说明：
    #   LLM_PROVIDER_ID    — 自定义 provider 名称，不能含斜杠 / （如 gmi、my-proxy）
    #   LLM_BASE_URL       — API 地址（如 https://api.gmi-serving.com/v1）
    #   LLM_API_KEY        — API Key
    #   LLM_MODEL_ID       — 发给 API 的模型名（如 openai/gpt-5.4），可含斜杠
    #   LLM_DEFAULT_MODEL  — OpenClaw 内部模型标识，格式 {provider_id}/{model_id}
    #                        （如 gmi/openai/gpt-5.4，第一段必须匹配 LLM_PROVIDER_ID）
    #   LLM_CONTEXT_WINDOW — 模型上下文窗口大小（默认 128000）
    #   LLM_MAX_TOKENS     — 最大输出 token 数（默认 32768）

    _PROVIDER_ID="${LLM_PROVIDER_ID:-my-openai-proxy}"
    _MODEL_ID="${LLM_MODEL_ID:-gpt-4o}"
    _DEFAULT_MODEL="${LLM_DEFAULT_MODEL:-${_PROVIDER_ID}/${_MODEL_ID}}"

    python3 -c "
import json, os, pathlib, sys

provider_id   = os.environ.get('LLM_PROVIDER_ID', 'my-openai-proxy')
base_url      = os.environ.get('LLM_BASE_URL', 'https://api.openai.com/v1')
api_key       = os.environ.get('LLM_API_KEY', 'sk-xxx-change-me')
model_id      = os.environ.get('LLM_MODEL_ID', 'gpt-4o')
default_model = os.environ.get('LLM_DEFAULT_MODEL', f'{provider_id}/{model_id}')
ctx_window    = int(os.environ.get('LLM_CONTEXT_WINDOW', '128000'))
max_tokens    = int(os.environ.get('LLM_MAX_TOKENS', '32768'))

# 校验: provider_id 不能含斜杠
if '/' in provider_id:
    print(f'[entrypoint] ERROR: LLM_PROVIDER_ID 不能包含斜杠: \"{provider_id}\"', file=sys.stderr)
    print(f'[entrypoint] 提示: LLM_PROVIDER_ID 只是 provider 名称（如 gmi）', file=sys.stderr)
    print(f'[entrypoint]        LLM_MODEL_ID 是发给 API 的模型名（如 openai/gpt-5.4）', file=sys.stderr)
    print(f'[entrypoint]        LLM_DEFAULT_MODEL 是完整标识（如 gmi/openai/gpt-5.4）', file=sys.stderr)
    sys.exit(1)

cfg = {
    'gateway': {'mode': 'local'},
    'models': {
        'providers': {
            provider_id: {
                'baseUrl': base_url,
                'apiKey': api_key,
                'api': 'openai-completions',
                'models': [{
                    'id': model_id,
                    'name': model_id,
                    'api': 'openai-completions',
                    'reasoning': False,
                    'input': ['text', 'image'],
                    'cost': {'input': 0, 'output': 0, 'cacheRead': 0, 'cacheWrite': 0},
                    'contextWindow': ctx_window,
                    'maxTokens': max_tokens,
                    'compat': {
                        'maxTokensField': 'max_completion_tokens'
                    }
                }]
            }
        }
    },
    'agents': {
        'defaults': {
            'model': default_model
        }
    }
}

pathlib.Path('$OC_CFG').write_text(json.dumps(cfg, indent=2, ensure_ascii=False))
print(f'[entrypoint] openclaw.json created: provider={provider_id}, model={default_model}')
"
    echo "[entrypoint] openclaw.json 已创建"

    # 运行 install.sh 注册 agent workspace
    if [ -f /app/install.sh ]; then
        echo "[entrypoint] 注册 agent workspace..."
        bash /app/install.sh || echo "[entrypoint] install.sh 部分步骤跳过（可稍后手动执行）"
    fi
else
    echo "[entrypoint] 已检测到 openclaw.json"

    # 确保已有配置使用 loopback 绑定（容器内通信不需要 lan）
    python3 -c "
import json, pathlib
cfg_path = pathlib.Path('$OC_CFG')
cfg = json.loads(cfg_path.read_text())
gw = cfg.setdefault('gateway', {})
changed = False
# 容器内 gateway 绑 loopback，CLI 和 dashboard 都走 127.0.0.1
for key in ['bind', 'auth', 'controlUi']:
    if key in gw:
        del gw[key]
        changed = True
if changed:
    cfg_path.write_text(json.dumps(cfg, indent=2, ensure_ascii=False))
    print('[entrypoint] 已清理 gateway 配置 (使用默认 loopback)')
" || true
fi

# 确保 data 目录存在
mkdir -p /app/data

# 同步 agent 配置
if [ -f /app/scripts/sync_agent_config.py ]; then
    echo "[entrypoint] 同步 agent 配置..."
    python3 /app/scripts/sync_agent_config.py || true
fi

echo "[entrypoint] 启动所有服务..."
exec "$@"
