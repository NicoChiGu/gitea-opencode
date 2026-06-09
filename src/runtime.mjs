import { loadPayload, getRuntimeConfig, assertRuntimeConfig } from "./env.mjs";
import { readEvent } from "./events.mjs";
import { GiteaClient, hasWritePermission } from "./gitea-client.mjs";
import { GitClient } from "./git.mjs";
import { OpenCodeRunner } from "./opencode.mjs";
import {
  issueExplainPrompt,
  issueFixPrompt,
  issueReviewPrompt,
  manualPrompt,
  pullRequestChangePrompt,
  pullRequestReviewPrompt,
} from "./prompts.mjs";

export async function runAutomation(deps = {}) {
  const env = deps.env || process.env;
  const payload = deps.payload || (await loadPayload(env));
  const config = deps.config || getRuntimeConfig(env);
  assertRuntimeConfig(config);

  const event = readEvent(payload, config.eventName, env);
  if (!event.shouldRun) {
    log(`Skipping OpenCode: ${event.reason}`);
    return { skipped: true, reason: event.reason };
  }

  const client =
    deps.client ||
    new GiteaClient({
      apiUrl: config.apiUrl,
      owner: config.owner,
      repo: config.repo,
      token: config.token,
      fetchImpl: deps.fetchImpl,
    });
  const git = deps.git || new GitClient({ cwd: config.workspace, env });
  const opencode = deps.opencode || new OpenCodeRunner({ cwd: config.workspace, env });

  if (event.eventKind === "issue_comment" && event.targetKind === "issue") {
    if (event.directive.action === "explain") {
      return explainIssue({ event, client, opencode, config });
    }
    if (event.directive.action !== "fix") {
      return reviewIssue({ event, client, opencode, config });
    }
    return fixIssue({ event, client, git, opencode, config });
  }

  if (
    event.eventKind === "issue_comment" ||
    event.eventKind === "pull_request_review_comment"
  ) {
    if (event.directive.action !== "fix") {
      return reviewPullRequest({ event, client, opencode, config });
    }
    return changePullRequest({ event, client, git, opencode, config });
  }

  if (event.eventKind === "pull_request") {
    return reviewPullRequest({ event, client, opencode, config });
  }

  if (event.eventKind === "workflow_dispatch") {
    return runManualTask({ event, client, git, opencode, config });
  }

  log(`Skipping OpenCode: no handler for ${event.eventKind}`);
  return { skipped: true, reason: `no handler for ${event.eventKind}` };
}

async function explainIssue({ event, client, opencode, config }) {
  const issue = await client.getIssue(event.issueNumber);
  const comments = await client.listIssueComments(event.issueNumber);
  const output = await opencode.run(
    issueExplainPrompt({ issue, comments, instruction: event.directive.instruction }),
    modelOptions(config)
  );
  await client.createIssueComment(event.issueNumber, formatBotComment(output));
  return { skipped: false, mode: "issue_explain", output };
}

async function reviewIssue({ event, client, opencode, config }) {
  const issue = await client.getIssue(event.issueNumber);
  const comments = await client.listIssueComments(event.issueNumber);
  const output = await opencode.run(
    issueReviewPrompt({ issue, comments, instruction: event.directive.instruction }),
    modelOptions(config)
  );
  await client.createIssueComment(event.issueNumber, formatBotComment(output));
  return { skipped: false, mode: "issue_review", output };
}

async function fixIssue({ event, client, git, opencode, config }) {
  if (!(await hasWriteAccess(client, event.actor))) {
    await client.createIssueComment(event.issueNumber, formatBotComment(`Skipping: user ${event.actor || "(unknown)"} does not have write permission for this repository.`));
    return { skipped: true, mode: "issue_fix_no_permission" };
  }

  const repo = await client.getRepo();
  const issue = await client.getIssue(event.issueNumber);
  const comments = await client.listIssueComments(event.issueNumber);
  const base = issue.ref || repo.default_branch || config.refName || "main";
  const branch = safeBranchName(`opencode/issue-${event.issueNumber}-${config.runId}`);

  await git.configureIdentity(config.gitAuthorName, config.gitAuthorEmail);
  await git.checkoutNewBranchFrom(base, branch);

  const output = await opencode.run(
    issueFixPrompt({ issue, comments, instruction: event.directive.instruction }),
    modelOptions(config)
  );

  if (!(await git.hasChanges())) {
    await client.createIssueComment(event.issueNumber, formatBotComment(output || "OpenCode did not produce file changes."));
    return { skipped: false, mode: "issue_fix_no_changes", output };
  }

  await git.commitAll(`fix: address issue #${event.issueNumber}`);
  await git.pushBranch(branch, config.token);
  const pr = await client.createPullRequest({
    title: `OpenCode fix for #${event.issueNumber}`,
    body: `Created by OpenCode for issue #${event.issueNumber}.\n\nInstruction:\n${event.directive.instruction}\n\nOpenCode output:\n${output || "(no output)"}`,
    head: branch,
    base,
  });
  await client.createIssueComment(event.issueNumber, formatBotComment(`Created pull request ${pullRequestLabel(pr)}.`));
  return { skipped: false, mode: "issue_fix_pr_created", branch, pr, output };
}

