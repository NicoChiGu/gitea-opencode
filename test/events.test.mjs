import test from "node:test";
import assert from "node:assert/strict";
import { readEvent } from "../src/events.mjs";

test("reads issue comment command", () => {
  const event = readEvent(
    {
      action: "created",
      issue: { number: 12, title: "Bug" },
      comment: { body: "/opencode fix this", user: { login: "alice" } },
      sender: { login: "alice" },
    },
    "issue_comment"
  );

  assert.equal(event.shouldRun, true);
  assert.equal(event.targetKind, "issue");
  assert.equal(event.issueNumber, 12);
  assert.equal(event.directive.action, "fix");
  assert.equal(event.actor, "alice");
});

test("reads PR timeline comment command", () => {
  const event = readEvent(
    {
      is_pull: true,
      issue: { number: 7 },
      comment: { body: "please update tests /oc", user: { login: "bob" } },
    },
    "issue_comment"
  );

  assert.equal(event.shouldRun, true);
  assert.equal(event.targetKind, "pull_request");
  assert.equal(event.prNumber, 7);
});

test("reads PR review line comment context", () => {
  const event = readEvent(
    {
      number: 8,
      comment: {
        body: "/oc add error handling here",
        user: { login: "carol" },
        path: "src/app.js",
        line: 42,
        diff_hunk: "@@ -1 +1 @@",
      },
    },
    "pull_request_review_comment"
  );

  assert.equal(event.shouldRun, true);
  assert.equal(event.prNumber, 8);
  assert.equal(event.reviewContext.path, "src/app.js");
  assert.equal(event.reviewContext.line, 42);
});

test("pull request event becomes auto review", () => {
  const event = readEvent(
    {
      action: "opened",
      number: 3,
      pull_request: { number: 3, title: "Change" },
      sender: { login: "dana" },
    },
    "pull_request",
    { OPENCODE_REVIEW_PROMPT: "Review carefully" }
  );

  assert.equal(event.shouldRun, true);
  assert.equal(event.autoReview, true);
  assert.equal(event.directive.instruction, "Review carefully");
});
