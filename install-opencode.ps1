param(
  [switch]$Force,
  [switch]$DryRun,
  [switch]$NoCommit,
  [switch]$NoPush,
  [string]$RunnerLabel = "ubuntu-22.04",
  [string]$ActionImage = "registry.cn-hangzhou.aliyuncs.com/terata/gitea-opencode:latest",
  [string]$ContainerImage = "",
  [string]$Model = "",
  [string]$ApiKeySecret = "",
  [switch]$Yes,
  [switch]$NonInteractive
)

$ErrorActionPreference = "Stop"
$CommitMessage = "chore: add gitea opencode workflow"
$DefaultModel = "anthropic/claude-sonnet-4-6"
if (-not [string]::IsNullOrWhiteSpace($ContainerImage)) {
  $ActionImage = $ContainerImage
}
$TemplateUrl = $env:OPENCODE_WORKFLOW_TEMPLATE_URL
if ([string]::IsNullOrWhiteSpace($TemplateUrl)) {
  $TemplateUrl = "https://raw.githubusercontent.com/NicoChiGu/gitea-opencode/main/templates/opencode.yml"
}

function Test-GitRepository {
  git rev-parse --is-inside-work-tree *> $null
  return $LASTEXITCODE -eq 0
}

if (-not (Test-GitRepository)) {
  throw "此安装程序必须在 Git 仓库内运行。"
}

$Template = Join-Path $PSScriptRoot "templates/opencode.yml"
$Destination = Join-Path ".gitea" "workflows/opencode.yml"

if ((Test-Path $Destination) -and -not $Force -and -not $DryRun) {
  if ($Yes -or $NonInteractive -or [Console]::IsInputRedirected) {
    throw "$Destination 已存在。在非交互模式下，请使用 -Force 参数进行覆盖。"
  } else {
    Write-Host ""
    $PromptChoice = Read-Host "检测到 $Destination 已存在，是否覆盖它？[y/N]"
    if ($PromptChoice -match "^[yY](es)?$") {
      Write-Host "已确认覆盖。"
    } else {
      Write-Host "操作已取消。"
      exit 0
    }
  }
}

function Select-OpenCodeModel {
  if (-not [string]::IsNullOrWhiteSpace($Model)) {
    return $Model
  }

  if ($Yes -or $NonInteractive -or [Console]::IsInputRedirected) {
    return $DefaultModel
  }

  Write-Host ""
  Write-Host "请选择 OpenCode 模型："
  Write-Host "  1) Anthropic Claude Sonnet 4.6 (推荐)        [$DefaultModel]"
  Write-Host "  2) OpenAI GPT-5 Codex                        [openai/gpt-5-codex]"
  Write-Host "  3) OpenAI ChatGPT latest                     [openai/gpt-5-chat-latest]"
  Write-Host "  4) OpenCode Zen Claude Sonnet 4              [opencode/claude-sonnet-4]"
  Write-Host "  5) OpenCode Zen Big Pickle (免费)            [opencode/big-pickle]"
  Write-Host "  6) OpenCode Zen MiniMax M2.5 Free (免费)     [opencode/minimax-m2.5-free]"
  Write-Host "  7) OpenCode Zen Nemotron 3 Super Free (免费) [opencode/nemotron-3-super-free]"
  Write-Host "  8) OpenCode Zen MiMo V2.5 Pro Free (免费)    [opencode/mimo-v2.5-pro-free]"
  Write-Host "  9) DeepSeek Reasoner                         [deepseek/deepseek-reasoner]"
  Write-Host " 10) Moonshot Kimi K2 Thinking                 [moonshotai/kimi-k2-thinking]"
  Write-Host " 11) MiniMax M2.5                              [minimax/MiniMax-M2.5]"
  Write-Host " 12) Xiaomi MiMo V2.5 Pro China                [xiaomi-token-plan-cn/mimo-v2.5-pro]"
  Write-Host " 13) Xiaomi MiMo V2.5 Pro Singapore            [xiaomi-token-plan-sgp/mimo-v2.5-pro]"
  Write-Host " 14) Xiaomi MiMo V2.5 Pro Amsterdam            [xiaomi-token-plan-ams/mimo-v2.5-pro]"
  Write-Host " 15) 手动输入 服务商/模型"
  $Choice = Read-Host "请选择 [1]"

  switch ($Choice) {
    "" { $Selected = $DefaultModel }
    "1" { $Selected = $DefaultModel }
    "2" { $Selected = "openai/gpt-5-codex" }
    "3" { $Selected = "openai/gpt-5-chat-latest" }
    "4" { $Selected = "opencode/claude-sonnet-4" }
    "5" { $Selected = "opencode/big-pickle" }
    "6" { $Selected = "opencode/minimax-m2.5-free" }
    "7" { $Selected = "opencode/nemotron-3-super-free" }
    "8" { $Selected = "opencode/mimo-v2.5-pro-free" }
    "9" { $Selected = "deepseek/deepseek-reasoner" }
    "10" { $Selected = "moonshotai/kimi-k2-thinking" }
    "11" { $Selected = "minimax/MiniMax-M2.5" }
    "12" { $Selected = "xiaomi-token-plan-cn/mimo-v2.5-pro" }
    "13" { $Selected = "xiaomi-token-plan-sgp/mimo-v2.5-pro" }
    "14" { $Selected = "xiaomi-token-plan-ams/mimo-v2.5-pro" }
    "15" { $Selected = Read-Host "请输入模型 (格式为 服务商/模型)" }
    default { throw "无效的选择: $Choice" }
  }

  if ($Selected -notmatch "^[^/]+/.+$") {
    throw "模型格式必须为 '服务商/模型'，当前输入为：$Selected"
  }

  return $Selected
}

