// Cloud-save worker route tests. Drives the helpers directly with a
// fake R2 BUCKET so we don't need a wrangler runtime.
import { describe, it, beforeEach } from "node:test";
import assert from "node:assert/strict";
import { handleSaveGet, handleSavePut, handleSaveDelete } from "../src/save-handlers.js";

function makeFakeR2() {
  const map = new Map();
  return {
    map,
    get: async (key) => {
      const v = map.get(key);
      if (v == null) return null;
      return { text: async () => v };
    },
    put: async (key, body) => { map.set(key, body); },
    delete: async (key) => { map.delete(key); },
  };
}
function makeEnv() { return { BUCKET: makeFakeR2() }; }
function jsonBodyRequest(method, body, headers = {}) {
  return new Request("https://x/save/test", {
    method,
    headers: { "Content-Type": "application/json", ...headers },
    body: JSON.stringify(body),
  });
}

describe("handleSaveGet", () => {
  let env;
  beforeEach(() => { env = makeEnv(); });

  it("returns 404 when the entry is missing", async () => {
    const res = await handleSaveGet(env, "user1", "demo:bounce");
    assert.equal(res.status, 404);
  });

  it("returns 200 with the bucket field when present", async () => {
    env.BUCKET.map.set(
      "save/user1/demo:bounce",
      JSON.stringify({ version: 1, bucket: { hi: 42 }, updated_at: 1700000000000 }),
    );
    const res = await handleSaveGet(env, "user1", "demo:bounce");
    assert.equal(res.status, 200);
    assert.deepEqual(await res.json(), { bucket: { hi: 42 } });
  });

  it("isolates by uid prefix", async () => {
    env.BUCKET.map.set(
      "save/user1/demo:bounce",
      JSON.stringify({ version: 1, bucket: { hi: 42 }, updated_at: 1 }),
    );
    const res = await handleSaveGet(env, "user2", "demo:bounce");
    assert.equal(res.status, 404);
  });

  it("returns 200 + empty bucket when the R2 record is corrupt JSON", async () => {
    env.BUCKET.map.set("save/user1/demo:bounce", "{not json");
    const res = await handleSaveGet(env, "user1", "demo:bounce");
    assert.equal(res.status, 200);
    assert.deepEqual(await res.json(), { bucket: {} });
  });
});

describe("handleSavePut", () => {
  let env;
  beforeEach(() => { env = makeEnv(); });

  it("writes a record with version + updated_at", async () => {
    const req = jsonBodyRequest("PUT", { bucket: { hi: 42 } });
    const res = await handleSavePut(env, "user1", "demo:bounce", req);
    assert.equal(res.status, 204);
    const stored = JSON.parse(env.BUCKET.map.get("save/user1/demo:bounce"));
    assert.equal(stored.version, 1);
    assert.deepEqual(stored.bucket, { hi: 42 });
    assert.equal(typeof stored.updated_at, "number");
  });

  it("returns 413 when Content-Length exceeds 70000", async () => {
    const req = new Request("https://x/save/test", {
      method: "PUT",
      headers: { "Content-Type": "application/json", "Content-Length": "70001" },
      body: JSON.stringify({ bucket: {} }),
    });
    const res = await handleSavePut(env, "user1", "demo:bounce", req);
    assert.equal(res.status, 413);
  });

  it("returns 400 when body is not JSON", async () => {
    const req = new Request("https://x/save/test", {
      method: "PUT",
      headers: { "Content-Type": "application/json" },
      body: "{not json",
    });
    const res = await handleSavePut(env, "user1", "demo:bounce", req);
    assert.equal(res.status, 400);
  });

  it("returns 400 when body lacks a bucket field", async () => {
    const req = jsonBodyRequest("PUT", { not_bucket: 1 });
    const res = await handleSavePut(env, "user1", "demo:bounce", req);
    assert.equal(res.status, 400);
  });

  it("returns 400 when bucket is not a plain object", async () => {
    const req = jsonBodyRequest("PUT", { bucket: [1, 2] });
    const res = await handleSavePut(env, "user1", "demo:bounce", req);
    assert.equal(res.status, 400);
  });

  it("returns 400 when bucket is a scalar (number / string / null)", async () => {
    for (const bad of [5, "hi", null, true]) {
      const req = jsonBodyRequest("PUT", { bucket: bad });
      const res = await handleSavePut(env, "user1", "demo:bounce", req);
      assert.equal(res.status, 400, `bucket=${JSON.stringify(bad)} should be 400`);
    }
  });

  it("returns 413 when actual body bytes exceed cap even with Content-Length spoofed to 0", async () => {
    // Build a real oversize JSON body but lie in the header. The post-parse
    // byte check should still reject — Content-Length is a hint, not the gate.
    const big = "x".repeat(70_001);
    const req = new Request("https://x/save/test", {
      method: "PUT",
      headers: { "Content-Type": "application/json", "Content-Length": "0" },
      body: JSON.stringify({ bucket: { k: big } }),
    });
    const res = await handleSavePut(env, "user1", "demo:bounce", req);
    assert.equal(res.status, 413);
  });
});

describe("handleSaveDelete", () => {
  let env;
  beforeEach(() => { env = makeEnv(); });

  it("returns 204 even when the entry was missing (idempotent)", async () => {
    const res = await handleSaveDelete(env, "user1", "demo:bounce");
    assert.equal(res.status, 204);
  });

  it("removes an existing entry", async () => {
    env.BUCKET.map.set("save/user1/demo:bounce", "stub");
    const res = await handleSaveDelete(env, "user1", "demo:bounce");
    assert.equal(res.status, 204);
    assert.equal(env.BUCKET.map.has("save/user1/demo:bounce"), false);
  });
});
