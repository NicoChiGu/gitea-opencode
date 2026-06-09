const triggerPattern = /(?:^|\s)(\/(?:opencode|oc)\b)/i;

export function parseDirective(text) {
  if (!text || typeof text !== "string") return null;

  const match = triggerPattern.exec(text);
  if (!match) return null;

  const markerStart = match.index + match[0].lastIndexOf(match[1]);
  const marker = match[1].toLowerCase();
  const before = text.slice(0, markerStart).trim();
  const after = text.slice(markerStart + match[1].length).trim();
  const instruction = normalizeInstruction(after || before || "review this");

  return {
    marker,
    instruction,
    raw: text,
    action: classifyInstruction(instruction),
  };
}

export function normalizeInstruction(value) {
  return String(value || "")
    .replace(/\s+/g, " ")
    .trim();
}

export function classifyInstruction(instruction) {
  const value = normalizeInstruction(instruction).toLowerCase();

  if (!value || value === "review this" || value === "review") return "review";
  if (/\bexplain\b|解释|说明/.test(value)) return "explain";
  if (/\b(fix|repair|resolve|implement|change|update|modify|add|remove|delete)\b|修复|修改|实现|添加|删除/.test(value)) {
    return "fix";
  }
  return "respond";
}

export function hasDirective(text) {
  return Boolean(parseDirective(text));
}
