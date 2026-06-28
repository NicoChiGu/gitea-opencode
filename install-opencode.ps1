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
  [string]$CheckoutAction = "actions/checkout@v4",
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

$JsonBase64 = "eyJJbnNpZGVHaXQiOiLmraTlronoo4XnqIvluo/lv4XpobvlnKggR2l0IOS7k+W6k+WGhei/kOihjOOAgiIsIkV4aXN0c05vbkludGVyYWN0aXZlIjoiezB9IOW3suWtmOWcqOOAguWcqOmdnuS6pOS6kuaooeW8j+S4i++8jOivt+S9v+eUqCAtRm9yY2Ug5Y+C5pWw6L+b6KGM6KaG55uW44CCIiwiRGV0ZWN0RXhpc3RzIjoi5qOA5rWL5YiwIHswfSDlt7LlrZjlnKjvvIzmmK/lkKbopobnm5blroPvvJ9beS9OXSIsIkNvbmZpcm1lZE92ZXJ3cml0ZSI6IuW3suehruiupOimhuebluOAgiIsIkNhbmNlbGVkIjoi5pON5L2c5bey5Y+W5raI44CCIiwiU2VsZWN0TW9kZWwiOiLor7fpgInmi6kgT3BlbkNvZGUg5qih5Z6L77yaIiwiTW9kZWxSZWMiOiIgIDEpIEFudGhyb3BpYyBDbGF1ZGUgU29ubmV0IDQuNiAo5o6o6I2QKSAgICAgICAgW3swfV0iLCJNb2RlbFBpY2tsZSI6IiAgNSkgT3BlbkNvZGUgWmVuIEJpZyBQaWNrbGUgKOWFjei0uSkgICAgICAgICAgICBbb3BlbmNvZGUvYmlnLXBpY2tsZV0iLCJNb2RlbE1pbmltYXhGcmVlIjoiICA2KSBPcGVuQ29kZSBaZW4gTWluaU1heCBNMi41IEZyZWUgKOWFjei0uSkgICAgIFtvcGVuY29kZS9taW5pbWF4LW0yLjUtZnJlZV0iLCJNb2RlbE5lbW90cm9uRnJlZSI6IiAgNykgT3BlbkNvZGUgWmVuIE5lbW90cm9uIDMgU3VwZXIgRnJlZSAo5YWN6LS5KSBbb3BlbmNvZGUvbmVtb3Ryb24tMy1zdXBlci1mcmVlXSIsIk1vZGVsTWltb0ZyZWUiOiIgIDgpIE9wZW5Db2RlIFplbiBNaU1vIFYyLjUgUHJvIEZyZWUgKOWFjei0uSkgICAgW29wZW5jb2RlL21pbW8tdjIuNS1wcm8tZnJlZV0iLCJNb2RlbE1hbnVhbCI6IiAxNSkg5omL5Yqo6L6T5YWlIOacjeWKoeWVhi/mqKHlnosiLCJJbnB1dENoZWNrb3V0Ijoi6K+36L6T5YWlIENoZWNrb3V0IEFjdGlvbiBb6buY6K6kOiB7MH1dIiwiQ2hvaWNlIjoi6K+36YCJ5oupIFsxXSIsIklucHV0TW9kZWwiOiLor7fovpPlhaXmqKHlnosgKOagvOW8j+S4uiDmnI3liqHllYYv5qih5Z6LKSIsIkludmFsaWRDaG9pY2UiOiLml6DmlYjnmoTpgInmi6k6IHswfSIsIkludmFsaWRNb2RlbEZvcm1hdCI6IuaooeWei+agvOW8j+W/hemhu+S4uiAn5pyN5Yqh5ZWGL+aooeWeiyfvvIzlvZPliY3ovpPlhaXkuLrvvJp7MH0iLCJVbmtub3duUHJvdmlkZXIiOiLmnKrnn6XnmoTmnI3liqHllYYgJ3swfSfjgILor7fph43mlrDov5DooYzlubbkvb/nlKggLUFwaUtleVNlY3JldCA8U0VDUkVUX05BTUU+IOWPguaVsOOAgiIsIklucHV0U2VjcmV0Ijoi6K+36L6T5YWl5pyN5Yqh5ZWGICd7MH0nIOeahCBHaXRlYSBBY3Rpb25zIOWvhumSpeWQjeensCIsIkludmFsaWRTZWNyZXQiOiLml6DmlYjnmoTlr4bpkqXlkI3np7AgJ3swfSfjgILku4XlhYHorrjkvb/nlKjlrZfmr43jgIHmlbDlrZflkozkuIvliJLnur/vvIzkuJTkuI3og73ku6XmlbDlrZflvIDlpLTvvIzkuZ/kuI3og73ku6UgR0lUSFVCXyDmiJYgR0lURUFfIOW8gOWktOOAgiIsIldvcmtmbG93Q29uZmlndXJlZCI6Ik9wZW5Db2RlIOW3peS9nOa1gemFjee9ruWujOaIkOOAgiIsIlJ1bm5lckxhYmVsIjoiUnVubmVyIOagh+etvjogezB9IiwiQWN0aW9uSW1hZ2UiOiJBY3Rpb24g6ZWc5YOPOiB7MH0iLCJTZWxlY3RlZE1vZGVsIjoi5bey6YCJ5qih5Z6LOiB7MH0iLCJBZGRTZWNyZXRUaXAiOiLor7flnKggR2l0ZWEgQWN0aW9ucyDkuK3kuLrmiYDpgInmnI3liqHllYbmt7vliqDku6XkuIvlr4bpkqU6IiwiU2VjcmV0Rm9ybWF0IjoiICB7MH09POaCqOeahCBBUEkg5a+G6ZKlPiIsIlRva2VuT3ZlcnJpZGUiOiLnlKjkuo4gR2l0ZWEg5YaZ5YWl55qE5Y+v6YCJIFRva2VuIOimhuebljoiLCJUb2tlbkZvcm1hdCI6IiAgT1BFTkNPREVfR0lURUFfVE9LRU49PEdpdGVhIOS4quS6uuiuv+mXruS7pOeJjD4iLCJXcm90ZURlc3RpbmF0aW9uIjoi5bey5YaZ5YWlIHswfSIsIk5vQ2hhbmdlcyI6IuayoeacieimgeaPkOS6pOeahOW3peS9nOa1geabtOaUueOAgiIsIkRldGFjaGVkSGVhZCI6IuaXoOazleS7juWIhuemu+eahCBIRUFEIOWIhuaUr+i/m+ihjOaOqOmAgeOAguivt+mHjeaWsOi/kOihjOW5tuS9v+eUqCAtTm9QdXNoIOWPguaVsO+8jOaIluetvuWHuuWIsOS4gOS4quWIhuaUr+OAgiJ9"
$JsonBytes = [System.Convert]::FromBase64String($JsonBase64)
$JsonText = [System.Text.Encoding]::UTF8.GetString($JsonBytes)
$S = ConvertFrom-Json $JsonText

