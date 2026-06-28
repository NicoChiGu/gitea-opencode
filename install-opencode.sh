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

select_model() {
  if [ "$MODEL_SET" -eq 1 ]; then
    validate_model
    return
  fi

  if [ "$NON_INTERACTIVE" -eq 1 ] || [ ! -t 0 ] || [ ! -r /dev/tty ] || [ ! -w /dev/tty ]; then
    MODEL="$DEFAULT_MODEL"
    return
  fi

  {
    echo
    echo "请选择 OpenCode 模型："
    echo "  1) Anthropic Claude Sonnet 4.6 (推荐)        [$DEFAULT_MODEL]"
    echo "  2) OpenAI GPT-5 Codex                        [openai/gpt-5-codex]"
    echo "  3) OpenAI ChatGPT latest                     [openai/gpt-5-chat-latest]"
    echo "  4) OpenCode Zen Claude Sonnet 4              [opencode/claude-sonnet-4]"
    echo "  5) OpenCode Zen Big Pickle (免费)            [opencode/big-pickle]"
    echo "  6) OpenCode Zen MiniMax M2.5 Free (免费)     [opencode/minimax-m2.5-free]"
    echo "  7) OpenCode Zen Nemotron 3 Super Free (免费) [opencode/nemotron-3-super-free]"
    echo "  8) OpenCode Zen MiMo V2.5 Pro Free (免费)    [opencode/mimo-v2.5-pro-free]"
    echo "  9) DeepSeek Reasoner                         [deepseek/deepseek-reasoner]"
    echo " 10) Moonshot Kimi K2 Thinking                 [moonshotai/kimi-k2-thinking]"
    echo " 11) MiniMax M2.5                              [minimax/MiniMax-M2.5]"
    echo " 12) Xiaomi MiMo V2.5 Pro China                [xiaomi-token-plan-cn/mimo-v2.5-pro]"
    echo " 13) Xiaomi MiMo V2.5 Pro Singapore            [xiaomi-token-plan-sgp/mimo-v2.5-pro]"
    echo " 14) Xiaomi MiMo V2.5 Pro Amsterdam            [xiaomi-token-plan-ams/mimo-v2.5-pro]"
    echo " 15) 手动输入 服务商/模型"
    printf "请选择 [1]: "
  } > /dev/tty

  IFS= read -r choice < /dev/tty || choice=""
  case "$choice" in
    ""|1) MODEL="$DEFAULT_MODEL" ;;
    2) MODEL="openai/gpt-5-codex" ;;
    3) MODEL="openai/gpt-5-chat-latest" ;;
    4) MODEL="opencode/claude-sonnet-4" ;;
    5) MODEL="opencode/big-pickle" ;;
    6) MODEL="opencode/minimax-m2.5-free" ;;
    7) MODEL="opencode/nemotron-3-super-free" ;;
    8) MODEL="opencode/mimo-v2.5-pro-free" ;;
    9) MODEL="deepseek/deepseek-reasoner" ;;
    10) MODEL="moonshotai/kimi-k2-thinking" ;;
    11) MODEL="minimax/MiniMax-M2.5" ;;
    12) MODEL="xiaomi-token-plan-cn/mimo-v2.5-pro" ;;
    13) MODEL="xiaomi-token-plan-sgp/mimo-v2.5-pro" ;;
    14) MODEL="xiaomi-token-plan-ams/mimo-v2.5-pro" ;;
    15)
      printf "请输入模型 (格式为 服务商/模型): " > /dev/tty
      IFS= read -r MODEL < /dev/tty || MODEL=""
      ;;
    *)
      echo "无效的选择: $choice" >&2
      exit 2
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

render_workflow() {
  select_model
  select_api_key_secret
  provider_env_line=$(provider_api_key_env_line)
  load_template | sed \
    -e "s#__RUNNER_LABEL__#$RUNNER_LABEL#g" \
    -e "s#__ACTION_IMAGE__#$ACTION_IMAGE#g" \
    -e "s#__PROVIDER_API_KEY_ENV__#$provider_env_line#g" \
    -e "s#__OPENCODE_MODEL__#$MODEL#g"
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
