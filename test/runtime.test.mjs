import test from "node:test";
import assert from "node:assert/strict";
import { runAutomation } from "../src/runtime.mjs";

const config = {
  owner: "acme",
  repo: "demo",
  repository: "acme/demo",
  eventName: "issue_comment",
  apiUrl: "https://gitea.example.com/api/v1",
  serverUrl: "https://gitea.example.com",
  token: "token",
  model: "anthropic/test",
  agent: "",
  runId: "99",
  refName: "main",
  workspace: process.cwd(),
  gitAuthorName: "OpenCode",
  gitAuthorEmail: "opencode@example.com",
};

test("explains an issue and posts a comment", async () => {
  const comments = [];
  const client = fakeClient({
    createIssueComment: async (index, body) => comments.push({ index, body }),
  });
  const opencode = { run: async () => "Issue explanation" };

  const result = await runAutomation({
    config,
    client,
    opencode,
    payload: {
      issue: { number: 1 },
      comment: { body: "/opencode explain this issue", user: { login: "alice" } },
    },
  });

  assert.equal(result.mode, "issue_explain");
  assert.deepEqual(comments, [{ index: 1, body: "OpenCode result:\n\nIssue explanation" }]);
});

test("fixes an issue by creating a branch, commit, push, and PR", async () => {
  const calls = [];
  const client = fakeClient({
    createPullRequest: async (body) => {
      calls.push(["createPullRequest", body]);
      return { number: 4, html_url: "https://gitea.example.com/acme/demo/pulls/4" };
    },
    createIssueComment: async (index, body) => calls.push(["comment", index, body]),
  });
  const git = fakeGit(calls, true);
  const opencode = { run: async () => "Implemented fix" };

  const result = await runAutomation({
    config,
    client,
    git,
    opencode,
    payload: {
      issue: { number: 2 },
      comment: { body: "/opencode fix this", user: { login: "alice" } },
    },
  });

  assert.equal(result.mode, "issue_fix_pr_created");
  assert.equal(result.branch, "opencode/issue-2-99");
  assert.deepEqual(calls.slice(0, 5), [
    ["configureIdentity", "OpenCode", "opencode@example.com"],
    ["checkoutNewBranchFrom", "main", "opencode/issue-2-99"],
    ["hasChanges"],
    ["commitAll", "fix: address issue #2"],
    ["pushBranch", "opencode/issue-2-99", "token"],
  ]);
  assert.equal(calls.at(-1)[0], "comment");
});

test("plain issue trigger reviews without creating a branch", async () => {
  const calls = [];
  const client = fakeClient({
    createIssueComment: async (index, body) => calls.push(["comment", index, body]),
  });
  const git = fakeGit(calls, true);
  const opencode = { run: async () => "Issue review" };

  const result = await runAutomation({
    config,
    client,
    git,
    opencode,
    payload: {
      issue: { number: 2 },
      comment: { body: "/opencode", user: { login: "alice" } },
    },
  });

  assert.equal(result.mode, "issue_review");
  assert.deepEqual(calls, [["comment", 2, "OpenCode result:\n\nIssue review"]]);
});

test("skips write actions from users without write access", async () => {
  const calls = [];
  const client = fakeClient({
    getCollaboratorPermission: async () => ({ permission: "read" }),
    createIssueComment: async (index, body) => calls.push(["comment", index, body]),
  });

  const result = await runAutomation({
    config,
    client,
    git: fakeGit([], true),
    opencode: { run: async () => "unused" },
    payload: {
      issue: { number: 2 },
      comment: { body: "/opencode fix this", user: { login: "reader" } },
    },
  });

  assert.equal(result.mode, "issue_fix_no_permission");
  assert.match(calls[0][2], /does not have write permission/);
});

test("pushes PR comment changes to same repository head branch", async () => {
  const calls = [];
  const client = fakeClient({
    getPull: async () => ({
      number: 5,
      title: "PR",
      body: "",
      head: { ref: "feature", repo: { full_name: "acme/demo" } },
    }),
    createIssueComment: async (index, body) => calls.push(["comment", index, body]),
  });
  const git = fakeGit(calls, true);
  const opencode = { run: async () => "Updated PR" };

  const result = await runAutomation({
    config: { ...config, eventName: "issue_comment" },
    client,
    git,
    opencode,
    payload: {
      is_pull: true,
      issue: { number: 5 },
      comment: { body: "please update tests /oc", user: { login: "alice" } },
    },
  });

  assert.equal(result.mode, "pr_change_pushed");
  assert.deepEqual(calls.slice(0, 5), [
    ["configureIdentity", "OpenCode", "opencode@example.com"],
    ["checkoutBranch", "feature"],
    ["hasChanges"],
    ["commitAll", "fix: apply OpenCode request for PR #5"],
    ["pushBranch", "feature", "token"],
  ]);
});

test("plain PR trigger reviews without pushing changes", async () => {
  const calls = [];
  const client = fakeClient({
    getPull: async () => ({
      number: 5,
      title: "PR",
      body: "",
      head: { ref: "feature", repo: { full_name: "acme/demo" } },
    }),
    createIssueComment: async (index, body) => calls.push(["comment", index, body]),
  });
  const git = fakeGit(calls, true);
  const opencode = { run: async () => "PR review" };

  const result = await runAutomation({
    config: { ...config, eventName: "issue_comment" },
    client,
    git,
    opencode,
    payload: {
      is_pull: true,
      issue: { number: 5 },
      comment: { body: "/oc", user: { login: "alice" } },
    },
  });

  assert.equal(result.mode, "pr_review");
  assert.deepEqual(calls, [["comment", 5, "OpenCode result:\n\nPR review"]]);
});

function fakeClient(overrides = {}) {
  return {
    getRepo: async () => ({ default_branch: "main" }),
    getIssue: async (number) => ({ number, title: "Issue", body: "Issue body" }),
    listIssueComments: async () => [],
    createIssueComment: async () => {},
    getPull: async (number) => ({
      number,
      title: "PR",
      body: "PR body",
      head: { ref: "feature", repo: { full_name: "acme/demo" } },
    }),
    getPullDiff: async () => "diff --git a/file b/file",
    getCollaboratorPermission: async () => ({ permission: "write" }),
    createPullRequest: async () => ({ number: 1 }),
    ...overrides,
  };
}

function fakeGit(calls, hasChanges) {
  return {
    configureIdentity: async (name, email) => calls.push(["configureIdentity", name, email]),
    checkoutNewBranchFrom: async (base, branch) => calls.push(["checkoutNewBranchFrom", base, branch]),
    checkoutBranch: async (branch) => calls.push(["checkoutBranch", branch]),
    hasChanges: async () => {
      calls.push(["hasChanges"]);
      return hasChanges;
    },
    commitAll: async (message) => calls.push(["commitAll", message]),
    pushBranch: async (branch, token) => calls.push(["pushBranch", branch, token]),
  };
}