function Test-GitRepository {
  git rev-parse --is-inside-work-tree *> $null
  return $LASTEXITCODE -eq 0
}

if (-not (Test-GitRepository)) {
  throw $S.InsideGit
}

$ScriptRoot = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($ScriptRoot)) {
  $ScriptRoot = "."
}
$Template = Join-Path $ScriptRoot "templates/opencode.yml"
$Destination = Join-Path ".gitea" "workflows/opencode.yml"

if ((Test-Path $Destination) -and -not $Force -and -not $DryRun) {
  if ($Yes -or $NonInteractive -or [Console]::IsInputRedirected) {
    throw ($S.ExistsNonInteractive -f $Destination)
  } else {
    Write-Host ""
    $PromptChoice = Read-Host ($S.DetectExists -f $Destination)
    if ($PromptChoice -match "^[yY](es)?$") {
      Write-Host $S.ConfirmedOverwrite
    } else {
      Write-Host $S.Canceled
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
  Write-Host $S.SelectModel
  Write-Host ($S.ModelRec -f $DefaultModel)
  Write-Host "  2) OpenAI GPT-5 Codex                        [openai/gpt-5-codex]"
  Write-Host "  3) OpenAI ChatGPT latest                     [openai/gpt-5-chat-latest]"
  Write-Host "  4) OpenCode Zen Claude Sonnet 4              [opencode/claude-sonnet-4]"
  Write-Host $S.ModelPickle
  Write-Host $S.ModelMinimaxFree
  Write-Host $S.ModelNemotronFree
  Write-Host $S.ModelMimoFree
  Write-Host "  9) DeepSeek Reasoner                         [deepseek/deepseek-reasoner]"
  Write-Host " 10) Moonshot Kimi K2 Thinking                 [moonshotai/kimi-k2-thinking]"
  Write-Host " 11) MiniMax M2.5                              [minimax/MiniMax-M2.5]"
  Write-Host " 12) Xiaomi MiMo V2.5 Pro China                [xiaomi-token-plan-cn/mimo-v2.5-pro]"
  Write-Host " 13) Xiaomi MiMo V2.5 Pro Singapore            [xiaomi-token-plan-sgp/mimo-v2.5-pro]"
  Write-Host " 14) Xiaomi MiMo V2.5 Pro Amsterdam            [xiaomi-token-plan-ams/mimo-v2.5-pro]"
  Write-Host $S.ModelManual
  $Choice = Read-Host $S.Choice

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
    "15" { $Selected = Read-Host $S.InputModel }
    default { throw ($S.InvalidChoice -f $Choice) }
  }

  if ($Selected -notmatch "^[^/]+/.+$") {
    throw ($S.InvalidModelFormat -f $Selected)
  }

  return $Selected
}

$SelectedModel = Select-OpenCodeModel

if ($SelectedModel -notmatch "^[^/]+/.+$") {
  throw ($S.InvalidModelFormat -f $SelectedModel)
}

function Select-CheckoutAction {
  if ($Yes -or $NonInteractive -or [Console]::IsInputRedirected) {
    return $CheckoutAction
  }
  Write-Host ""
  $InputVal = Read-Host ($S.InputCheckout -f $CheckoutAction)
  if ([string]::IsNullOrWhiteSpace($InputVal)) {
    return $CheckoutAction
  }
  return $InputVal
}

$SelectedCheckoutAction = Select-CheckoutAction

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
        throw ($S.UnknownProvider -f $Provider)
      }
      return Read-Host ($S.InputSecret -f $Provider)
    }
  }
}

