# Gitea OpenCode

在 Gitea Actions 中运行 OpenCode，让 Issue 和 PR 评论可以触发代码审查、解释、修复、提交和创建 PR。

当前安装源：

```text
https://github.com/NicoChiGu/gitea-opencode
```

## 一键安装到目标仓库

在你要启用 OpenCode 的 Gitea 项目根目录运行下面命令。安装器会进入终端引导，让你选择 OpenCode 模型，然后创建 `.gitea/workflows/opencode.yml`，默认提交并推送当前分支。

Linux / macOS:

```sh
curl -fsSL https://raw.githubusercontent.com/NicoChiGu/gitea-opencode/main/install-opencode.sh | bash
```

Windows PowerShell:

```powershell
irm https://raw.githubusercontent.com/NicoChiGu/gitea-opencode/main/install-opencode.ps1 | iex
```

只生成 workflow，不提交、不推送：

```sh
curl -fsSL https://raw.githubusercontent.com/NicoChiGu/gitea-opencode/main/install-opencode.sh | bash -s -- --no-commit
```

PowerShell 带参数：

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/NicoChiGu/gitea-opencode/main/install-opencode.ps1))) -NoCommit
```

覆盖已有 `.gitea/workflows/opencode.yml`：

```sh
curl -fsSL https://raw.githubusercontent.com/NicoChiGu/gitea-opencode/main/install-opencode.sh | bash -s -- --force
```

跳过引导，直接使用默认模型：

```sh
curl -fsSL https://raw.githubusercontent.com/NicoChiGu/gitea-opencode/main/install-opencode.sh | bash -s -- --yes
```

自定义标准 runner label、Docker Action 镜像和模型：

```sh
curl -fsSL https://raw.githubusercontent.com/NicoChiGu/gitea-opencode/main/install-opencode.sh | bash -s -- \
  --runner-label ubuntu-22.04 \
  --action-image registry.cn-hangzhou.aliyuncs.com/terata/gitea-opencode:latest \
  --model openai/gpt-5-codex
```

模型必须使用 OpenCode 的 `provider/model` 格式。完整 provider 和 model 以 OpenCode/Models.dev 为准；安装器只是提供常用选项，也支持手动输入。

如果手动输入的 provider 不在安装器内置映射中，可以指定 API key 对应的 Gitea Actions Secret 名称：

```sh
curl -fsSL https://raw.githubusercontent.com/NicoChiGu/gitea-opencode/main/install-opencode.sh | bash -s -- \
  --model my-provider/my-model \
  --api-key-secret MY_PROVIDER_API_KEY
```

安装器要求当前目录是 Git 仓库。默认 commit message 是：

```text
chore: add gitea opencode workflow
```

## 安装器参数

Linux / macOS:

```text
--force                 覆盖已有 .gitea/workflows/opencode.yml
--dry-run               只输出 workflow，不写文件
--no-commit             写入 workflow，但不提交
--no-push               提交 workflow，但不推送
--runner-label <label>  Gitea runner label，默认 ubuntu-22.04
--action-image <image>  OpenCode Docker Action 镜像
--container-image <image>
                        --action-image 的兼容别名
--model <model>         OpenCode 模型，格式 provider/model
--api-key-secret <name> provider API key 对应的 Gitea Actions Secret 名称
--yes, --non-interactive
                        跳过引导并使用默认模型
```

PowerShell 对应参数：

```text
-Force
-DryRun
-NoCommit
-NoPush
-RunnerLabel <label>
-ActionImage <image>
-ContainerImage <image>
-Model <model>
-ApiKeySecret <name>
-Yes
-NonInteractive
```

如果你需要从其他分支或镜像读取 workflow 模板，可以设置：

```sh
OPENCODE_WORKFLOW_TEMPLATE_URL=https://raw.githubusercontent.com/NicoChiGu/gitea-opencode/main/templates/opencode.yml
```

## 标准 Gitea Runner

生成的 workflow 默认使用：

```yaml
runs-on: ubuntu-22.04
```

OpenCode 适配器通过 Docker Action step 运行：

```yaml
uses: docker://registry.cn-hangzhou.aliyuncs.com/terata/gitea-opencode:latest
```

因此你不需要给 act_runner 新增 `opencode:docker://...` label，也不需要额外编排 runner。只要你的在线 runner 已经有 `ubuntu-22.04`、`ubuntu-24.04` 或 `ubuntu-latest` 这类标准 label 即可。

完整生成效果类似：

```yaml
jobs:
  opencode:
    runs-on: ubuntu-22.04
    steps:
      - uses: https://github.com/actions/checkout@v4
      - uses: docker://registry.cn-hangzhou.aliyuncs.com/terata/gitea-opencode:latest
```

如果你的 runner 只有其他 label，安装时指定：

```sh
curl -fsSL https://raw.githubusercontent.com/NicoChiGu/gitea-opencode/main/install-opencode.sh | bash -s -- \
  --runner-label ubuntu-latest
```

如果这是私有镜像，先在 runner 所在机器登录阿里云镜像仓库：

```sh
docker login registry.cn-hangzhou.aliyuncs.com
```

如果 act_runner 是容器化运行，并且通过宿主机 Docker socket 拉取 action 镜像，需要确保 act_runner 能读取对应 Docker 登录凭据。

