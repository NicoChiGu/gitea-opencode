#!/usr/bin/env sh
set -eu

RUNNER_LABEL="ubuntu-22.04"
ACTION_IMAGE="registry.cn-hangzhou.aliyuncs.com/terata/gitea-opencode:latest"
DEFAULT_MODEL="anthropic/claude-sonnet-4-6"
MODEL=""
MODEL_SET=0
API_KEY_SECRET=""
API_KEY_SECRET_SET=0
FORCE=0
DRY_RUN=0
NO_COMMIT=0
NO_PUSH=0
NON_INTERACTIVE=0
CHECKOUT_ACTION="actions/checkout@v4"
COMMIT_MESSAGE="chore: add gitea opencode workflow"
TEMPLATE_URL="${OPENCODE_WORKFLOW_TEMPLATE_URL:-https://raw.githubusercontent.com/NicoChiGu/gitea-opencode/main/templates/opencode.yml}"

usage() {
  cat <<'EOF'
用法: ./install-opencode.sh [选项]

选项:
  --force                 覆盖已存在的 .gitea/workflows/opencode.yml 文件
  --dry-run               仅打印工作流配置，不写入实际文件
  --no-commit             写入工作流，但不自动提交到 git
  --no-push               提交工作流，但不自动推送到远程仓库
  --runner-label <label>  Gitea runner 标签，默认：ubuntu-22.04
  --action-image <image>  OpenCode action 步骤所使用的 Docker 镜像
  --container-image <image>
                          --action-image 的已弃用别名
  --model <model>         格式为 "服务商/模型" 的 OpenCode 模型
  --api-key-secret <name> 为所选服务商指定的 Gitea Actions 密钥名称
  --checkout-action <action>
                          使用的 checkout action，默认：actions/checkout@v4
  --yes, --non-interactive
                          跳过交互提示并使用默认配置
  --help                  显示此帮助信息
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --force)
      FORCE=1
      shift
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --no-commit)
      NO_COMMIT=1
      shift
      ;;
    --no-push)
      NO_PUSH=1
      shift
      ;;
    --runner-label)
      RUNNER_LABEL="${2:-}"
      [ -n "$RUNNER_LABEL" ] || { echo "--runner-label requires a value" >&2; exit 2; }
      shift 2
      ;;
    --action-image|--container-image)
      ACTION_IMAGE="${2:-}"
      [ -n "$ACTION_IMAGE" ] || { echo "$1 requires a value" >&2; exit 2; }
      shift 2
      ;;
    --model)
      MODEL="${2:-}"
      [ -n "$MODEL" ] || { echo "--model requires a value" >&2; exit 2; }
      MODEL_SET=1
      shift 2
      ;;
    --api-key-secret)
      API_KEY_SECRET="${2:-}"
      [ -n "$API_KEY_SECRET" ] || { echo "--api-key-secret requires a value" >&2; exit 2; }
      API_KEY_SECRET_SET=1
      shift 2
      ;;
    --checkout-action)
      CHECKOUT_ACTION="${2:-}"
      [ -n "$CHECKOUT_ACTION" ] || { echo "--checkout-action requires a value" >&2; exit 2; }
      shift 2
      ;;
    --yes|--non-interactive)
      NON_INTERACTIVE=1
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "此安装程序必须在 Git 仓库内运行。" >&2
  exit 1
fi

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
TEMPLATE="$SCRIPT_DIR/templates/opencode.yml"
DEST=".gitea/workflows/opencode.yml"

if [ -f "$DEST" ] && [ "$FORCE" -ne 1 ] && [ "$DRY_RUN" -ne 1 ]; then
  if [ "$NON_INTERACTIVE" -eq 1 ] || [ ! -t 0 ] || [ ! -r /dev/tty ] || [ ! -w /dev/tty ]; then
    echo "$DEST 已存在。在非交互模式下，请使用 --force 参数进行覆盖。" >&2
    exit 1
  else
    echo "" > /dev/tty
    printf "检测到 %s 已存在，是否覆盖？[y/N]: " "$DEST" > /dev/tty
    IFS= read -r prompt_choice < /dev/tty || prompt_choice=""
    case "$prompt_choice" in
      [yY]|[yY][eE][sS])
        echo "已确认覆盖。" > /dev/tty
        ;;
      *)
        echo "操作已取消。" > /dev/tty
        exit 0
        ;;
    esac
  fi
fi

load_template() {
  if [ -f "$TEMPLATE" ]; then
    cat "$TEMPLATE"
    return
  fi

  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$TEMPLATE_URL"
    return
  fi

  if command -v wget >/dev/null 2>&1; then
    wget -qO- "$TEMPLATE_URL"
    return
  fi

  echo "Workflow template not found locally, and neither curl nor wget is available." >&2
  echo "Expected local template: $TEMPLATE" >&2
  echo "Remote template: $TEMPLATE_URL" >&2
  exit 1
}

