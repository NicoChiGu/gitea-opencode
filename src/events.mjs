import { parseDirective, normalizeInstruction } from "./command.mjs";

export function readEvent(payload, eventName, env = {}) {
  const name = eventName || env.GITHUB_EVENT_NAME || env.GITEA_EVENT_NAME || "";

  if (name === "issue_comment") {
    return fromIssueComment(payload);
  }

  if (name === "pull_request_review_comment") {
    return fromPullRequestReviewComment(payload);
  }

  if (name === "pull_request") {
    return fromPullRequest(payload, env);
  }

  if (name === "workflow_dispatch") {
    return fromWorkflowDispatch(payload, env);
  }

  return { shouldRun: false, reason: `unsupported event: ${name || "unknown"}` };
}

function fromIssueComment(payload) {
  const body = payload?.comment?.body || payload?.comment?.content || "";
  const directive = parseDirective(body);
  if (!directive) {
    return { shouldRun: false, reason: "comment does not mention /opencode or /oc" };
  }

  const issue = payload.issue || {};
  const isPull = Boolean(payload.is_pull || payload.pull_request || issue.pull_request);
  const issueNumber = numberOrNull(issue.number ?? issue.index);

  return {
    shouldRun: true,
    eventKind: "issue_comment",
    targetKind: isPull ? "pull_request" : "issue",
    directive,
    issueNumber,
    prNumber: isPull ? issueNumber : null,
    actor: actorFromPayload(payload),
    comment: payload.comment || null,
    payload,
  };
}

function fromPullRequestReviewComment(payload) {
  const comment = payload.comment || payload.review || {};
  const body = comment.body || comment.content || payload?.review?.content || "";
  const directive = parseDirective(body);
  if (!directive) {
    return { shouldRun: false, reason: "review comment does not mention /opencode or /oc" };
  }

  const pr = payload.pull_request || {};
  const issue = payload.issue || {};
  const prNumber = numberOrNull(payload.number ?? pr.number ?? pr.index ?? issue.number ?? issue.index);

  return {
    shouldRun: true,
    eventKind: "pull_request_review_comment",
    targetKind: "pull_request",
    directive,
    issueNumber: prNumber,
    prNumber,
    actor: actorFromPayload(payload),
    comment,
    reviewContext: {
      path: comment.path || comment.file_path || null,
      line: numberOrNull(comment.line ?? comment.original_line ?? comment.position),
      commitId: comment.commit_id || payload.commit_id || null,
      diffHunk: comment.diff_hunk || comment.diff || null,
    },
    payload,
  };
}

function fromPullRequest(payload, env) {
  const action = payload.action || "";
  if (!["opened", "reopened", "synchronized", "synchronize"].includes(action)) {
    return { shouldRun: false, reason: `pull_request action is not reviewable: ${action || "unknown"}` };
  }

  const pr = payload.pull_request || {};
  const prNumber = numberOrNull(payload.number ?? pr.number ?? pr.index);
  const defaultPrompt = "Review this pull request. Check for correctness, regressions, security issues, and missing tests. Do not modify files.";

  return {
    shouldRun: true,
    eventKind: "pull_request",
    targetKind: "pull_request",
    autoReview: true,
    directive: {
      marker: "auto",
      instruction: normalizeInstruction(env.OPENCODE_REVIEW_PROMPT || defaultPrompt),
      raw: "",
      action: "review",
    },
    issueNumber: prNumber,
    prNumber,
    actor: actorFromPayload(payload),
    pullRequest: pr,
    payload,
  };
}

function fromWorkflowDispatch(payload, env) {
  const inputs = payload?.inputs || payload?.workflow_dispatch?.inputs || {};
  const prompt = normalizeInstruction(inputs.prompt || env.OPENCODE_PROMPT || "");
  if (!prompt) {
    return { shouldRun: false, reason: "workflow_dispatch requires a prompt input" };
  }

  return {
    shouldRun: true,
    eventKind: "workflow_dispatch",
    targetKind: "repository",
    manualCreatePr: String(inputs.create_pr ?? env.OPENCODE_MANUAL_CREATE_PR ?? "true").toLowerCase() !== "false",
    directive: {
      marker: "manual",
      instruction: prompt,
      raw: prompt,
      action: "fix",
    },
    actor: actorFromPayload(payload) || env.GITHUB_ACTOR || env.GITEA_ACTOR || null,
    payload,
  };
}

export function actorFromPayload(payload) {
  return (
    payload?.comment?.user?.login ||
    payload?.review?.user?.login ||
    payload?.sender?.login ||
    payload?.pull_request?.user?.login ||
    payload?.issue?.user?.login ||
    null
  );
}

export function numberOrNull(value) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}
