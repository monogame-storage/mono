// Drift detection for the shared agent contract. The Worker and the
// eval harness both import from cosmi/src/lib/agent-prompt.js — these
// tests lock down the structural invariants so a future refactor can't
// silently break the system prompt or strand a tool definition.
import { describe, it } from "node:test";
import assert from "node:assert/strict";
import {
  AGENT_TOOLS,
  AGENT_MAX_ITER,
  ENGINE_CONSTANTS,
  buildAgentSystemPrompt,
} from "../src/lib/agent-prompt.js";
import { ENGINE_GLOBALS } from "../src/lib/lint.js";

describe("AGENT_TOOLS", () => {
  it("declares exactly the four file-management tools", () => {
    const names = AGENT_TOOLS.map((t) => t.function.name).sort();
    assert.deepEqual(names, ["delete_file", "list_files", "read_file", "write_file"]);
  });

  it("uses OpenAI function-calling schema shape", () => {
    for (const t of AGENT_TOOLS) {
      assert.equal(t.type, "function");
      assert.ok(t.function.name);
      assert.ok(t.function.description);
      assert.equal(t.function.parameters.type, "object");
    }
  });
});

describe("AGENT_MAX_ITER", () => {
  it("is a sane positive integer", () => {
    assert.ok(Number.isInteger(AGENT_MAX_ITER));
    assert.ok(AGENT_MAX_ITER >= 5);
    assert.ok(AGENT_MAX_ITER <= 100);
  });
});

describe("buildAgentSystemPrompt", () => {
  const prompt = buildAgentSystemPrompt("## TEST API\n### example_fn(): void");

  it("appends the API.md content verbatim", () => {
    assert.ok(prompt.includes("### example_fn(): void"));
  });

  it("falls back gracefully when API.md is empty", () => {
    const empty = buildAgentSystemPrompt("");
    assert.ok(empty.includes("API.md unavailable"));
  });

  it("contains every ENGINE_GLOBAL in the reserved list", () => {
    for (const name of ENGINE_GLOBALS) {
      assert.ok(
        prompt.includes(name),
        `reserved globals enumeration is missing engine global '${name}'`,
      );
    }
  });

  it("contains every ENGINE_CONSTANT in the reserved list", () => {
    for (const name of ENGINE_CONSTANTS) {
      assert.ok(
        prompt.includes(name),
        `reserved globals enumeration is missing constant '${name}'`,
      );
    }
  });

  it("warns about touch_start callback misuse", () => {
    // Catch a refactor that drops the polling-vs-callback section.
    assert.ok(prompt.includes("function touch_start(x, y)"));
    assert.ok(prompt.toLowerCase().includes("polling"));
  });

  it("declares the staging rule", () => {
    assert.ok(prompt.includes("at most TWO write_file calls per turn"));
  });
});
