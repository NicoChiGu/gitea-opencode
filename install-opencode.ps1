param(
  [switch]$Force,
  [switch]$DryRun,
  [switch]$NoCommit,
  [switch]$NoPush,
  [string]$RunnerLabel = "opencode",
  [string]$Model = "",
  [switch]$Yes,
  [switch]$NonInteractive
)

$ErrorActionPreference = "Stop"
$CommitMessage = "chore: add gitea opencode workflow"
$DefaultModel = "anthropic/claude-sonnet-4-6"
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

function Select-OpenCodeModel {
  if (-not [string]::IsNullOrWhiteSpace($Model)) {
    return $Model
  }

  if ($Yes -or $NonInteractive -or [Console]::IsInputRedirected) {
    return $DefaultModel
  }

  Write-Host ""
  Write-Host "Select OpenCode model:"
  Write-Host "  1) Anthropic Claude Sonnet 4.6 (recommended)  [$DefaultModel]"
  Write-Host "  2) OpenAI GPT-5 Codex                         [openai/gpt-5-codex]"
  Write-Host "  3) OpenAI ChatGPT latest                      [openai/gpt-5-chat-latest]"
  Write-Host "  4) OpenCode Zen Claude Sonnet 4               [opencode/claude-sonnet-4]"
  Write-Host "  5) Xiaomi MiMo V2.5 Pro China                 [xiaomi-token-plan-cn/mimo-v2.5-pro]"
  Write-Host "  6) Xiaomi MiMo V2.5 Pro Singapore             [xiaomi-token-plan-sgp/mimo-v2.5-pro]"
  Write-Host "  7) Xiaomi MiMo V2.5 Pro Amsterdam             [xiaomi-token-plan-ams/mimo-v2.5-pro]"
  Write-Host "  8) DeepSeek Reasoner                          [deepseek/deepseek-reasoner]"
  Write-Host "  9) Moonshot Kimi K2 Thinking                  [moonshotai/kimi-k2-thinking]"
  Write-Host " 10) MiniMax M2.5                               [minimax/MiniMax-M2.5]"
  Write-Host " 11) Manual provider/model"
  $Choice = Read-Host "Choice [1]"

  switch ($Choice) {
    "" { $Selected = $DefaultModel }
    "1" { $Selected = $DefaultModel }
    "2" { $Selected = "openai/gpt-5-codex" }
    "3" { $Selected = "openai/gpt-5-chat-latest" }
    "4" { $Selected = "opencode/claude-sonnet-4" }
    "5" { $Selected = "xiaomi-token-plan-cn/mimo-v2.5-pro" }
    "6" { $Selected = "xiaomi-token-plan-sgp/mimo-v2.5-pro" }
    "7" { $Selected = "xiaomi-token-plan-ams/mimo-v2.5-pro" }
    "8" { $Selected = "deepseek/deepseek-reasoner" }
    "9" { $Selected = "moonshotai/kimi-k2-thinking" }
    "10" { $Selected = "minimax/MiniMax-M2.5" }
    "11" { $Selected = Read-Host "Enter model (provider/model)" }
    default { throw "Invalid choice: $Choice" }
  }

  if ($Selected -notmatch "^[^/]+/.+$") {
    throw "Model must use provider/model format, got: $Selected"
  }

  return $Selected
}

$SelectedModel = Select-OpenCodeModel

if (Test-Path $Template) {
  $Workflow = Get-Content -Raw -Path $Template
} else {
  $Workflow = Invoke-RestMethod -Uri $TemplateUrl
}

$Workflow = $Workflow.Replace("__RUNNER_LABEL__", $RunnerLabel)
$Workflow = $Workflow.Replace("__OPENCODE_MODEL__", $SelectedModel)

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
