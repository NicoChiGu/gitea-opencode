# Gitea OpenCode

在 Gitea Actions 中运行 OpenCode，让 Issue 和 PR 评论可以触发代码审查、解释、修复、提交和创建 PR。

当前安装源：

```text
https://github.com/NicoChiGu/gitea-opencode
```

## 一键安装到目标仓库

在你要启用 OpenCode 的 Gitea 项目根目录运行下面命令。安装器会创建 `.gitea/workflows/opencode.yml`，默认提交并推送当前分支。

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

自定义 runner label 和模型：

```sh
curl -fsSL https://raw.githubusercontent.com/NicoChiGu/gitea-opencode/main/install-opencode.sh | bash -s -- \
  --runner-label opencode \
  --model anthropic/claude-sonnet-4-20250514
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
--runner-label <label>  Gitea runner label，默认 opencode
--model <model>         OpenCode 模型，默认 anthropic/claude-sonnet-4-20250514
```

PowerShell 对应参数：

```text
-Force
-DryRun
-NoCommit
-NoPush
-RunnerLabel <label>
-Model <model>
```

如果你需要从其他分支或镜像读取 workflow 模板，可以设置：

```sh
OPENCODE_WORKFLOW_TEMPLATE_URL=https://raw.githubusercontent.com/NicoChiGu/gitea-opencode/main/templates/opencode.yml
```

## Gitea Runner

生成的 workflow 默认使用：

```yaml
runs-on: opencode
```

因此 Gitea act runner 需要配置一个 `opencode` label，并让该 label 使用本项目镜像。例如：

```text
opencode:docker://ghcr.io/nicochigu/gitea-opencode:latest
```

构建镜像：

```sh
git clone https://github.com/NicoChiGu/gitea-opencode.git
cd gitea-opencode
docker build -t ghcr.io/nicochigu/gitea-opencode:latest .
docker push ghcr.io/nicochigu/gitea-opencode:latest
```

也可以参考仓库中的 `docker-compose.runner.yml` 和 `runner-config.example.yaml` 启动 runner。

## 必要 Secrets

在目标 Gitea 仓库或组织的 Actions Secrets 中配置：

```text
ANTHROPIC_API_KEY
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
