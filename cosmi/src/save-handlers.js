// Cloud save handlers. Pure functions over (env, uid, cartId[, request]) →
// Response. Extracted from index.js's route table so they can be tested
// without booting a wrangler runtime. Each handler is the leaf called
// after auth + cartId validation in the main fetch handler.
//
// R2 record shape: { version: 1, bucket: <object>, updated_at: <unix_ms> }
// The wrapper is opaque to the client; GET strips it down to { bucket }.

const R2_PREFIX = "save/";
const MAX_BODY_BYTES = 70_000;   // ~64KB JSON + headroom; defense in depth

function r2Key(uid, cartId) {
  return R2_PREFIX + uid + "/" + cartId;
}

function json(status, body) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json",
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Methods": "GET, POST, PUT, DELETE, OPTIONS",
      "Access-Control-Allow-Headers": "Authorization, Content-Type",
    },
  });
}

function noContent() {
  return new Response(null, {
    status: 204,
    headers: {
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Methods": "GET, POST, PUT, DELETE, OPTIONS",
      "Access-Control-Allow-Headers": "Authorization, Content-Type",
    },
  });
}

export async function handleSaveGet(env, uid, cartId) {
  const obj = await env.BUCKET.get(r2Key(uid, cartId));
  if (!obj) return json(404, { error: "Not found" });
  const text = await obj.text();
  let parsed;
  try { parsed = JSON.parse(text); } catch { parsed = null; }
  // If the stored record is corrupt or shape-wrong, treat as empty bucket
  // rather than 500. The client's mirror is the source of truth here;
  // a successful 200 lets the client overwrite on next save.
  const bucket = (parsed && typeof parsed === "object" && parsed.bucket
                  && typeof parsed.bucket === "object" && !Array.isArray(parsed.bucket))
    ? parsed.bucket : {};
  return json(200, { bucket });
}

export async function handleSavePut(env, uid, cartId, request) {
  // Fast-path 413 from Content-Length to avoid buffering oversized requests.
  // Non-numeric / missing headers fall through to the post-parse byte check
  // below — Content-Length alone is spoofable, so it's a hint, not the gate.
  //
  // Known limitation: an authenticated client that omits Content-Length and
  // streams up to 100MB (CF Workers' platform cap) burns isolate CPU/memory
  // until request.text() resolves. The post-parse check rejects after
  // buffering. Streaming inspection via request.body.getReader() would
  // abort earlier — flagged as BETA follow-up. Bounded by verifyAuth, so
  // not a public DoS vector, but a single bad authenticated client can
  // chew through Worker time. Acceptable trade-off in ALPHA.
  const lenHeader = request.headers.get("Content-Length");
  const declaredLen = lenHeader ? parseInt(lenHeader, 10) : 0;
  if (declaredLen > MAX_BODY_BYTES) return json(413, { error: "body too large" });
  // Read the body as text first so we can measure actual bytes before
  // JSON.parse runs — a 5MB body with `Content-Length: 0` shouldn't slip
  // through. text() respects CF Workers' global 100MB request cap.
  let raw;
  try { raw = await request.text(); }
  catch { return json(400, { error: "invalid body" }); }
  if (raw.length > MAX_BODY_BYTES) return json(413, { error: "body too large" });
  let body;
  try { body = JSON.parse(raw); }
  catch { return json(400, { error: "invalid JSON" }); }
  if (!body || typeof body !== "object") return json(400, { error: "body must be an object" });
  const bucket = body.bucket;
  if (!bucket || typeof bucket !== "object" || Array.isArray(bucket)) {
    return json(400, { error: "body.bucket must be a plain object" });
  }
  const record = { version: 1, bucket, updated_at: Date.now() };
  await env.BUCKET.put(r2Key(uid, cartId), JSON.stringify(record));
  return noContent();
}

export async function handleSaveDelete(env, uid, cartId) {
  await env.BUCKET.delete(r2Key(uid, cartId));
  return noContent();
}