fetch_dynamic_models() {
  DEFAULT_MODELS_STR="Anthropic Claude Sonnet 4.6 (推荐);anthropic/claude-sonnet-4-6
OpenAI GPT-5 Codex;openai/gpt-5-codex
OpenAI ChatGPT latest;openai/gpt-5-chat-latest
OpenCode Zen Claude Sonnet 4;opencode/claude-sonnet-4
OpenCode Zen Big Pickle (免费);opencode/big-pickle
OpenCode Zen DeepSeek V4 Flash Free (免费);opencode/deepseek-v4-flash-free
OpenCode Zen MiMo V2.5 Free (免费);opencode/mimo-v2.5-free
OpenCode Zen North Mini Code Free (免费);opencode/north-mini-code-free
OpenCode Zen Nemotron 3 Ultra Free (免费);opencode/nemotron-3-ultra-free
DeepSeek Reasoner;deepseek/deepseek-reasoner
Moonshot Kimi K2 Thinking;moonshotai/kimi-k2-thinking
MiniMax M2.5;minimax/MiniMax-M2.5
Xiaomi MiMo V2.5 Pro China;xiaomi-token-plan-cn/mimo-v2.5-pro
Xiaomi MiMo V2.5 Pro Singapore;xiaomi-token-plan-sgp/mimo-v2.5-pro
Xiaomi MiMo V2.5 Pro Amsterdam;xiaomi-token-plan-ams/mimo-v2.5-pro"

  ACTIVE_MODELS_STR="$DEFAULT_MODELS_STR"

  API_URL="https://models.dev/api.json"
  JSON_DATA=""
  if command -v curl >/dev/null 2>&1; then
    JSON_DATA=$(curl -fsSL --connect-timeout 3 "$API_URL" 2>/dev/null) || JSON_DATA=""
  elif command -v wget >/dev/null 2>&1; then
    JSON_DATA=$(wget -qO- --timeout=3 "$API_URL" 2>/dev/null) || JSON_DATA=""
  fi

  if [ -n "$JSON_DATA" ]; then
    if command -v node >/dev/null 2>&1; then
      PARSED=$(node -e '
        try {
          const data = JSON.parse(process.argv[1]);
          const models = data.opencode.models;
          const zenModels = [];
          for (const mId of ["claude-sonnet-4-6", "claude-sonnet-4"]) {
            if (models[mId]) {
              zenModels.push(`OpenCode Zen ${models[mId].name};opencode/${mId}`);
            }
          }
          for (const mId of Object.keys(models)) {
            if (mId === "claude-sonnet-4-6" || mId === "claude-sonnet-4") continue;
            const m = models[mId];
            const isFree = mId.endsWith("-free") || mId === "big-pickle" || (m.cost && m.cost.input === 0);
            if (isFree) {
              let name = m.name;
              if (!name.endsWith("Free") && !name.includes("免费")) name += " (免费)";
              zenModels.push(`OpenCode Zen ${name};opencode/${mId}`);
            }
          }
          const output = [
            "Anthropic Claude Sonnet 4.6 (推荐);anthropic/claude-sonnet-4-6",
            "OpenAI GPT-5 Codex;openai/gpt-5-codex",
            "OpenAI ChatGPT latest;openai/gpt-5-chat-latest",
            ...zenModels,
            "DeepSeek Reasoner;deepseek/deepseek-reasoner",
            "Moonshot Kimi K2 Thinking;moonshotai/kimi-k2-thinking",
            "MiniMax M2.5;minimax/MiniMax-M2.5",
            "Xiaomi MiMo V2.5 Pro China;xiaomi-token-plan-cn/mimo-v2.5-pro",
            "Xiaomi MiMo V2.5 Pro Singapore;xiaomi-token-plan-sgp/mimo-v2.5-pro",
            "Xiaomi MiMo V2.5 Pro Amsterdam;xiaomi-token-plan-ams/mimo-v2.5-pro"
          ];
          console.log(output.join("\n"));
        } catch (e) {}
      ' "$JSON_DATA" 2>/dev/null) || PARSED=""
      if [ -n "$PARSED" ]; then
        ACTIVE_MODELS_STR="$PARSED"
        return
      fi
    fi

    if command -v python3 >/dev/null 2>&1 || command -v python >/dev/null 2>&1; then
      PYTHON_CMD="python3"
      command -v python3 >/dev/null 2>&1 || PYTHON_CMD="python"
      PARSED=$($PYTHON_CMD -c '
import sys, json
try:
    data = json.loads(sys.argv[1])
    models = data["opencode"]["models"]
    zen_models = []
    for mId in ["claude-sonnet-4-6", "claude-sonnet-4"]:
        if mId in models:
            zen_models.append(f"OpenCode Zen {models[mId][\"name\"]};opencode/{mId}")
    for mId in models:
        if mId in ["claude-sonnet-4-6", "claude-sonnet-4"]:
            continue
        m = models[mId]
        is_free = mId.endswith("-free") or mId == "big-pickle" or (m.get("cost") and m.get("cost").get("input") == 0)
        if is_free:
            name = m["name"]
            if not name.endswith("Free") and "免费" not in name:
                name += " (免费)"
            zen_models.append(f"OpenCode Zen {name};opencode/{mId}")
    output = [
        "Anthropic Claude Sonnet 4.6 (推荐);anthropic/claude-sonnet-4-6",
        "OpenAI GPT-5 Codex;openai/gpt-5-codex",
        "OpenAI ChatGPT latest;openai/gpt-5-chat-latest"
    ] + zen_models + [
        "DeepSeek Reasoner;deepseek/deepseek-reasoner",
        "Moonshot Kimi K2 Thinking;moonshotai/kimi-k2-thinking",
        "MiniMax M2.5;minimax/MiniMax-M2.5",
        "Xiaomi MiMo V2.5 Pro China;xiaomi-token-plan-cn/mimo-v2.5-pro",
        "Xiaomi MiMo V2.5 Pro Singapore;xiaomi-token-plan-sgp/mimo-v2.5-pro",
        "Xiaomi MiMo V2.5 Pro Amsterdam;xiaomi-token-plan-ams/mimo-v2.5-pro"
    ]
    print("\n".join(output))
except Exception as e:
    pass
' "$JSON_DATA" 2>/dev/null) || PARSED=""
      if [ -n "$PARSED" ]; then
        ACTIVE_MODELS_STR="$PARSED"
        return
      fi
    fi
  fi
}

select_model() {
  if [ "$MODEL_SET" -eq 1 ]; then
    validate_model
    return
  fi

  fetch_dynamic_models

  if [ "$NON_INTERACTIVE" -eq 1 ] || [ ! -t 0 ] || [ ! -r /dev/tty ] || [ ! -w /dev/tty ]; then
    MODEL="$DEFAULT_MODEL"
    return
  fi

  {
    echo
    echo "请选择 OpenCode 模型："
    i=1
    old_ifs="$IFS"
    IFS='
'
    for line in $ACTIVE_MODELS_STR; do
      [ -n "$line" ] || continue
      name=$(echo "$line" | cut -d';' -f1)
      id=$(echo "$line" | cut -d';' -f2)
      printf " %2d) %-44s [%s]\n" "$i" "$name" "$id"
      i=$((i + 1))
    done
    manual_num=$i
    printf " %2d) 手动输入 服务商/模型\n" "$manual_num"
    printf "请选择 [1]: "
    IFS="$old_ifs"
  } > /dev/tty

  IFS= read -r choice < /dev/tty || choice=""
  case "$choice" in
    ''|*[!0-9]*)
      if [ -z "$choice" ]; then
        MODEL="$DEFAULT_MODEL"
      else
        echo "无效的选择: $choice" >&2
        exit 2
      fi
      ;;
    *)
      if [ "$choice" -eq "$manual_num" ]; then
        printf "请输入模型 (格式为 服务商/模型): " > /dev/tty
        IFS= read -r MODEL < /dev/tty || MODEL=""
      else
        i=1
        old_ifs="$IFS"
        IFS='
'
        found_model=""
        for line in $ACTIVE_MODELS_STR; do
          [ -n "$line" ] || continue
          if [ "$i" -eq "$choice" ]; then
            found_model=$(echo "$line" | cut -d';' -f2)
            break
          fi
          i=$((i + 1))
        done
        IFS="$old_ifs"
        if [ -n "$found_model" ]; then
          MODEL="$found_model"
        else
          echo "无效的选择: $choice" >&2
          exit 2
        fi
      fi
      ;;
  esac

  validate_model
}

