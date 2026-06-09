#!/usr/bin/env sh
set -eu

RUNNER_LABEL="opencode"
MODEL="anthropic/claude-sonnet-4-20250514"
FORCE=0
DRY_RUN=0
NO_COMMIT=0
NO_PUSH=0
COMMIT_MESSAGE="chore: add gitea opencode workflow"

usage() {
  cat <<'EOF'
Usage: ./install-opencode.sh [options]

Options:
  --force                 Overwrite an existing .gitea/workflows/opencode.yml
  --dry-run               Print the workflow instead of writing files
  --no-commit             Write the workflow but do not commit it
  --no-push               Commit the workflow but do not push it
  --runner-label <label>  Gitea runner label, default: opencode
  --model <model>         OpenCode model, default: anthropic/claude-sonnet-4-20250514
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
    --model)
      MODEL="${2:-}"
      [ -n "$MODEL" ] || { echo "--model requires a value" >&2; exit 2; }
      shift 2
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

if [ ! -f "$TEMPLATE" ]; then
  echo "Workflow template not found: $TEMPLATE" >&2
  exit 1
fi

if [ -f "$DEST" ] && [ "$FORCE" -ne 1 ] && [ "$DRY_RUN" -ne 1 ]; then
  echo "$DEST already exists. Re-run with --force to overwrite it." >&2
  exit 1
fi

render_workflow() {
  sed \
    -e "s#__RUNNER_LABEL__#$RUNNER_LABEL#g" \
    -e "s#__OPENCODE_MODEL__#$MODEL#g" \
    "$TEMPLATE"
}

if [ "$DRY_RUN" -eq 1 ]; then
  render_workflow
  exit 0
fi

mkdir -p .gitea/workflows
render_workflow > "$DEST"
echo "Wrote $DEST"

if [ "$NO_COMMIT" -eq 1 ]; then
  exit 0
fi

git add "$DEST"
if git diff --cached --quiet -- "$DEST"; then
  echo "No workflow changes to commit."
else
  git commit -m "$COMMIT_MESSAGE"
fi

if [ "$NO_PUSH" -eq 1 ]; then
  exit 0
fi

BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [ "$BRANCH" = "HEAD" ]; then
  echo "Cannot push from a detached HEAD. Re-run with --no-push or checkout a branch." >&2
  exit 1
fi

git push origin "$BRANCH"
