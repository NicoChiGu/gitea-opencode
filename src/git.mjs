import { spawnFile } from "./process.mjs";

export class GitClient {
  constructor({ cwd = process.cwd(), env = process.env, spawn = spawnFile } = {}) {
    this.cwd = cwd;
    this.env = env;
    this.spawn = spawn;
  }

  async configureIdentity(name, email) {
    await this.git(["config", "user.name", name]);
    await this.git(["config", "user.email", email]);
  }

  async checkoutNewBranchFrom(baseRef, branch) {
    await this.git(["fetch", "origin", baseRef, "--depth=1"]);
    await this.git(["checkout", "-B", branch, "FETCH_HEAD"]);
  }

  async checkoutBranch(branch) {
    await this.git(["fetch", "origin", branch, "--depth=1"]);
    await this.git(["checkout", "-B", branch, `origin/${branch}`]);
  }

  async statusPorcelain() {
    return (await this.git(["status", "--porcelain"])).stdout.trim();
  }

  async hasChanges() {
    return (await this.statusPorcelain()).length > 0;
  }

  async commitAll(message) {
    await this.git(["add", "--all"]);
    await this.git(["commit", "-m", message]);
  }

  async pushBranch(branch, token) {
    await this.git(["-c", `http.extraHeader=Authorization: token ${token}`, "push", "origin", branch]);
  }

  async currentBranch() {
    return (await this.git(["rev-parse", "--abbrev-ref", "HEAD"])).stdout.trim();
  }

  async git(args) {
    return this.spawn("git", args, { cwd: this.cwd, env: this.env });
  }
}
