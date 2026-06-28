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
  assert.match(result.stdout, /uses: docker:\/\/registry\.cn-hangzhou\.aliyuncs\.com\/terata\/gitea-opencode:latest/);
  assert.match(result.stdout, /ANTHROPIC_API_KEY: \$\{\{ secrets\.ANTHROPIC_API_KEY \}\}/);
  assert.doesNotMatch(result.stdout, /OPENAI_API_KEY/);
  assert.match(result.stdout, /OPENCODE_MODEL: "anthropic\/custom"/);
  assert.match(result.stdout, /uses: actions\/checkout@v4/);
  assert.match(result.stderr, /ANTHROPIC_API_KEY=<您的 API 密钥>/);
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
  assert.match(result.stderr, /已存在/);
});

test("shell installer yes mode uses the default model", async () => {
  const cwd = await gitTempRepo();
  const result = spawnSync("sh", [installer, "--dry-run", "--yes"], {
    cwd,
    encoding: "utf8",
  });

  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /OPENCODE_MODEL: "anthropic\/claude-sonnet-4-6"/);
  assert.match(result.stdout, /ANTHROPIC_API_KEY/);
});

test("shell installer renders only the selected Xiaomi secret", async () => {
  const cwd = await gitTempRepo();
  const result = spawnSync("sh", [installer, "--dry-run", "--model", "xiaomi-token-plan-cn/mimo-v2.5-pro"], {
    cwd,
    encoding: "utf8",
  });

  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /XIAOMI_API_KEY: \$\{\{ secrets\.XIAOMI_API_KEY \}\}/);
  assert.doesNotMatch(result.stdout, /ANTHROPIC_API_KEY/);
  assert.doesNotMatch(result.stdout, /OPENAI_API_KEY/);
  assert.match(result.stderr, /XIAOMI_API_KEY=<您的 API 密钥>/);
});

test("shell installer supports custom provider secret names", async () => {
  const cwd = await gitTempRepo();
  const result = spawnSync("sh", [installer, "--dry-run", "--model", "custom-provider/model", "--api-key-secret", "CUSTOM_PROVIDER_API_KEY"], {
    cwd,
    encoding: "utf8",
  });

  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /CUSTOM_PROVIDER_API_KEY: \$\{\{ secrets\.CUSTOM_PROVIDER_API_KEY \}\}/);
  assert.match(result.stderr, /CUSTOM_PROVIDER_API_KEY=<您的 API 密钥>/);
});

test("shell installer rejects invalid model format", async () => {
  const cwd = await gitTempRepo();
  const result = spawnSync("sh", [installer, "--dry-run", "--model", "openai"], {
    cwd,
    encoding: "utf8",
  });

  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /格式/);
});

test("shell installer renders custom action image", async () => {
  const cwd = await gitTempRepo();
  const result = spawnSync("sh", [installer, "--dry-run", "--yes", "--action-image", "registry.example.com/team/opencode:test"], {
    cwd,
    encoding: "utf8",
  });

  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /uses: docker:\/\/registry\.example\.com\/team\/opencode:test/);
  assert.match(result.stderr, /Action 镜像: registry\.example\.com\/team\/opencode:test/);
});

test("shell installer renders custom checkout action", async () => {
  const cwd = await gitTempRepo();
  const result = spawnSync("sh", [installer, "--dry-run", "--yes", "--checkout-action", "checkout@v4"], {
    cwd,
    encoding: "utf8",
  });

  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /uses: checkout@v4/);
});

test("shell installer detects existing checkout action from existing workflow file", async () => {
  const cwd = await gitTempRepo();
  await mkdir(join(cwd, ".gitea/workflows"), { recursive: true });
  await writeFile(
    join(cwd, ".gitea/workflows/opencode.yml"),
    `
jobs:
  opencode:
    steps:
      - name: Checkout repository
        uses: custom-checkout@v99
`
  );

  const result = spawnSync("sh", [installer, "--dry-run", "--yes"], {
    cwd,
    encoding: "utf8",
  });

  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /uses: custom-checkout@v99/);
});

async function gitTempRepo() {
  const cwd = await mkdtemp(join(tmpdir(), "gitea-opencode-test-"));
  spawnSync("git", ["init"], { cwd, encoding: "utf8" });
  return cwd;
}