function Assert-ValidSecretName([string]$Name) {
  if ([string]::IsNullOrWhiteSpace($Name) -or $Name -notmatch "^[A-Za-z_][A-Za-z0-9_]*$" -or $Name.StartsWith("GITHUB_") -or $Name.StartsWith("GITEA_")) {
    throw ($S.InvalidSecret -f $Name)
  }
}

function Write-NextSteps([string]$SelectedModel, [string]$SelectedSecret) {
  [Console]::Error.WriteLine("")
  [Console]::Error.WriteLine($S.WorkflowConfigured)
  [Console]::Error.WriteLine(($S.RunnerLabel -f $RunnerLabel))
  [Console]::Error.WriteLine(($S.ActionImage -f $ActionImage))
  [Console]::Error.WriteLine(($S.SelectedModel -f $SelectedModel))
  [Console]::Error.WriteLine($S.AddSecretTip)
  [Console]::Error.WriteLine(($S.SecretFormat -f $SelectedSecret))
  [Console]::Error.WriteLine($S.TokenOverride)
  [Console]::Error.WriteLine($S.TokenFormat)
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
if ($Workflow.Contains("__CHECKOUT_ACTION__")) {
  $Workflow = $Workflow.Replace("__CHECKOUT_ACTION__", $SelectedCheckoutAction)
} else {
  $Workflow = $Workflow.Replace("https://github.com/actions/checkout@v4", $SelectedCheckoutAction)
}

if ($DryRun) {
  Write-Output $Workflow
  Write-NextSteps $SelectedModel $SelectedApiKeySecret
  exit 0
}

New-Item -ItemType Directory -Force -Path (Split-Path $Destination) | Out-Null
Set-Content -Path $Destination -Value $Workflow -NoNewline
Write-Output ($S.WroteDestination -f $Destination)

if ($NoCommit) {
  Write-NextSteps $SelectedModel $SelectedApiKeySecret
  exit 0
}

git add $Destination
git diff --cached --quiet -- $Destination
if ($LASTEXITCODE -ne 0) {
  git commit -m $CommitMessage
} else {
  Write-Output $S.NoChanges
}

if ($NoPush) {
  Write-NextSteps $SelectedModel $SelectedApiKeySecret
  exit 0
}

$Branch = (git rev-parse --abbrev-ref HEAD).Trim()
if ($Branch -eq "HEAD") {
  throw $S.DetachedHead
}

git push origin $Branch
Write-NextSteps $SelectedModel $SelectedApiKeySecret