$SelectedModel = Select-OpenCodeModel

if ($SelectedModel -notmatch "^[^/]+/.+$") {
  throw "模型格式必须为 '服务商/模型'，当前输入为：$SelectedModel"
}

function Get-ProviderFromModel([string]$Value) {
  return ($Value -split "/", 2)[0]
}

function Get-ApiKeySecretForModel([string]$Value) {
  if (-not [string]::IsNullOrWhiteSpace($ApiKeySecret)) {
    return $ApiKeySecret
  }

  $Provider = Get-ProviderFromModel $Value
  switch ($Provider) {
    "anthropic" { return "ANTHROPIC_API_KEY" }
    "openai" { return "OPENAI_API_KEY" }
    "opencode" { return "OPENCODE_API_KEY" }
    "deepseek" { return "DEEPSEEK_API_KEY" }
    "moonshotai" { return "MOONSHOT_API_KEY" }
    "minimax" { return "MINIMAX_API_KEY" }
    "openrouter" { return "OPENROUTER_API_KEY" }
    "xiaomi-token-plan-cn" { return "XIAOMI_API_KEY" }
    "xiaomi-token-plan-sgp" { return "XIAOMI_API_KEY" }
    "xiaomi-token-plan-ams" { return "XIAOMI_API_KEY" }
    default {
      if ($Yes -or $NonInteractive -or [Console]::IsInputRedirected) {
        throw "未知的服务商 '$Provider'。请重新运行并使用 -ApiKeySecret <SECRET_NAME> 参数。"
      }
      return Read-Host "请输入服务商 '$Provider' 的 Gitea Actions 密钥名称"
    }
  }
}

function Assert-ValidSecretName([string]$Name) {
  if ([string]::IsNullOrWhiteSpace($Name) -or $Name -notmatch "^[A-Za-z_][A-Za-z0-9_]*$" -or $Name.StartsWith("GITHUB_") -or $Name.StartsWith("GITEA_")) {
    throw "无效的密钥名称 '$Name'。仅允许使用字母、数字和下划线，且不能以数字开头，也不能以 GITHUB_ 或 GITEA_ 开头。"
  }
}

function Write-NextSteps([string]$SelectedModel, [string]$SelectedSecret) {
  [Console]::Error.WriteLine("")
  [Console]::Error.WriteLine("OpenCode 工作流配置完成。")
  [Console]::Error.WriteLine("Runner 标签: $RunnerLabel")
  [Console]::Error.WriteLine("Action 镜像: $ActionImage")
  [Console]::Error.WriteLine("已选模型: $SelectedModel")
  [Console]::Error.WriteLine("请在 Gitea Actions 中为所选服务商添加以下密钥:")
  [Console]::Error.WriteLine("  $SelectedSecret=<您的 API 密钥>")
  [Console]::Error.WriteLine("用于 Gitea 写入的可选 Token 覆盖:")
  [Console]::Error.WriteLine("  OPENCODE_GITEA_TOKEN=<Gitea 个人访问令牌>")
}

$SelectedApiKeySecret = Get-ApiKeySecretForModel $SelectedModel
Assert-ValidSecretName $SelectedApiKeySecret
$ProviderApiKeyEnv = "          ${SelectedApiKeySecret}: " + '${{ secrets.' + $SelectedApiKeySecret + ' }}'

if (Test-Path $Template) {
  $Workflow = Get-Content -Raw -Path $Template
} else {
  $Workflow = Invoke-RestMethod -Uri $TemplateUrl
}

$Workflow = $Workflow.Replace("__RUNNER_LABEL__", $RunnerLabel)
$Workflow = $Workflow.Replace("__ACTION_IMAGE__", $ActionImage)
$Workflow = $Workflow.Replace("__PROVIDER_API_KEY_ENV__", $ProviderApiKeyEnv)
$Workflow = $Workflow.Replace("__OPENCODE_MODEL__", $SelectedModel)

if ($DryRun) {
  Write-Output $Workflow
  Write-NextSteps $SelectedModel $SelectedApiKeySecret
  exit 0
}

New-Item -ItemType Directory -Force -Path (Split-Path $Destination) | Out-Null
Set-Content -Path $Destination -Value $Workflow -NoNewline
Write-Output "已写入 $Destination"

if ($NoCommit) {
  Write-NextSteps $SelectedModel $SelectedApiKeySecret
  exit 0
}

git add $Destination
git diff --cached --quiet -- $Destination
if ($LASTEXITCODE -ne 0) {
  git commit -m $CommitMessage
} else {
  Write-Output "没有要提交的工作流更改。"
}

if ($NoPush) {
  Write-NextSteps $SelectedModel $SelectedApiKeySecret
  exit 0
}

$Branch = (git rev-parse --abbrev-ref HEAD).Trim()
if ($Branch -eq "HEAD") {
  throw "无法从分离的 HEAD 分支进行推送。请重新运行并使用 -NoPush 参数，或签出到一个分支。"
}

git push origin $Branch
Write-NextSteps $SelectedModel $SelectedApiKeySecret
