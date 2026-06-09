export function issueExplainPrompt({ issue, comments, instruction }) {
  return `You are helping with a Gitea issue.

Task from user:
${instruction}

Issue:
#${issue.number || issue.index}: ${issue.title || "(untitled)"}

Body:
${issue.body || "(empty)"}

Comments:
${formatComments(comments)}

Write a clear explanation of the issue and the relevant context. Do not modify files.`;
}

export function issueFixPrompt({ issue, comments, instruction }) {
  return `You are working in a checked-out Gitea repository.

Task from issue comment:
${instruction}

Issue:
#${issue.number || issue.index}: ${issue.title || "(untitled)"}

Body:
${issue.body || "(empty)"}

Discussion:
${formatComments(comments)}

Implement the requested fix in the repository. Keep the change focused, add or update tests when appropriate, and do not create the pull request yourself.`;
}

export function issueReviewPrompt({ issue, comments, instruction }) {
  return `You are helping with a Gitea issue and a checked-out repository.

Task from user:
${instruction}

Issue:
#${issue.number || issue.index}: ${issue.title || "(untitled)"}

Body:
${issue.body || "(empty)"}

Discussion:
${formatComments(comments)}

Review the issue and the repository context. Reply with useful findings, risks, and next steps. Do not modify files.`;
}

export function pullRequestChangePrompt({ pullRequest, instruction, diff, reviewContext }) {
  return `You are working in a checked-out Gitea pull request branch.

Task from PR comment:
${instruction}

Pull request:
#${pullRequest.number || pullRequest.index}: ${pullRequest.title || "(untitled)"}

Description:
${pullRequest.body || "(empty)"}

${formatReviewContext(reviewContext)}

Current diff:
${limit(diff || "(diff unavailable)", 30000)}

Implement the requested change directly on the pull request branch. Keep the change focused and do not create a new pull request.`;
}

export function pullRequestReviewPrompt({ pullRequest, diff, instruction }) {
  return `You are reviewing a Gitea pull request.

Review instruction:
${instruction}

Pull request:
#${pullRequest.number || pullRequest.index}: ${pullRequest.title || "(untitled)"}

Description:
${pullRequest.body || "(empty)"}

Diff:
${limit(diff || "(diff unavailable)", 30000)}

Return a concise code review with concrete findings. Do not modify files.`;
}

export function manualPrompt({ instruction }) {
  return `You are working in a checked-out Gitea repository.

Manual OpenCode task:
${instruction}

Implement the requested repository changes. Do not create a pull request yourself.`;
}

function formatComments(comments = []) {
  if (!comments.length) return "(none)";
  return comments
    .map((comment) => {
      const author = comment?.user?.login || "unknown";
      const body = comment?.body || comment?.content || "";
      return `- ${author}: ${body}`;
    })
    .join("\n");
}

function formatReviewContext(context) {
  if (!context) return "";
  const parts = [];
  if (context.path) parts.push(`File: ${context.path}`);
  if (context.line) parts.push(`Line: ${context.line}`);
  if (context.commitId) parts.push(`Commit: ${context.commitId}`);
  if (context.diffHunk) parts.push(`Diff context:\n${context.diffHunk}`);
  return parts.length ? `Review comment context:\n${parts.join("\n")}\n` : "";
}

function limit(value, max) {
  const text = String(value);
  if (text.length <= max) return text;
  return `${text.slice(0, max)}\n\n[truncated]`;
}
