// Path-traversal guard regression suite. The agent's tool inputs are
// untrusted — these vectors must never reach R2 key concatenation.
import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { validateAgentPath, validateGameId, validateCartId } from "../src/lib/path.js";

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

describe("validateGameId", () => {
  it("accepts a Firestore-style auto id", () => {
    assert.equal(validateGameId("pyS83mFaQBOP25stI2KA"), null);
  });

  it("accepts plain alphanumeric / underscore / dash", () => {
    assert.equal(validateGameId("game-1_v2"), null);
    assert.equal(validateGameId("ABC"), null);
    assert.equal(validateGameId("123"), null);
  });

  it("rejects empty / null / non-string", () => {
    assert.match(validateGameId(""), /required/);
    assert.match(validateGameId(null), /required/);
    assert.match(validateGameId(undefined), /required/);
    assert.match(validateGameId(42), /required/);
  });

  it("rejects path-traversal characters", () => {
    assert.match(validateGameId("../foo"), /must match/);
    assert.match(validateGameId("foo/bar"), /must match/);
    assert.match(validateGameId("foo\\bar"), /must match/);
  });

  it("rejects whitespace and special chars", () => {
    assert.match(validateGameId("foo bar"), /must match/);
    assert.match(validateGameId("foo.bar"), /must match/);
    assert.match(validateGameId("foo:bar"), /must match/);
  });

  it("rejects values longer than 64 chars", () => {
    assert.match(validateGameId("a".repeat(65)), /must match/);
  });

  it("accepts a 64-char id at the boundary", () => {
    assert.equal(validateGameId("a".repeat(64)), null);
  });
});

describe("validateCartId", () => {
  it("accepts plain alphanumerics", () => {
    assert.equal(validateCartId("game42"), null);
  });

  it("accepts colons and underscores and hyphens", () => {
    assert.equal(validateCartId("demo:bounce"), null);
    assert.equal(validateCartId("pkg:com.foo"), "must match /^[a-zA-Z0-9:_-]{1,80}$/"); // dot rejected
    assert.equal(validateCartId("pkg:com_foo"), null);
    assert.equal(validateCartId("hi-score_v2"), null);
  });

  it("accepts boundary length 80", () => {
    assert.equal(validateCartId("a".repeat(80)), null);
  });

  it("rejects empty / null / non-string", () => {
    assert.match(validateCartId(""), /required/);
    assert.match(validateCartId(null), /required/);
    assert.match(validateCartId(undefined), /required/);
    assert.match(validateCartId(42), /required/);
  });

  it("rejects > 80 chars", () => {
    assert.match(validateCartId("a".repeat(81)), /must match/);
  });

  it("rejects path traversal vectors", () => {
    assert.match(validateCartId("../foo"), /must match/);
    assert.match(validateCartId("foo/bar"), /must match/);
    assert.match(validateCartId("foo\\bar"), /must match/);
    assert.match(validateCartId(".."), /must match/);
  });

  it("rejects whitespace and control chars", () => {
    assert.match(validateCartId("foo bar"), /must match/);
    assert.match(validateCartId("foo\tbar"), /must match/);
    assert.match(validateCartId("foo\0bar"), /must match/);
  });
});
