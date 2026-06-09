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
$TemplateUrl = $env:OPENCODE_WORKFLOW_TEMPLATE_URL
if ([string]::IsNullOrWhiteSpace($TemplateUrl)) {
  $TemplateUrl = "https://raw.githubusercontent.com/NicoChiGu/gitea-opencode/main/templates/opencode.yml"
}

function Test-GitRepository {
  git rev-parse --is-inside-work-tree *> $null
  return $LASTEXITCODE -eq 0
}

if (-not (Test-GitRepository)) {
  throw "This installer must be run inside a Git repository."
}

$Template = Join-Path $PSScriptRoot "templates/opencode.yml"
$Destination = Join-Path ".gitea" "workflows/opencode.yml"

if ((Test-Path $Destination) -and -not $Force -and -not $DryRun) {
  throw "$Destination already exists. Re-run with -Force to overwrite it."
}

if (Test-Path $Template) {
  $Workflow = Get-Content -Raw -Path $Template
} else {
  $Workflow = Invoke-RestMethod -Uri $TemplateUrl
}

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
