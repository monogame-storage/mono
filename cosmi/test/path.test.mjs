// Path-traversal guard regression suite. The agent's tool inputs are
// untrusted — these vectors must never reach R2 key concatenation.
import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { validateAgentPath } from "../src/lib/path.js";

describe("validateAgentPath", () => {
  it("accepts a plain filename", () => {
    assert.equal(validateAgentPath("main.lua"), null);
  });

  it("accepts a nested relative path", () => {
    assert.equal(validateAgentPath("scenes/title.lua"), null);
  });

  it("rejects empty string", () => {
    assert.match(validateAgentPath(""), /required/);
  });

  it("rejects null / undefined / non-string", () => {
    assert.match(validateAgentPath(null), /required/);
    assert.match(validateAgentPath(undefined), /required/);
    assert.match(validateAgentPath(42), /required/);
  });

  it("rejects bare '..'", () => {
    assert.match(validateAgentPath(".."), /'\.\.'/);
  });

  it("rejects '../foo'", () => {
    assert.match(validateAgentPath("../foo"), /'\.\.'/);
  });

  it("rejects embedded '..' segment", () => {
    assert.match(validateAgentPath("a/../b"), /'\.\.'/);
  });

  it("rejects absolute paths", () => {
    assert.match(validateAgentPath("/etc/passwd"), /relative POSIX/);
  });

  it("rejects backslash (Windows-style separator + traversal vector)", () => {
    assert.match(validateAgentPath("a\\b.lua"), /relative POSIX/);
  });

  it("rejects backslash + dotdot combo", () => {
    assert.match(validateAgentPath("a\\..\\b"), /'\.\.'/);
  });

  it("rejects embedded NUL", () => {
    assert.match(validateAgentPath("a\0.lua"), /NUL/);
  });
});
