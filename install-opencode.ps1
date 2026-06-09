param(
  [switch]$Force,
  [switch]$DryRun,
  [switch]$NoCommit,
  [switch]$NoPush,
  [string]$RunnerLabel = "opencode",
  [string]$Model = "anthropic/claude-sonnet-4-20250514"
)

$ErrorActionPreference = "Stop"
$CommitMessage = "chore: add gitea opencode workflow"

function Test-GitRepository {
  git rev-parse --is-inside-work-tree *> $null
  return $LASTEXITCODE -eq 0
}

if (-not (Test-GitRepository)) {
  throw "This installer must be run inside a Git repository."
}

$Template = Join-Path $PSScriptRoot "templates/opencode.yml"
$Destination = Join-Path ".gitea" "workflows/opencode.yml"

if (-not (Test-Path $Template)) {
  throw "Workflow template not found: $Template"
}

if ((Test-Path $Destination) -and -not $Force -and -not $DryRun) {
  throw "$Destination already exists. Re-run with -Force to overwrite it."
}

$Workflow = Get-Content -Raw -Path $Template
$Workflow = $Workflow.Replace("__RUNNER_LABEL__", $RunnerLabel)
$Workflow = $Workflow.Replace("__OPENCODE_MODEL__", $Model)

if ($DryRun) {
  Write-Output $Workflow
  exit 0
}

New-Item -ItemType Directory -Force -Path (Split-Path $Destination) | Out-Null
Set-Content -Path $Destination -Value $Workflow -NoNewline
Write-Output "Wrote $Destination"

if ($NoCommit) {
  exit 0
}

git add $Destination
git diff --cached --quiet -- $Destination
if ($LASTEXITCODE -ne 0) {
  git commit -m $CommitMessage
} else {
  Write-Output "No workflow changes to commit."
}

if ($NoPush) {
  exit 0
}

$Branch = (git rev-parse --abbrev-ref HEAD).Trim()
if ($Branch -eq "HEAD") {
  throw "Cannot push from a detached HEAD. Re-run with -NoPush or checkout a branch."
}

git push origin $Branch
