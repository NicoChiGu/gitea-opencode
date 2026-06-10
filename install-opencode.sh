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
Usage: ./install-opencode.sh [options]

Options:
  --force                 Overwrite an existing .gitea/workflows/opencode.yml
  --dry-run               Print the workflow instead of writing files
  --no-commit             Write the workflow but do not commit it
  --no-push               Commit the workflow but do not push it
  --runner-label <label>  Gitea runner label, default: ubuntu-22.04
  --action-image <image>  Docker image used by the OpenCode action step
  --model <model>         OpenCode model in provider/model format
  --api-key-secret <name> Gitea Actions secret name for the selected provider
  --yes, --non-interactive
                          Skip prompts and use defaults
  --help                  Show this help
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
    --action-image)
      ACTION_IMAGE="${2:-}"
      [ -n "$ACTION_IMAGE" ] || { echo "--action-image requires a value" >&2; exit 2; }
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
  echo "This installer must be run inside a Git repository." >&2
  exit 1
fi

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
TEMPLATE="$SCRIPT_DIR/templates/opencode.yml"
DEST=".gitea/workflows/opencode.yml"

if [ -f "$DEST" ] && [ "$FORCE" -ne 1 ] && [ "$DRY_RUN" -ne 1 ]; then
  echo "$DEST already exists. Re-run with --force to overwrite it." >&2
  exit 1
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

  if [ "$NON_INTERACTIVE" -eq 1 ] || [ ! -r /dev/tty ] || [ ! -w /dev/tty ]; then
    MODEL="$DEFAULT_MODEL"
    return
  fi

  {
    echo
    echo "Select OpenCode model:"
    echo "  1) Anthropic Claude Sonnet 4.6 (recommended)  [$DEFAULT_MODEL]"
    echo "  2) OpenAI GPT-5 Codex                         [openai/gpt-5-codex]"
    echo "  3) OpenAI ChatGPT latest                      [openai/gpt-5-chat-latest]"
    echo "  4) OpenCode Zen Claude Sonnet 4               [opencode/claude-sonnet-4]"
    echo "  5) Xiaomi MiMo V2.5 Pro China                 [xiaomi-token-plan-cn/mimo-v2.5-pro]"
    echo "  6) Xiaomi MiMo V2.5 Pro Singapore             [xiaomi-token-plan-sgp/mimo-v2.5-pro]"
    echo "  7) Xiaomi MiMo V2.5 Pro Amsterdam             [xiaomi-token-plan-ams/mimo-v2.5-pro]"
    echo "  8) DeepSeek Reasoner                          [deepseek/deepseek-reasoner]"
    echo "  9) Moonshot Kimi K2 Thinking                  [moonshotai/kimi-k2-thinking]"
    echo " 10) MiniMax M2.5                               [minimax/MiniMax-M2.5]"
    echo " 11) Manual provider/model"
    printf "Choice [1]: "
  } > /dev/tty

  IFS= read -r choice < /dev/tty || choice=""
  case "$choice" in
    ""|1) MODEL="$DEFAULT_MODEL" ;;
    2) MODEL="openai/gpt-5-codex" ;;
    3) MODEL="openai/gpt-5-chat-latest" ;;
    4) MODEL="opencode/claude-sonnet-4" ;;
    5) MODEL="xiaomi-token-plan-cn/mimo-v2.5-pro" ;;
    6) MODEL="xiaomi-token-plan-sgp/mimo-v2.5-pro" ;;
    7) MODEL="xiaomi-token-plan-ams/mimo-v2.5-pro" ;;
    8) MODEL="deepseek/deepseek-reasoner" ;;
    9) MODEL="moonshotai/kimi-k2-thinking" ;;
    10) MODEL="minimax/MiniMax-M2.5" ;;
    11)
      printf "Enter model (provider/model): " > /dev/tty
      IFS= read -r MODEL < /dev/tty || MODEL=""
      ;;
    *)
      echo "Invalid choice: $choice" >&2
      exit 2
      ;;
  esac

  validate_model
}

validate_model() {
  case "$MODEL" in
    */*) ;;
    *)
      echo "Model must use provider/model format, got: $MODEL" >&2
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
      if [ "$NON_INTERACTIVE" -eq 1 ] || [ ! -r /dev/tty ] || [ ! -w /dev/tty ]; then
        echo "Unknown provider '$provider'. Re-run with --api-key-secret <SECRET_NAME>." >&2
        exit 2
      fi
      printf "Enter Gitea Actions secret name for provider '%s': " "$provider" > /dev/tty
      IFS= read -r API_KEY_SECRET < /dev/tty || API_KEY_SECRET=""
      ;;
  esac
}

validate_api_key_secret() {
  case "$API_KEY_SECRET" in
    ""|[0-9]*|GITHUB_*|GITEA_*|*[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_]*)
      echo "Invalid secret name: $API_KEY_SECRET" >&2
      echo "Use only letters, numbers, and underscores; do not start with a number, GITHUB_, or GITEA_." >&2
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
    echo "OpenCode workflow configured."
    echo "Runner label: $RUNNER_LABEL"
    echo "Action image: $ACTION_IMAGE"
    echo "Selected model: $MODEL"
    echo "Add this Gitea Actions secret for the selected provider:"
    echo "  $API_KEY_SECRET=<your api key>"
    echo "Optional token override for Gitea writes:"
    echo "  OPENCODE_GITEA_TOKEN=<gitea personal access token>"
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
echo "Wrote $DEST"

if [ "$NO_COMMIT" -eq 1 ]; then
  print_next_steps
  exit 0
fi

git add "$DEST"
if git diff --cached --quiet -- "$DEST"; then
  echo "No workflow changes to commit."
else
  git commit -m "$COMMIT_MESSAGE"
fi

if [ "$NO_PUSH" -eq 1 ]; then
  print_next_steps
  exit 0
fi

BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [ "$BRANCH" = "HEAD" ]; then
  echo "Cannot push from a detached HEAD. Re-run with --no-push or checkout a branch." >&2
  exit 1
fi

git push origin "$BRANCH"
print_next_steps