## 故障排查

### 没有匹配的 `ubuntu-22.04` 在线运行器

如果你的 Gitea 提示没有匹配的 `ubuntu-22.04` 在线运行器，先确认当前 runner UI 中真实存在的标签，然后用安装器指定它。例如只有 `ubuntu-latest` 时：

```sh
curl -fsSL https://raw.githubusercontent.com/NicoChiGu/gitea-opencode/main/install-opencode.sh | bash -s -- \
  --force \
  --runner-label ubuntu-latest
```

不要使用 job container 版本：

```yaml
container:
  image: registry.cn-hangzhou.aliyuncs.com/terata/gitea-opencode:latest
```

这个模式在部分 Gitea/act_runner 组合中会导致调度阶段找不到标准 runner。当前模板使用的是已验证可调度的 Docker Action step：

```yaml
uses: docker://registry.cn-hangzhou.aliyuncs.com/terata/gitea-opencode:latest
```

### `gitea-opencode: command not found`

新版 workflow 不会在宿主 runner 里执行 `gitea-opencode`，而是通过 Docker Action 镜像运行。如果你仍然看到 `gitea-opencode: command not found`，说明目标仓库里的 `.gitea/workflows/opencode.yml` 还是旧版本。

重新构建并推送镜像：

```sh
docker build -t registry.cn-hangzhou.aliyuncs.com/terata/gitea-opencode:latest .
docker push registry.cn-hangzhou.aliyuncs.com/terata/gitea-opencode:latest
```

然后覆盖 workflow：

```sh
curl -fsSL https://raw.githubusercontent.com/NicoChiGu/gitea-opencode/main/install-opencode.sh | bash -s -- --force
```

覆盖后确认 workflow 中是：

```yaml
uses: docker://registry.cn-hangzhou.aliyuncs.com/terata/gitea-opencode:latest
```

`gitea-opencode` 是本项目镜像里的适配器脚本，负责：

- 读取 `GITHUB_EVENT_PATH` 中的 Gitea 事件。
- 判断评论里是否有 `/opencode` 或 `/oc`。
- 调用 OpenCode CLI。
- 使用 Gitea API 回复 Issue/PR 评论。
- 在 `fix` 类指令下创建分支、提交代码并创建 PR。

## 必要 Secrets

根据安装时选择的模型，在目标 Gitea 仓库或组织的 Actions Secrets 中配置对应 provider 的 API key。安装器只会把当前模型需要的 secret 写入 `.gitea/workflows/opencode.yml`，不会把所有 provider secret 都写进去。

常用映射：

```text
ANTHROPIC_API_KEY       Anthropic: anthropic/claude-sonnet-4-6
OPENAI_API_KEY          OpenAI: openai/gpt-5-codex, openai/gpt-5-chat-latest
OPENCODE_API_KEY        OpenCode Zen: opencode/claude-sonnet-4
XIAOMI_API_KEY          Xiaomi MiMo: xiaomi-token-plan-cn/mimo-v2.5-pro 等
DEEPSEEK_API_KEY        DeepSeek: deepseek/deepseek-reasoner
MOONSHOT_API_KEY        Moonshot/Kimi: moonshotai/kimi-k2-thinking
MINIMAX_API_KEY         MiniMax: minimax/MiniMax-M2.5
OPENROUTER_API_KEY      OpenRouter: openrouter/<model>
```

安装器完成后也会输出最终提示，例如：

```text
Selected model: xiaomi-token-plan-cn/mimo-v2.5-pro
Add this Gitea Actions secret for the selected provider:
  XIAOMI_API_KEY=<your api key>
```

可选：

```text
OPENCODE_GITEA_TOKEN
```

默认使用 Gitea Actions 内置的 `${{ secrets.GITEA_TOKEN }}`。如果你的 Gitea 实例限制了内置 token 的写权限，可以创建 Personal Access Token，并保存为 `OPENCODE_GITEA_TOKEN`。

workflow 会请求这些权限：

```yaml
permissions:
  contents: write
  code: write
  issues: write
  pull-requests: write
```

如果仓库或组织的 Actions 权限上限更低，Gitea 会按上限收紧权限。

## 支持的触发方式

Issue 评论：

```text
/opencode explain this issue
/opencode fix this
/oc fix this bug
```

PR 评论：

```text
Delete the attachment from S3 when the note is removed /oc
/oc add error handling here
```

PR 文件行评论：

```text
/oc add error handling here
```

PR 自动审查：

```text
pull_request opened / reopened / synchronized
```

手动触发：

```text
workflow_dispatch
```

## 行为说明

- `/opencode` 或 `/oc` 普通触发只做审查/解释，不默认改代码。
- 包含 `fix`、`add`、`update`、`delete`、`implement` 等意图时，才进入代码变更流程。
- Issue 修复会创建 `opencode/issue-<number>-<run_id>` 分支，提交修改并创建 PR。
- PR 评论修复会提交到同一个 PR 分支。
- 评论者没有写权限时，OpenCode 会回复跳过说明，不会提交代码。
- 跨仓库 PR 默认只审查，不向外部仓库推送。

## 本地开发

运行测试：

```sh
npm test
```

查看 CLI：

```sh
node bin/gitea-opencode.mjs --help
```