async function changePullRequest({ event, client, git, opencode, config }) {
  if (!(await hasWriteAccess(client, event.actor))) {
    await client.createIssueComment(event.prNumber, formatBotComment(`Skipping: user ${event.actor || "(unknown)"} does not have write permission for this repository.`));
    return { skipped: true, mode: "pr_change_no_permission" };
  }

  const pr = event.pullRequest?.number || event.pullRequest?.index ? event.pullRequest : await client.getPull(event.prNumber);

  if (!isSameRepositoryPullRequest(pr, config)) {
    await client.createIssueComment(event.prNumber, formatBotComment("Skipping: this pull request comes from another repository. OpenCode only pushes changes to same-repository PR branches by default."));
    return { skipped: true, mode: "pr_change_cross_repo" };
  }

  const headBranch = pr?.head?.ref || pr?.head?.name || pr?.head_branch || config.refName;
  if (!headBranch) throw new Error("Unable to determine pull request head branch.");

  await git.configureIdentity(config.gitAuthorName, config.gitAuthorEmail);
  await git.checkoutBranch(headBranch);

  const diff = await safeGetDiff(client, event.prNumber);
  const output = await opencode.run(
    pullRequestChangePrompt({
      pullRequest: pr,
      instruction: event.directive.instruction,
      diff,
      reviewContext: event.reviewContext,
    }),
    modelOptions(config)
  );

  if (!(await git.hasChanges())) {
    await client.createIssueComment(event.prNumber, formatBotComment(output || "OpenCode did not produce file changes."));
    return { skipped: false, mode: "pr_change_no_changes", output };
  }

  await git.commitAll(`fix: apply OpenCode request for PR #${event.prNumber}`);
  await git.pushBranch(headBranch, config.token);
  await client.createIssueComment(event.prNumber, formatBotComment(output || "OpenCode pushed changes to this PR."));
  return { skipped: false, mode: "pr_change_pushed", branch: headBranch, output };
}

async function reviewPullRequest({ event, client, opencode, config }) {
  const pr = event.pullRequest?.number || event.pullRequest?.index ? event.pullRequest : await client.getPull(event.prNumber);
  const actor = event.actor || pr?.user?.login;

  if (!isSameRepositoryPullRequest(pr, config) && !(await hasWriteAccess(client, actor))) {
    log("Skipping cross-repository pull request auto-review without write access.");
    return { skipped: true, mode: "pr_review_cross_repo" };
  }

  const diff = await safeGetDiff(client, event.prNumber);
  const output = await opencode.run(
    pullRequestReviewPrompt({
      pullRequest: pr,
      diff,
      instruction: event.directive.instruction,
    }),
    modelOptions(config)
  );
  await client.createIssueComment(event.prNumber, formatBotComment(output));
  return { skipped: false, mode: "pr_review", output };
}

async function runManualTask({ event, client, git, opencode, config }) {
  await git.configureIdentity(config.gitAuthorName, config.gitAuthorEmail);
  const repo = await client.getRepo();
  const base = repo.default_branch || config.refName || "main";
  const branch = safeBranchName(`opencode/manual-${config.runId}`);
  await git.checkoutNewBranchFrom(base, branch);

  const output = await opencode.run(manualPrompt({ instruction: event.directive.instruction }), modelOptions(config));
  if (!(await git.hasChanges())) {
    log(output || "OpenCode did not produce file changes.");
    return { skipped: false, mode: "manual_no_changes", output };
  }

  if (!event.manualCreatePr) {
    log("OpenCode produced changes, but manual create_pr=false. Changes remain in the workflow workspace only.");
    return { skipped: false, mode: "manual_changes_not_pushed", output };
  }

  await git.commitAll("chore: apply manual OpenCode task");
  await git.pushBranch(branch, config.token);
  const pr = await client.createPullRequest({
    title: "OpenCode manual task",
    body: `Created by workflow_dispatch.\n\nPrompt:\n${event.directive.instruction}\n\nOpenCode output:\n${output || "(no output)"}`,
    head: branch,
    base,
  });
  log(`Created pull request ${pullRequestLabel(pr)}.`);
  return { skipped: false, mode: "manual_pr_created", branch, pr, output };
}

async function hasWriteAccess(client, username) {
  if (!username) return false;
  try {
    return hasWritePermission(await client.getCollaboratorPermission(username));
  } catch {
    return false;
  }
}

async function safeGetDiff(client, prNumber) {
  try {
    return await client.getPullDiff(prNumber);
  } catch (error) {
    log(`Unable to fetch pull request diff: ${error.message}`);
    return "";
  }
}

function isSameRepositoryPullRequest(pr, config) {
  const headRepo = pr?.head?.repo?.full_name || pr?.head?.repo?.fullName || pr?.head?.repo?.name || "";
  if (!headRepo) return true;
  return headRepo === `${config.owner}/${config.repo}` || headRepo === config.repo;
}

function modelOptions(config) {
  return { model: config.model, agent: config.agent };
}

function formatBotComment(output) {
  return `OpenCode result:\n\n${output || "(no output)"}`;
}

function pullRequestLabel(pr) {
  if (pr?.html_url) return `#${pr.number || pr.index} (${pr.html_url})`;
  return `#${pr?.number || pr?.index || "unknown"}`;
}

function safeBranchName(value) {
  return value
    .replace(/[^A-Za-z0-9/_-]+/g, "-")
    .replace(/\/+/g, "/")
    .replace(/^-+|-+$/g, "");
}

function log(message) {
  console.log(`[gitea-opencode] ${message}`);
}
