import { spawnFile } from "./process.mjs";

export class OpenCodeRunner {
  constructor({ cwd = process.cwd(), env = process.env, spawn = spawnFile } = {}) {
    this.cwd = cwd;
    this.env = env;
    this.spawn = spawn;
  }

  async run(prompt, { model, agent } = {}) {
    console.log(`[gitea-opencode] Starting OpenCode model=${model || "(default)"} agent=${agent || "(default)"}`);
    const args = ["run"];
    if (model) args.push("--model", model);
    if (agent) args.push("--agent", agent);
    args.push(prompt);
    const result = await this.spawn("opencode", args, {
      cwd: this.cwd,
      env: this.env,
      streamStdout: true,
      streamStderr: true,
      heartbeatLabel: "OpenCode",
      heartbeatIntervalMs: 30000,
    });
    console.log("[gitea-opencode] OpenCode finished");
    return result.stdout.trim() || result.stderr.trim();
  }
}
