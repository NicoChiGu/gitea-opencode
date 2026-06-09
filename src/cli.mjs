import { runAutomation } from "./runtime.mjs";

const help = `gitea-opencode

Run the Gitea OpenCode automation adapter inside Gitea Actions.

Usage:
  gitea-opencode
  gitea-opencode --help
  gitea-opencode --version

Required environment in Gitea Actions:
  GITHUB_EVENT_PATH       Path to the event payload JSON
  GITHUB_API_URL          Gitea REST API URL
  GITHUB_REPOSITORY       owner/repo
  GITEA_TOKEN             Built-in Gitea Actions token

Optional:
  OPENCODE_GITEA_TOKEN    Personal access token override
  OPENCODE_MODEL          provider/model, defaults to anthropic/claude-sonnet-4-6
  OPENCODE_AGENT          OpenCode agent name
`;

export async function runCli(args = [], env = process.env) {
  if (args.includes("--help") || args.includes("-h")) {
    console.log(help.trimEnd());
    return;
  }

  if (args.includes("--version") || args.includes("-v")) {
    console.log("0.1.0");
    return;
  }

  await runAutomation({ env });
}
