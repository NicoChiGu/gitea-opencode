import test from "node:test";
import assert from "node:assert/strict";
import { classifyInstruction, parseDirective } from "../src/command.mjs";

test("parses directive with instruction after trigger", () => {
  const directive = parseDirective("/opencode explain this issue");
  assert.equal(directive.marker, "/opencode");
  assert.equal(directive.instruction, "explain this issue");
  assert.equal(directive.action, "explain");
});

test("parses directive with instruction before short trigger", () => {
  const directive = parseDirective("Delete the attachment from S3 when the note is removed /oc");
  assert.equal(directive.marker, "/oc");
  assert.equal(directive.instruction, "Delete the attachment from S3 when the note is removed");
  assert.equal(directive.action, "fix");
});

test("ignores text without trigger", () => {
  assert.equal(parseDirective("please review this"), null);
});

test("classifies common command families", () => {
  assert.equal(classifyInstruction("fix this"), "fix");
  assert.equal(classifyInstruction("add error handling here"), "fix");
  assert.equal(classifyInstruction("explain this issue"), "explain");
  assert.equal(classifyInstruction("review this"), "review");
});