validate_model() {
  case "$MODEL" in
    */*) ;;
    *)
      echo "模型格式必须为 '服务商/模型'，当前输入为：$MODEL" >&2
      exit 2
      ;;
  esac
}

secret_for_provider() {
  provider="${MODEL%%/*}"
  case "$provider" in
    anthropic) API_KEY_SECRET="ANTHROPIC_API_KEY" ;;
    openai) API_KEY_SECRET="OPENAI_API_KEY" ;;
    opencode) API_KEY_SECRET="OPENCODE_API_KEY" ;;
    deepseek) API_KEY_SECRET="DEEPSEEK_API_KEY" ;;
    moonshotai) API_KEY_SECRET="MOONSHOT_API_KEY" ;;
    minimax) API_KEY_SECRET="MINIMAX_API_KEY" ;;
    openrouter) API_KEY_SECRET="OPENROUTER_API_KEY" ;;
    xiaomi-token-plan-cn|xiaomi-token-plan-sgp|xiaomi-token-plan-ams) API_KEY_SECRET="XIAOMI_API_KEY" ;;
    *)
      if [ "$NON_INTERACTIVE" -eq 1 ] || [ ! -t 0 ] || [ ! -r /dev/tty ] || [ ! -w /dev/tty ]; then
        echo "未知的服务商 '$provider'。请重新运行并使用 --api-key-secret <SECRET_NAME> 参数。" >&2
        exit 2
      fi
      printf "请输入服务商 '%s' 的 Gitea Actions 密钥名称: " "$provider" > /dev/tty
      IFS= read -r API_KEY_SECRET < /dev/tty || API_KEY_SECRET=""
      ;;
  esac
}

validate_api_key_secret() {
  case "$API_KEY_SECRET" in
    ""|[0-9]*|GITHUB_*|GITEA_*|*[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_]*)
      echo "无效的密钥名称: $API_KEY_SECRET" >&2
      echo "仅允许使用字母、数字和下划线，且不能以数字开头，也不能以 GITHUB_ 或 GITEA_ 开头。" >&2
      exit 2
      ;;
  esac
}

select_api_key_secret() {
  if [ "$API_KEY_SECRET_SET" -eq 0 ]; then
    secret_for_provider
  fi
  validate_api_key_secret
}

provider_api_key_env_line() {
  printf '          %s: ${{ secrets.%s }}' "$API_KEY_SECRET" "$API_KEY_SECRET"
}

print_next_steps() {
  {
    echo
    echo "OpenCode 工作流配置完成。"
    echo "Runner 标签: $RUNNER_LABEL"
    echo "Action 镜像: $ACTION_IMAGE"
    echo "已选模型: $MODEL"
    echo "请在 Gitea Actions 中为所选服务商添加以下密钥:"
    echo "  $API_KEY_SECRET=<您的 API 密钥>"
    echo "用于 Gitea 写入的可选 Token 覆盖:"
    echo "  OPENCODE_GITEA_TOKEN=<Gitea 个人访问令牌>"
  } >&2
}

select_checkout_action() {
  if [ "$NON_INTERACTIVE" -eq 1 ] || [ ! -t 0 ] || [ ! -r /dev/tty ] || [ ! -w /dev/tty ]; then
    return
  fi

  echo > /dev/tty
  printf "请输入 Checkout Action [默认: %s]: " "$CHECKOUT_ACTION" > /dev/tty
  IFS= read -r choice < /dev/tty || choice=""
  if [ -n "$choice" ]; then
    CHECKOUT_ACTION="$choice"
  fi
}

render_workflow() {
  select_model
  select_checkout_action
  select_api_key_secret
  provider_env_line=$(provider_api_key_env_line)
  load_template | sed \
    -e "s#__RUNNER_LABEL__#$RUNNER_LABEL#g" \
    -e "s#__ACTION_IMAGE__#$ACTION_IMAGE#g" \
    -e "s#__PROVIDER_API_KEY_ENV__#$provider_env_line#g" \
    -e "s#__OPENCODE_MODEL__#$MODEL#g" \
    -e "s#https://github.com/actions/checkout@v4#$CHECKOUT_ACTION#g" \
    -e "s#__CHECKOUT_ACTION__#$CHECKOUT_ACTION#g"
}

if [ "$DRY_RUN" -eq 1 ]; then
  render_workflow
  print_next_steps
  exit 0
fi

mkdir -p .gitea/workflows
render_workflow > "$DEST"
echo "已写入 $DEST"

if [ "$NO_COMMIT" -eq 1 ]; then
  print_next_steps
  exit 0
fi

git add "$DEST"
if git diff --cached --quiet -- "$DEST"; then
  echo "没有要提交的工作流更改。"
else
  git commit -m "$COMMIT_MESSAGE"
fi

if [ "$NO_PUSH" -eq 1 ]; then
  print_next_steps
  exit 0
fi

BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [ "$BRANCH" = "HEAD" ]; then
  echo "无法从分离的 HEAD 分支进行推送。请重新运行并使用 --no-push 参数，或签出到一个分支。" >&2
  exit 1
fi

git push origin "$BRANCH"
print_next_steps
