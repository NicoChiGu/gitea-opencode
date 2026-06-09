import test from "node:test";
import assert from "node:assert/strict";
import { mkdtemp, mkdir, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { spawnSync } from "node:child_process";

const repoRoot = resolve(".");
const installer = join(repoRoot, "install-opencode.sh");

test("shell installer dry-run renders configured workflow", async () => {
  const cwd = await gitTempRepo();
  const result = spawnSync("sh", [installer, "--dry-run", "--runner-label", "ai", "--model", "anthropic/custom"], {
    cwd,
    encoding: "utf8",
  });

  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /runs-on: ai/);
  assert.match(result.stdout, /OPENCODE_MODEL: "anthropic\/custom"/);
});

test("shell installer protects existing workflow without force", async () => {
  const cwd = await gitTempRepo();
  await mkdir(join(cwd, ".gitea/workflows"), { recursive: true });
  await writeFile(join(cwd, ".gitea/workflows/opencode.yml"), "existing\n");

  const result = spawnSync("sh", [installer, "--no-commit"], {
    cwd,
    encoding: "utf8",
  });

  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /already exists/);
});

async function gitTempRepo() {
  const cwd = await mkdtemp(join(tmpdir(), "gitea-opencode-test-"));
  spawnSync("git", ["init"], { cwd, encoding: "utf8" });
  return cwd;
}
