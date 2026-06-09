import { readFile } from "node:fs/promises";

export const defaultModel = "anthropic/claude-sonnet-4-6";

export async function loadPayload(env) {
  const eventPath = env.GITHUB_EVENT_PATH || env.GITEA_EVENT_PATH;
  if (!eventPath) return {};
  return JSON.parse(await readFile(eventPath, "utf8"));
}

export function getRuntimeConfig(env) {
  const repository = env.GITHUB_REPOSITORY || env.GITEA_REPOSITORY || "";
  const [owner, repo] = repository.split("/");

  return {
    owner,
    repo,
    repository,
    eventName: env.GITHUB_EVENT_NAME || env.GITEA_EVENT_NAME || "",
    apiUrl: env.GITHUB_API_URL || env.GITEA_API_URL || deriveApiUrl(env.GITHUB_SERVER_URL || env.GITEA_SERVER_URL),
    serverUrl: env.GITHUB_SERVER_URL || env.GITEA_SERVER_URL || "",
    token: env.OPENCODE_GITEA_TOKEN || env.GITEA_TOKEN || env.GITHUB_TOKEN || "",
    model: env.OPENCODE_MODEL || defaultModel,
    agent: env.OPENCODE_AGENT || "",
    runId: env.GITHUB_RUN_ID || env.GITEA_RUN_ID || String(Date.now()),
    refName: env.GITHUB_REF_NAME || env.GITEA_REF_NAME || "",
    workspace: env.GITHUB_WORKSPACE || env.GITEA_WORKSPACE || process.cwd(),
    gitAuthorName: env.OPENCODE_GIT_AUTHOR_NAME || "OpenCode",
    gitAuthorEmail: env.OPENCODE_GIT_AUTHOR_EMAIL || "opencode@gitea.local",
  };
}

function deriveApiUrl(serverUrl) {
  if (!serverUrl) return "";
  return `${serverUrl.replace(/\/+$/, "")}/api/v1`;
}

export function assertRuntimeConfig(config) {
  const missing = [];
  if (!config.owner || !config.repo) missing.push("GITHUB_REPOSITORY");
  if (!config.apiUrl) missing.push("GITHUB_API_URL");
  if (!config.token) missing.push("GITEA_TOKEN or OPENCODE_GITEA_TOKEN");
  if (missing.length > 0) {
    throw new Error(`Missing required environment: ${missing.join(", ")}`);
  }
}
