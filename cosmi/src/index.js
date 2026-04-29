// Mono Developer API — Cloudflare Worker
// Routes:
//   POST   /chat                          → AI chat (generate/edit Lua code)
//   POST   /test                          → Headless test (run game, return errors)
//   GET    /games/:gameId/files           → list files
//   GET    /games/:gameId/files/:filename → read file
//   PUT    /games/:gameId/files/:filename → write file
//   DELETE /games/:gameId/files/:filename → delete file
//   POST   /games/:gameId/publish         → snapshot files to published version
//   POST   /games/:gameId/unpublish       → remove published snapshot
//   GET    /games/:gameId/published       → get published files (public, no auth)
//   GET    /games/:gameId/thumbnail       → get published thumbnail (public, no auth)

// headless test moved to browser Web Worker

// Default monogame.cc; override per-environment via env.DOCS_BASE_URL
// (wrangler.toml [vars] or `wrangler dev --var DOCS_BASE_URL=http://localhost:8090`).
// Set to a localhost URL so Cosmi reads in-progress docs from a local
// monogame.cc clone without redeploying. See docsBase().
const DEFAULT_DOCS_BASE = "https://monogame.cc";

function docsBase(env) {
  const v = env?.DOCS_BASE_URL;
  return (typeof v === "string" && v.trim()) ? v.replace(/\/$/, "") : DEFAULT_DOCS_BASE;
}

function docUrls(env) {
  const base = docsBase(env);
  return {
    context: `${base}/editor/templates/mono/CONTEXT.md`,
    api: `${base}/docs/API.md`,
    pitfalls: `${base}/docs/AI-PITFALLS.md`,
  };
}

// docCache key is `${base}::${name}` so localhost and prod doc bodies
// don't collide between requests in the same isolate.
const docCache = {};
const docExpiry = {};

// Cache the parsed API.md whitelist alongside its source string so
// extractApiWhitelist runs at most once per fetchDoc("api") refresh.
let apiWhitelistCache = null;
let apiWhitelistSource = null;

export default {
  async fetch(request, env) {
    if (request.method === "OPTIONS") return corsResponse();

    const url = new URL(request.url);

    // ── Public endpoints (no auth) ──
    const pubMatch = url.pathname.match(/^\/games\/([^/]+)\/(published|thumbnail)$/);
    if (pubMatch && request.method === "GET") {
      const [, gameId, endpoint] = pubMatch;
      const bad = validateGameId(gameId);
      if (bad) return json(400, { error: bad });
      if (endpoint === "published") return await handleGetPublished(env, gameId);
      if (endpoint === "thumbnail") return await handleGetThumbnail(env, gameId);
    }

    // Public config: exposes the vendor catalog so the client can render
    // the Provider dropdown + decide /chat vs /chat/agent routing (tool
    // use runs only against openai-protocol providers). Model lists are
    // NOT included — those are fetched live per-Connection via /models.
    if (url.pathname === "/config" && request.method === "GET") {
      const providers = Object.entries(PROVIDER_CATALOG).map(([id, p]) => ({
        id,
        label: p.label,
        protocol: p.protocol,
        baseUrl: p.baseUrl || null,
        modelsPath: p.modelsPath || null,
        // Custom is the only one requiring user-supplied baseUrl.
        requiresBaseUrl: id === "custom",
      }));
      return json(200, {
        providers,
        agentProtocols: ["openai"],
      });
    }

    try {
      const uid = await verifyAuth(request, env);
      if (!uid) return json(401, { error: "Unauthorized" });

      // ── Chat endpoint ──
      if (url.pathname === "/chat" && request.method === "POST") {
        return await handleChat(request, env, uid);
      }

      // ── Agent endpoint (OpenAI-compat tool-use loop) ──
      if (url.pathname === "/chat/agent" && request.method === "POST") {
        return await handleAgent(request, env, uid);
      }

      // ── Model list proxy (for Add Provider UI autocomplete) ──
      if (url.pathname === "/models" && request.method === "POST") {
        return await handleListModels(request, env, uid);
      }

      // /test removed — headless test runs in browser Web Worker

      // ── Publish endpoints ──
      const publishMatch = url.pathname.match(/^\/games\/([^/]+)\/(publish|unpublish)$/);
      if (publishMatch && request.method === "POST") {
        const [, gameId, action] = publishMatch;
        const bad = validateGameId(gameId);
        if (bad) return json(400, { error: bad });
        if (action === "publish") return await handlePublish(env, uid, gameId);
        if (action === "unpublish") return await handleUnpublish(env, uid, gameId);
      }

      // ── Admin: lint rejection log (per-user) ──
      if (url.pathname === "/admin/lint-rejects" && request.method === "GET") {
        return await handleListLintRejects(env, uid, url);
      }

      // ── File endpoints ──
      const match = url.pathname.match(/^\/games\/([^/]+)\/files(?:\/(.+))?$/);
      if (!match) return json(404, { error: "Not found" });

      const [, gameId, filename] = match;
      const bad = validateGameId(gameId);
      if (bad) return json(400, { error: bad });
      const prefix = `${uid}/${gameId}/`;

      switch (request.method) {
        case "GET":
          return filename
            ? await getFile(env, prefix + filename)
            : await listFiles(env, prefix);
        case "PUT":
          return await putFile(env, prefix + filename, request);
        case "DELETE":
          return await deleteFile(env, prefix + filename);
        default:
          return json(405, { error: "Method not allowed" });
      }
    } catch (e) {
      // Don't leak stack traces — they expose Worker internals
      // (paths, framework versions, prompt structure) to clients.
      // Surface only the message; tail the wrangler logs for traces.
      console.error("[unhandled]", e?.stack || e);
      return json(500, { error: e?.message || "internal error" });
    }
  },
};

// ── Chat ──

// Provider catalog — vendor-level config only. The specific model id is
// chosen by the user at Connection time via a live /models query, not
// hardcoded here. Custom is the free-form BYOK entry: the client
// supplies baseUrl + model directly.
//
// protocol drives how handleChat / handleAgent build the upstream
// request: "openai" → /v1/chat/completions JSON, "anthropic" → Messages
// API with system prompt caching, "gemini" → generateContent.
//
// auth drives how the API key is passed: "bearer" → Authorization
// header, "x-api-key" → Anthropic's vendor header, "query-key" → Gemini's
// ?key= query param.
const PROVIDER_CATALOG = {
  openai: {
    label: "OpenAI",
    baseUrl: "https://api.openai.com",
    chatPath: "/v1/chat/completions",
    modelsPath: "/v1/models",
    protocol: "openai",
    auth: "bearer",
  },
  anthropic: {
    label: "Anthropic",
    baseUrl: "https://api.anthropic.com",
    chatPath: "/v1/messages",
    modelsPath: "/v1/models",
    protocol: "anthropic",
    auth: "x-api-key",
  },
  moonshot: {
    label: "Moonshot",
    baseUrl: "https://api.moonshot.ai",
    chatPath: "/v1/chat/completions",
    modelsPath: "/v1/models",
    protocol: "openai",
    auth: "bearer",
  },
  google: {
    label: "Google (Gemini)",
    baseUrl: "https://generativelanguage.googleapis.com/v1beta",
    // Gemini derives chatPath per model at request time:
    //   "/models/{model}:generateContent"
    modelsPath: "/models",
    protocol: "gemini",
    auth: "query-key",
  },
  apimart: {
    label: "ApiMart",
    baseUrl: "https://api.apimart.io",
    chatPath: "/v1/chat/completions",
    modelsPath: "/v1/models",
    protocol: "openai",
    auth: "bearer",
  },
  custom: {
    label: "Custom / Relay",
    // baseUrl comes from the Connection. Protocol defaults to openai;
    // a user wanting anthropic-protocol against a custom relay can pick
    // "anthropic" as the provider and override baseUrl on the Connection.
    chatPath: "/v1/chat/completions",
    modelsPath: "/v1/models",
    protocol: "openai",
    auth: "bearer",
  },
};

// Resolve a connection's effective upstream endpoint. Returns null if
// the provider key is unknown.
function resolveProvider(providerId) {
  return PROVIDER_CATALOG[providerId] || null;
}

async function handleChat(request, env, uid) {
  const body = await request.json();
  const gameId = body.gameId;
  const message = String(body.message || "");
  const files = body.files;
  const history = body.history;
  const providerId = body.provider;
  const model = body.model;
  const byok = body.byok || {};
  if (!gameId || !message) return json(400, { error: "gameId and message required" });
  const badId = validateGameId(gameId);
  if (badId) return json(400, { error: badId });
  if (!providerId || !model) return json(400, { error: "provider and model required" });
  if (!byok.apiKey) return json(400, { error: "byok.apiKey required" });

  const provider = resolveProvider(providerId);
  if (!provider) return json(400, { error: `unknown provider: ${providerId}` });

  // CONTEXT.md (engine philosophy) and API.md (function reference) are
  // ALWAYS included — API.md is the canonical whitelist that write_file
  // also enforces, so the model and the harness see the same source of
  // truth. AI-PITFALLS.md is added only when the user is debugging.
  const msgLower = message.toLowerCase();
  const isErrorFix = /fix|error|bug|crash|broken|fail|오류|수정|고쳐|에러|안.?[돼되]|안.?나/.test(msgLower);

  const docsToLoad = ["context", "api"];
  if (isErrorFix) docsToLoad.push("pitfalls");

  const docContents = await Promise.all(docsToLoad.map((n) => fetchDoc(n, env)));
  const engineDocs = docContents.join("\n\n---\n\n");

  // Build file context from current game files
  let fileContext = "";
  if (files && files.length > 0) {
    fileContext = "\n\n## Current Game Files\n\n";
    for (const f of files) {
      fileContext += `### ${f.name}\n\`\`\`lua\n${f.content}\n\`\`\`\n\n`;
    }
  }

  // Split the system prompt into a static prefix (engine docs + response
  // format + rules) and a dynamic suffix (current game files). The prefix
  // is stable across consecutive turns in a session, so Anthropic prompt
  // caching can reuse it — we mark it below with a cache_control breakpoint.
  // The files change often, so they stay outside the cache block.
  const systemPromptStatic = `You are Mono, an AI game developer for the Mono fantasy console.
You create and modify Lua games based on user requests.

${engineDocs}

## Response Format
Respond with a JSON object:
{
  "message": "Detailed explanation",
  "files": [
    { "name": "main.lua", "content": "-- full file content" }
  ]
}

The "message" field should include:
1. What you changed and why
2. Key functions or logic added/modified (names only — NO code)
3. Any tips or things to try next

Write the message in the same language the user used. Keep it concise — 2 to 4 short sentences total.

CRITICAL message rules:
- NEVER include code blocks (no \`\`\`lua, no inline \`code\`) in "message"
- NEVER paste source code, function bodies, or file contents in "message"
- All code goes in the "files" field ONLY
- If you need to reference a function, use its name without backticks

Rules:
- Always return complete file contents in "files", not diffs
- Follow the Mono engine API exactly — use surface-first drawing calls
- Games must have _init() and _draw(), optionally _update()
- Keep games simple and fun
- Use the scene system (go/title/game) for multi-scene games`;

  // Backward-compat concatenation for non-anthropic branches (openai,
  // gemini, responses) — they don't support cache markers.
  const systemPrompt = systemPromptStatic + fileContext;

  const messages = [];
  if (history) {
    for (const h of history) {
      messages.push({ role: h.role, content: h.content });
    }
  }
  messages.push({ role: "user", content: message });

  // Resolve upstream from the Connection's provider + BYOK fields.
  // baseUrl defaults to the catalog entry; Custom (or any user who
  // wants a relay) supplies byok.baseUrl to override.
  const baseUrl = (byok.baseUrl && byok.baseUrl.trim()) || provider.baseUrl;
  if (!baseUrl) return json(400, { error: "baseUrl required for this provider" });
  const apiKey = byok.apiKey;
  const modelName = model;
  const protocol = provider.protocol;

  let apiUrl;
  if (protocol === "gemini") {
    // Gemini derives the chat path per-model at request time.
    apiUrl = `${baseUrl.replace(/\/$/, "")}/models/${modelName}:generateContent?key=${apiKey}`;
  } else {
    apiUrl = baseUrl.replace(/\/$/, "") + provider.chatPath;
  }

  let aiRes, aiData, content;

  if (protocol === "anthropic") {
    // Anthropic Messages API — cache both the static prefix AND the file
    // context in separate ephemeral blocks. Two breakpoints:
    //   [1] docs + response format + rules (rarely changes)
    //   [2] full files dump (may or may not change per turn)
    // If files are unchanged between turns (e.g. user chats about the
    // code without editing), block [2] hits cache and costs ~10% of
    // fresh tokens. If files changed, block [2] rewrites the cache and
    // the next identical-files turn benefits. Block [1] still hits
    // independently whenever docs are stable.
    const systemBlocks = [
      { type: "text", text: systemPromptStatic, cache_control: { type: "ephemeral" } },
    ];
    if (fileContext) {
      systemBlocks.push({ type: "text", text: fileContext, cache_control: { type: "ephemeral" } });
    }
    aiRes = await fetch(apiUrl, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-api-key": apiKey,
        "anthropic-version": "2023-06-01",
      },
      body: JSON.stringify({
        model: modelName,
        max_tokens: 4096,
        system: systemBlocks,
        messages,
      }),
    });
    if (!aiRes.ok) { const err = await aiRes.text(); return json(502, { error: "AI request failed", detail: err }); }
    aiData = await aiRes.json();
    content = aiData.content?.[0]?.text || "";
    if (aiData.usage) {
      const u = aiData.usage;
      // Preserve Anthropic cache telemetry so the client can see hit rate.
      // cache_read_input_tokens > 0 on turn N≥2 means the cache_control
      // breakpoint landed a hit.
      aiData.usage = {
        prompt_tokens: u.input_tokens || 0,
        completion_tokens: u.output_tokens || 0,
        total_tokens: (u.input_tokens || 0) + (u.output_tokens || 0),
        cache_creation_input_tokens: u.cache_creation_input_tokens || 0,
        cache_read_input_tokens: u.cache_read_input_tokens || 0,
      };
    }

  } else if (protocol === "gemini") {
    // Google Gemini API — apiUrl already carries ?key=... from above.
    const geminiContents = [
      { role: "user", parts: [{ text: systemPrompt }] },
      { role: "model", parts: [{ text: "Understood. I will follow these instructions." }] },
      ...messages.map(m => ({
        role: m.role === "assistant" ? "model" : "user",
        parts: [{ text: m.content }],
      })),
    ];
    aiRes = await fetch(apiUrl, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ contents: geminiContents }),
    });
    if (!aiRes.ok) { const err = await aiRes.text(); return json(502, { error: "AI request failed", detail: err }); }
    aiData = await aiRes.json();
    content = aiData.candidates?.[0]?.content?.parts?.[0]?.text || "";
    const gUsage = aiData.usageMetadata;
    aiData.usage = gUsage ? {
      prompt_tokens: gUsage.promptTokenCount || 0,
      completion_tokens: gUsage.candidatesTokenCount || 0,
      total_tokens: gUsage.totalTokenCount || 0,
    } : undefined;

  } else {
    // OpenAI-compatible Chat Completions API (default)
    const aiMessages = [{ role: "system", content: systemPrompt }, ...messages];
    aiRes = await fetch(apiUrl, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${apiKey}`,
      },
      body: JSON.stringify({
        model: modelName,
        max_tokens: 4096,
        messages: aiMessages,
      }),
    });
    if (!aiRes.ok) { const err = await aiRes.text(); return json(502, { error: "AI request failed", detail: err }); }
    aiData = await aiRes.json();
    content = aiData.choices?.[0]?.message?.content || "";
  }

  // Parse AI response — extract JSON from response
  let parsed;
  try {
    const jsonMatch = content.match(/\{[\s\S]*\}/);
    parsed = jsonMatch ? JSON.parse(jsonMatch[0]) : { message: content, files: [] };
  } catch {
    parsed = { message: content, files: [] };
  }

  // Save files to R2
  if (parsed.files && parsed.files.length > 0) {
    const prefix = `${uid}/${gameId}/`;
    for (const f of parsed.files) {
      await env.BUCKET.put(prefix + f.name, f.content, {
        httpMetadata: { contentType: "text/plain" },
      });
    }
  }

  // Attach usage info and accumulate
  if (aiData.usage) {
    parsed.usage = {
      prompt_tokens: aiData.usage.prompt_tokens,
      completion_tokens: aiData.usage.completion_tokens,
      total_tokens: aiData.usage.total_tokens,
    };

    // Accumulate game-level usage in R2
    const usageKey = `${uid}/${gameId}/_usage.json`;
    let gameUsage = { prompt_tokens: 0, completion_tokens: 0, total_tokens: 0 };
    try {
      const existing = await env.BUCKET.get(usageKey);
      if (existing) gameUsage = JSON.parse(await existing.text());
    } catch {}
    gameUsage.prompt_tokens += parsed.usage.prompt_tokens;
    gameUsage.completion_tokens += parsed.usage.completion_tokens;
    gameUsage.total_tokens += parsed.usage.total_tokens;
    await env.BUCKET.put(usageKey, JSON.stringify(gameUsage), {
      httpMetadata: { contentType: "application/json" },
    });
    parsed.gameUsage = gameUsage;

    // Accumulate user-level usage in R2
    const userUsageKey = `${uid}/_usage.json`;
    let userUsage = { prompt_tokens: 0, completion_tokens: 0, total_tokens: 0 };
    try {
      const existing = await env.BUCKET.get(userUsageKey);
      if (existing) userUsage = JSON.parse(await existing.text());
    } catch {}
    userUsage.prompt_tokens += parsed.usage.prompt_tokens;
    userUsage.completion_tokens += parsed.usage.completion_tokens;
    userUsage.total_tokens += parsed.usage.total_tokens;
    await env.BUCKET.put(userUsageKey, JSON.stringify(userUsage), {
      httpMetadata: { contentType: "application/json" },
    });
    parsed.userUsage = userUsage;
  }

  return json(200, parsed);
}

async function fetchDoc(name, env) {
  const url = docUrls(env)[name];
  if (!url) return "";
  const key = `${docsBase(env)}::${name}`;
  if (docCache[key] && Date.now() < (docExpiry[key] || 0)) return docCache[key];
  try {
    const res = await fetch(url);
    if (res.ok) {
      docCache[key] = await res.text();
      docExpiry[key] = Date.now() + 3600_000;
    }
  } catch {}
  return docCache[key] || "";
}

// ── R2 operations ──

async function listFiles(env, prefix) {
  const list = await env.BUCKET.list({ prefix });
  const files = list.objects.map((o) => ({
    name: o.key.slice(prefix.length),
    size: o.size,
    updated: o.uploaded.toISOString(),
  }));
  return json(200, { files });
}

async function getFile(env, key) {
  const obj = await env.BUCKET.get(key);
  if (!obj) return json(404, { error: "File not found" });
  // Binary files (images) — return raw with content-type
  const ct = obj.httpMetadata?.contentType || "";
  if (ct.startsWith("image/") || /\.(png|jpg|jpeg|gif|bmp|webp)$/i.test(key)) {
    return new Response(obj.body, {
      headers: {
        "Content-Type": ct || "application/octet-stream",
        "Access-Control-Allow-Origin": "*",
      },
    });
  }
  const body = await obj.text();
  return json(200, { content: body });
}

async function putFile(env, key, request) {
  const ct = request.headers.get("Content-Type") || "";
  if (ct === "application/octet-stream" || ct.startsWith("image/")) {
    // Binary upload (e.g. thumbnail.png)
    const body = await request.arrayBuffer();
    if (body.byteLength > 256 * 1024) return json(400, { error: "File too large (max 256KB)" });
    await env.BUCKET.put(key, body, { httpMetadata: { contentType: ct } });
    return json(200, { ok: true });
  }
  const { content } = await request.json();
  if (typeof content !== "string") return json(400, { error: "content must be a string" });
  if (content.length > 256 * 1024) return json(400, { error: "File too large (max 256KB)" });
  await env.BUCKET.put(key, content, { httpMetadata: { contentType: "text/plain" } });
  return json(200, { ok: true });
}

async function deleteFile(env, key) {
  await env.BUCKET.delete(key);
  return json(200, { ok: true });
}

// ── Agent (OpenAI-compat tool-use loop) ──
// Required provider protocol: openai. Anthropic/Gemini fall back to /chat
// via the client-side fallback. Streams progress as Server-Sent Events so
// the dev editor can render "📖 read_file main.lua ✓" style cards in
// real time. File I/O goes straight to R2.

import { lintEnginePrimitiveOverwrite } from "./lib/lint.js";
import { validateAgentPath, validateGameId } from "./lib/path.js";
import { extractApiWhitelist, lintApiCompliance, collectFileDefinedNames } from "./lib/api-lint.js";
import { AGENT_TOOLS, AGENT_MAX_ITER, buildAgentSystemPrompt } from "./lib/agent-prompt.js";

// Append-only audit trail for write_file rejections. Each rejection
// becomes its own R2 object so concurrent writes don't race; the ISO
// timestamp prefix sorts oldest-first so list().reverse() gives newest.
// Best-effort: failures here must NEVER break the agent loop.
async function logLintRejection(env, uid, payload) {
  try {
    const isoTs = new Date().toISOString();
    const day = isoTs.slice(0, 10); // 2026-04-29
    const ts = isoTs.replace(/[:.]/g, "-");
    const rand = Math.random().toString(36).slice(2, 8);
    // Date-bucketed key — `${uid}/_admin/lint-reject/2026-04-29/...`.
    // Future cleanup can drop whole day prefixes via list(prefix).delete().
    const key = `${uid}/_admin/lint-reject/${day}/${ts}-${rand}.json`;
    const body = JSON.stringify({ ts: isoTs, ...payload });
    await env.BUCKET.put(key, body, {
      httpMetadata: { contentType: "application/json" },
    });
  } catch (e) {
    console.error("[LINT-LOG] failed:", e?.message || e);
  }
}

async function handleListLintRejects(env, uid, url) {
  const limit = Math.min(parseInt(url.searchParams.get("limit") || "20", 10) || 20, 100);
  const prefix = `${uid}/_admin/lint-reject/`;
  // R2 list returns alphabetical by key. ISO timestamps sort oldest
  // first, so reverse to get newest. Cap window at 1000 (R2's per-list
  // ceiling) — `windowed` reflects what we actually scanned, not the
  // true total, so the response can't claim more than it knows.
  const list = await env.BUCKET.list({ prefix, limit: 1000 });
  const sorted = list.objects.slice().reverse().slice(0, limit);
  const items = await Promise.all(sorted.map(async (obj) => {
    const o = await env.BUCKET.get(obj.key);
    if (!o) return null;
    try {
      return { key: obj.key.slice(prefix.length), ...JSON.parse(await o.text()) };
    } catch {
      return { key: obj.key.slice(prefix.length), error: "parse_failed" };
    }
  }));
  return json(200, {
    returned: items.filter(Boolean).length,
    windowed: list.objects.length,
    windowCapped: Boolean(list.truncated),
    items: items.filter(Boolean),
  });
}

// Collect every identifier defined in any sibling .lua file under
// `prefix`, excluding `excludePath`. Mono games use cross-file globals
// (main.lua declares helpers, scene files call them), so the lint must
// see the union before deciding what's "unknown".
//
// `cache` (optional) is a turn-scoped `{ signature, set }` slot. We
// list R2 first to compute a content signature (sorted "name:size"
// entries minus the excludePath), and only re-read the .lua bodies if
// that signature changed since the previous call in the same turn —
// usually it won't, so multi-write turns drop from O(N writes × N
// files) R2 GETs to O(N files) once.
async function collectProjectGlobals(env, prefix, excludePath, cache, writesSoFar) {
  // Single pass: list everything, then decide if cache hit applies.
  const objs = [];
  let cursor;
  do {
    const list = await env.BUCKET.list({ prefix, cursor });
    for (const obj of list.objects) {
      const name = obj.key.slice(prefix.length);
      if (!name.endsWith(".lua")) continue;
      if (name === excludePath) continue;
      objs.push({ key: obj.key, name, size: obj.size });
    }
    cursor = list.truncated ? list.cursor : undefined;
  } while (cursor);

  // Signature mixes (name:size) per file with `writesSoFar` — the
  // monotonically growing count of successful writes this turn. The
  // size-based component catches the common case (sibling created /
  // grew / shrank); writesSoFar covers the contrived case where a
  // sibling was rewritten with the same byte count but different
  // contents (e.g. function rename without changing length).
  const signature = objs
    .map((o) => `${o.name}:${o.size}`)
    .sort()
    .join("|") + `|w:${writesSoFar ?? 0}`;
  if (cache && cache.signature === signature && cache.set) return cache.set;

  const reads = objs.map(async (o) => {
    const got = await env.BUCKET.get(o.key);
    if (!got) return null;
    return collectFileDefinedNames(await got.text());
  });
  const results = await Promise.all(reads);
  const set = new Set();
  for (const r of results) if (r) for (const n of r) set.add(n);

  if (cache) {
    cache.signature = signature;
    cache.set = set;
  }
  return set;
}

// Returns the parsed API.md whitelist, re-parsing only when the cached
// API.md text changes. Returns null if the doc fetch failed — callers
// must fail-open in that case (lintApiCompliance does this internally).
async function getApiWhitelist(env) {
  const md = await fetchDoc("api", env);
  if (!md) return null;
  if (apiWhitelistSource !== md) {
    apiWhitelistSource = md;
    apiWhitelistCache = extractApiWhitelist(md);
  }
  return apiWhitelistCache;
}

async function execAgentTool(name, input, ctx) {
  const { env, uid, gameId, changed } = ctx;
  const prefix = `${uid}/${gameId}/`;

  switch (name) {
    case "list_files": {
      const files = [];
      let cursor;
      do {
        const list = await env.BUCKET.list({ prefix, cursor });
        for (const obj of list.objects) {
          const name = obj.key.slice(prefix.length);
          if (name.startsWith("_")) continue; // hide chat history etc
          files.push({ name, size: obj.size });
        }
        cursor = list.truncated ? list.cursor : undefined;
      } while (cursor);
      return { files };
    }
    case "read_file": {
      const bad = validateAgentPath(input?.path);
      if (bad) return { error: bad };
      const obj = await env.BUCKET.get(prefix + input.path);
      if (!obj) return { error: `file not found: ${input.path}` };
      return { path: input.path, content: await obj.text() };
    }
    case "write_file": {
      const bad = validateAgentPath(input?.path);
      if (bad) return { error: bad };
      if (typeof input.content !== "string") return { error: "content must be a string" };
      if (input.content.length > 256 * 1024) return { error: "file too large (max 256KB)" };
      // Harness: for Lua files, reject writes that shadow engine primitives
      // or call functions outside API.md BEFORE hitting R2 so the agent
      // can self-correct in the next iteration. Every rejection is logged
      // to R2 (under `${uid}/_admin/lint-reject/`) so the developer can
      // audit false positives later via /admin/lint-rejects.
      if (input.path.endsWith(".lua")) {
        const violation = lintEnginePrimitiveOverwrite(input.content);
        if (violation) {
          await logLintRejection(env, uid, {
            kind: "engine_primitive",
            gameId, path: input.path,
            size: input.content.length,
            reason: violation,
            snippet: input.content.slice(0, 500),
          });
          return { error: `write_file blocked for ${input.path}: ${violation}` };
        }
        const whitelist = await getApiWhitelist(env);
        const projectDefined = await collectProjectGlobals(
          env, prefix, input.path,
          ctx.projectGlobalsCache,
          changed.size,
        );
        const apiViolations = lintApiCompliance(input.content, whitelist, { projectDefined });
        if (apiViolations.length > 0) {
          const list = apiViolations
            .map((v) => `${v.name}() at line ${v.line}`)
            .join(", ");
          await logLintRejection(env, uid, {
            kind: "api_compliance",
            gameId, path: input.path,
            size: input.content.length,
            violations: apiViolations,
            snippet: input.content.slice(0, 500),
          });
          return {
            error: `write_file blocked for ${input.path}: unknown function call(s) — ${list}. Only functions documented in docs/API.md may be used. If this is a user-defined helper, define it in this file before calling it.`,
          };
        }
      }
      await env.BUCKET.put(prefix + input.path, input.content, {
        httpMetadata: { contentType: "text/plain" },
      });
      changed.set(input.path, { action: "write", size: input.content.length });
      return { ok: true, path: input.path, bytes: input.content.length };
    }
    case "delete_file": {
      const bad = validateAgentPath(input?.path);
      if (bad) return { error: bad };
      await env.BUCKET.delete(prefix + input.path);
      changed.set(input.path, { action: "delete" });
      return { ok: true, path: input.path };
    }
    default:
      return { error: `unknown tool: ${name}` };
  }
}

async function handleAgent(request, env, uid) {
  const body = await request.json().catch(() => ({}));
  const { gameId, message, history, provider: providerId, model } = body;
  const byok = body.byok || {};
  if (!gameId || !message) return json(400, { error: "gameId and message required" });
  const badId = validateGameId(gameId);
  if (badId) return json(400, { error: badId });
  if (!providerId || !model) return json(400, { error: "provider and model required" });
  if (!byok.apiKey) return json(400, { error: "byok.apiKey required" });

  const provider = resolveProvider(providerId);
  if (!provider) return json(400, { error: `unknown provider: ${providerId}` });
  // Agent path requires openai-compat tool_use protocol.
  if (provider.protocol !== "openai") {
    return json(400, { error: `agent loop requires openai protocol, got ${provider.protocol}` });
  }

  const baseUrl = (byok.baseUrl && byok.baseUrl.trim()) || provider.baseUrl;
  if (!baseUrl) return json(400, { error: "baseUrl required for this provider" });
  const apiUrl = baseUrl.replace(/\/$/, "") + provider.chatPath;
  const apiKey = byok.apiKey;
  const modelName = model;

  // System prompt — agent-style (no file dump; LLM uses tools to inspect).
  // Built from the shared lib so the eval harness sees the exact same
  // text. API.md is appended verbatim inside buildAgentSystemPrompt so
  // the model and the write_file harness share one source of truth.
  const apiDoc = await fetchDoc("api", env);
  const systemPrompt = buildAgentSystemPrompt(apiDoc);

  const messages = [{ role: "system", content: systemPrompt }];
  for (const h of (history || [])) {
    messages.push({ role: h.role, content: h.content });
  }
  messages.push({ role: "user", content: message });

  // SSE stream setup.
  const { readable, writable } = new TransformStream();
  const writer = writable.getWriter();
  const enc = new TextEncoder();
  const send = (event, data) => writer.write(enc.encode(
    `event: ${event}\ndata: ${JSON.stringify(data)}\n\n`
  ));

  // Run the loop without awaiting — so the response starts streaming
  // immediately. Errors route to an SSE error event.
  (async () => {
    // projectGlobalsCache is a turn-scoped { signature, set } cache so
    // the cross-file globals scan doesn't re-list+re-read R2 on every
    // write_file in the same turn. Signature = sorted list of "name:size"
    // — invalidated automatically the moment a sibling .lua write changes
    // its size.
    const ctx = { env, uid, gameId, changed: new Map(), projectGlobalsCache: { signature: null, set: null } };
    const usage = { prompt_tokens: 0, completion_tokens: 0, total_tokens: 0 };
    const MAX_ITER = AGENT_MAX_ITER;

    try {
      for (let iter = 0; iter < MAX_ITER; iter++) {
        const res = await fetch(apiUrl, {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            "Authorization": `Bearer ${apiKey}`,
          },
          body: JSON.stringify({
            model: modelName,
            messages,
            tools: AGENT_TOOLS,
            tool_choice: "auto",
            stream: true,
            stream_options: { include_usage: true },
          }),
        });

        if (!res.ok) {
          const detail = (await res.text()).slice(0, 500);
          await send("error", { message: `upstream ${res.status}`, detail });
          break;
        }

        // Consume the upstream SSE stream, forwarding content deltas as
        // `event: token` and accumulating tool_calls until the turn ends.
        const reader = res.body.getReader();
        const dec = new TextDecoder();
        let sseBuf = "";
        let content = "";
        let reasoning = "";
        const toolAcc = new Map(); // index → { id, name, argsStr }
        let finish = null;
        let usageChunk = null;

        streamLoop: while (true) {
          const { value, done } = await reader.read();
          if (done) break;
          sseBuf += dec.decode(value, { stream: true });
          let idx;
          while ((idx = sseBuf.indexOf("\n\n")) !== -1) {
            const frame = sseBuf.slice(0, idx);
            sseBuf = sseBuf.slice(idx + 2);
            let dataStr = "";
            for (const line of frame.split("\n")) {
              if (line.startsWith("data:")) dataStr += line.slice(5).trim();
            }
            if (!dataStr) continue;
            if (dataStr === "[DONE]") break streamLoop;
            let chunk;
            try { chunk = JSON.parse(dataStr); } catch { continue; }
            if (chunk.usage) usageChunk = chunk.usage;
            const choice = chunk.choices?.[0];
            if (!choice) continue;
            if (choice.finish_reason) finish = choice.finish_reason;
            const d = choice.delta;
            if (!d) continue;
            if (d.reasoning_content) {
              // Forward each reasoning delta immediately so the client can
              // display the model's thinking live — same cadence as token
              // streaming. Server still accumulates into `reasoning` for
              // round-tripping on the assistant turn (some reasoning-mode
              // providers reject turns that drop reasoning_content).
              reasoning += d.reasoning_content;
              await send("reasoning", { text: d.reasoning_content });
            }
            if (typeof d.content === "string" && d.content) {
              content += d.content;
              await send("token", { text: d.content });
            }
            if (Array.isArray(d.tool_calls)) {
              for (const tc of d.tool_calls) {
                const i = tc.index ?? 0;
                let acc = toolAcc.get(i);
                if (!acc) { acc = { id: "", name: "", argsStr: "" }; toolAcc.set(i, acc); }
                if (tc.id) acc.id = tc.id;
                if (tc.function?.name) acc.name = tc.function.name;
                if (tc.function?.arguments) acc.argsStr += tc.function.arguments;
              }
            }
          }
        }

        if (usageChunk) {
          usage.prompt_tokens     += usageChunk.prompt_tokens     || 0;
          usage.completion_tokens += usageChunk.completion_tokens || 0;
          usage.total_tokens      += usageChunk.total_tokens      || 0;
        }
        // Reasoning is now forwarded delta-by-delta inside the stream
        // loop; no end-of-turn bulk emit here.

        const toolCalls = [...toolAcc.values()]
          .filter(t => t.name)
          .map((t, k) => ({
            id: t.id || `tc-${iter}-${k}`,
            type: "function",
            function: { name: t.name, arguments: t.argsStr },
          }));

        // Done — no tool calls, the streamed content IS the final reply.
        if (toolCalls.length === 0) {
          const changedFiles = [];
          for (const [path, info] of ctx.changed) {
            changedFiles.push({ name: path, action: info.action, size: info.size || 0 });
          }
          await send("final", { text: content, changed: changedFiles, usage, iterations: iter + 1 });
          break;
        }

        // Continue the conversation: keep the assistant turn (with tool_calls)
        // verbatim, then feed each tool result back as role:"tool".
        // Reasoning-mode providers require reasoning_content round-tripped
        // back on multi-turn assistant messages, else the next turn 400s
        // with errors like "thinking is enabled but reasoning content is
        // missing".
        const assistantTurn = { role: "assistant", content, tool_calls: toolCalls };
        if (reasoning) assistantTurn.reasoning_content = reasoning;
        messages.push(assistantTurn);
        for (const tc of toolCalls) {
          const name = tc.function.name;
          let input = {};
          try { input = JSON.parse(tc.function.arguments || "{}"); } catch {}
          await send("tool_start", { id: tc.id, name, input });
          const result = await execAgentTool(name, input, ctx);
          await send("tool_result", {
            id: tc.id,
            name,
            ok: !result.error,
            summary: summarizeToolResult(name, result),
          });
          messages.push({
            role: "tool",
            tool_call_id: tc.id,
            content: JSON.stringify(result).slice(0, 200 * 1024),
          });
        }

        if (finish === "stop") {
          // finish=stop with tool_calls is unusual but would otherwise loop.
          await send("final", { text: content, changed: [], usage, iterations: iter + 1 });
          break;
        }
      }
    } catch (e) {
      await send("error", { message: e.message || String(e) });
    } finally {
      await writer.close();
    }
  })();

  return new Response(readable, {
    status: 200,
    headers: {
      "Content-Type": "text/event-stream",
      "Cache-Control": "no-cache",
      "Connection": "keep-alive",
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Headers": "Authorization, Content-Type",
    },
  });
}

function summarizeToolResult(name, result) {
  if (result.error) return result.error;
  switch (name) {
    case "list_files": return `${result.files?.length || 0} files`;
    case "read_file":  return `${result.content?.length || 0} bytes`;
    case "write_file": return `wrote ${result.bytes || 0} bytes`;
    case "delete_file":return "deleted";
  }
  return "ok";
}

// ── Model list proxy ──
// Queries the provider's /models endpoint live so the client can
// populate the Connection editor's model dropdown without the server
// carrying a hardcoded model list. Accepts { provider, apiKey,
// baseUrl? } — provider is the catalog key, baseUrl is an optional
// override (required for "custom"). Returns the normalized list.
async function handleListModels(request, env, uid) {
  const body = await request.json().catch(() => ({}));
  const { provider: providerId, apiKey, baseUrl: rawBaseUrl } = body;
  if (!apiKey) return json(400, { error: "apiKey required" });
  if (!providerId) return json(400, { error: "provider required" });

  const provider = resolveProvider(providerId);
  if (!provider) return json(400, { error: `unknown provider: ${providerId}` });

  const baseUrl = (rawBaseUrl && rawBaseUrl.trim()) || provider.baseUrl;
  if (!baseUrl) return json(400, { error: "baseUrl required for this provider" });

  const modelsUrl = baseUrl.replace(/\/$/, "") + provider.modelsPath;
  const headers = provider.auth === "x-api-key"
    ? { "x-api-key": apiKey, "anthropic-version": "2023-06-01" }
    : provider.auth === "query-key"
      ? {} // key goes in query string for gemini, appended below
      : { "Authorization": `Bearer ${apiKey}` };

  const finalUrl = provider.auth === "query-key"
    ? `${modelsUrl}?key=${encodeURIComponent(apiKey)}`
    : modelsUrl;

  let upstream;
  try {
    upstream = await fetch(finalUrl, { headers });
  } catch (e) {
    console.error(`[/models] fetch failed url=${modelsUrl} err=${e.message}`);
    return json(502, { error: "upstream fetch failed" });
  }
  if (!upstream.ok) {
    // Drain the body so the connection can close cleanly, but do NOT
    // log it — upstream error bodies can carry keys in URLs, internal
    // paths, and stack traces, and CF Worker logs can be retained for
    // a long time. Status + url is enough to triage.
    upstream.text().catch(() => "");
    console.error(`[/models] upstream ${upstream.status} url=${modelsUrl}`);
    return json(502, { error: `upstream ${upstream.status}` });
  }
  const data = await upstream.json().catch(() => null);
  if (!data) return json(502, { error: "upstream returned non-JSON" });

  // Normalize across different provider response shapes.
  let models = [];
  if (Array.isArray(data.data)) {
    // OpenAI-style — `{data: [{id, ...}]}` (OpenAI, Anthropic post-2024,
    // Moonshot, most OpenAI-compat relays).
    models = data.data.map(m => ({
      id: m.id || m.model || m.name,
      context: m.context_length || m.context_window || null,
      reasoning: !!m.supports_reasoning,
      vision: !!m.supports_image_in || !!m.supports_vision,
    })).filter(m => m.id);
  } else if (Array.isArray(data.models)) {
    // Gemini — `{models: [{name: "models/gemini-...", ...}]}`
    models = data.models.map(m => ({
      id: m.name?.startsWith("models/") ? m.name.slice(7) : m.name,
      context: m.inputTokenLimit || null,
    })).filter(m => m.id);
  }

  return json(200, { models });
}

// ── Publish ──

async function handlePublish(env, uid, gameId) {
  // Verify ownership: uid must match the game's owner in Firestore
  try {
    const token = await getAccessToken(env);
    const docUrl = `https://firestore.googleapis.com/v1/projects/${env.FIREBASE_PROJECT_ID}/databases/(default)/documents/games/${gameId}`;
    const docRes = await fetch(docUrl, { headers: { Authorization: `Bearer ${token}` } });
    if (!docRes.ok) return json(404, { error: "Game not found" });
    const docData = await docRes.json();
    const ownerUid = docData.fields?.uid?.stringValue;
    if (ownerUid !== uid) return json(403, { error: "Not your game" });
  } catch (e) {
    return json(500, { error: "Ownership check failed: " + e.message });
  }

  const prefix = `${uid}/${gameId}/`;

  // List current game files (exclude _ prefixed meta files, handle pagination)
  let allDevObjects = [];
  let devCursor;
  do {
    const list = await env.BUCKET.list({ prefix, cursor: devCursor });
    allDevObjects.push(...list.objects);
    devCursor = list.truncated ? list.cursor : undefined;
  } while (devCursor);
  const gameFiles = allDevObjects.filter(o => {
    const name = o.key.slice(prefix.length);
    return !name.startsWith("_");
  });

  if (gameFiles.length === 0) return json(400, { error: "No files to publish" });

  // Check main.lua exists
  const hasMain = gameFiles.some(o => o.key.slice(prefix.length) === "main.lua");
  if (!hasMain) return json(400, { error: "main.lua is required" });

  // Determine version number
  const metaKey = `published/${gameId}/_meta.json`;
  let meta = { version: 0, uid };
  try {
    const existing = await env.BUCKET.get(metaKey);
    if (existing) meta = JSON.parse(await existing.text());
  } catch {}
  const version = meta.version + 1;

  // Copy files to published/{gameId}/v{version}/ and published/{gameId}/latest/
  // Parallel copy to avoid Worker timeout on many files
  await Promise.all(gameFiles.map(async (obj) => {
    const name = obj.key.slice(prefix.length);
    const content = await env.BUCKET.get(obj.key);
    if (!content) return;
    const body = await content.arrayBuffer();
    const ct = { httpMetadata: { contentType: content.httpMetadata?.contentType || "text/plain" } };
    await Promise.all([
      env.BUCKET.put(`published/${gameId}/v${version}/${name}`, body, ct),
      env.BUCKET.put(`published/${gameId}/latest/${name}`, new Uint8Array(body), ct),
    ]);
  }));

  // Update R2 meta + Firestore (parallel — both must succeed)
  const publishedAt = new Date().toISOString();
  meta = { version, uid, publishedAt };
  try {
    await Promise.all([
      env.BUCKET.put(metaKey, JSON.stringify(meta), {
        httpMetadata: { contentType: "application/json" },
      }),
      firestorePatch(env, `games/${gameId}`, {
        status: { stringValue: "published" },
        publishedVersion: { integerValue: String(version) },
        publishedAt: { timestampValue: publishedAt },
      }),
    ]);
  } catch (e) {
    // Rollback: clean up latest/ so state is consistent
    await Promise.all(gameFiles.map(async (obj) => {
      const name = obj.key.slice(prefix.length);
      await env.BUCKET.delete(`published/${gameId}/latest/${name}`).catch(() => {});
    }));
    await env.BUCKET.delete(metaKey).catch(() => {});
    throw e; // will be caught by outer try/catch → 500
  }

  // Clean up old version snapshots (keep last 3)
  const KEEP_VERSIONS = 3;
  if (version > KEEP_VERSIONS) {
    const deleteUpTo = version - KEEP_VERSIONS;
    for (let v = 1; v <= deleteUpTo; v++) {
      const vPrefix = `published/${gameId}/v${v}/`;
      let delCursor;
      do {
        const list = await env.BUCKET.list({ prefix: vPrefix, cursor: delCursor });
        if (list.objects.length === 0) break;
        await Promise.all(list.objects.map(o => env.BUCKET.delete(o.key)));
        delCursor = list.truncated ? list.cursor : undefined;
      } while (delCursor);
    }
  }

  return json(200, { success: true, version });
}

async function handleUnpublish(env, uid, gameId) {
  // Verify ownership via R2 meta
  const metaKey = `published/${gameId}/_meta.json`;
  const existing = await env.BUCKET.get(metaKey);
  if (!existing) return json(404, { error: "Game not published" });
  const existingMeta = JSON.parse(await existing.text());
  if (existingMeta.uid !== uid) return json(403, { error: "Not your game" });

  // Delete latest/ files (handle pagination)
  const latestPrefix = `published/${gameId}/latest/`;
  let delCursor;
  do {
    const list = await env.BUCKET.list({ prefix: latestPrefix, cursor: delCursor });
    for (const obj of list.objects) await env.BUCKET.delete(obj.key);
    delCursor = list.truncated ? list.cursor : undefined;
  } while (delCursor);

  // Mark as unpublished in meta (keep version history)
  const metaObj = await env.BUCKET.get(metaKey);
  let meta = metaObj ? JSON.parse(await metaObj.text()) : {};
  meta.unpublished = true;
  meta.unpublishedAt = new Date().toISOString();
  await env.BUCKET.put(metaKey, JSON.stringify(meta), {
    httpMetadata: { contentType: "application/json" },
  });

  // Update Firestore
  await firestorePatch(env, `games/${gameId}`, {
    status: { stringValue: "draft" },
  });

  return json(200, { success: true });
}

async function handleGetPublished(env, gameId) {
  // Check meta
  const metaKey = `published/${gameId}/_meta.json`;
  const metaObj = await env.BUCKET.get(metaKey);
  if (!metaObj) return json(404, { error: "Game not found" });
  const meta = JSON.parse(await metaObj.text());
  if (meta.unpublished) return json(404, { error: "Game not published" });

  // List latest files (handle pagination)
  const prefix = `published/${gameId}/latest/`;
  let allObjects = [];
  let cursor;
  do {
    const list = await env.BUCKET.list({ prefix, cursor });
    allObjects.push(...list.objects);
    cursor = list.truncated ? list.cursor : undefined;
  } while (cursor);
  if (allObjects.length === 0) return json(404, { error: "No published files" });

  // Text extensions are inlined as UTF-8 strings; everything else is
  // returned base64-encoded with an explicit `encoding` field so the
  // public play.html can decode binary assets (images, etc.) without
  // needing an authenticated R2 fetch. Matches handlePublish's parallel
  // fetch style so response latency scales with slowest file, not sum.
  const TEXT_EXT = /\.(lua|json|md|txt)$/i;
  const files = (await Promise.all(allObjects.map(async (obj) => {
    const name = obj.key.slice(prefix.length);
    if (name === "thumbnail.png") return null; // served separately at /thumbnail
    if (name.startsWith("_")) return null;     // internal meta files (future-proofing)
    const content = await env.BUCKET.get(obj.key);
    if (!content) return null;
    if (TEXT_EXT.test(name)) {
      return { name, content: await content.text() };
    }
    const bin = new Uint8Array(await content.arrayBuffer());
    // Chunked String.fromCharCode to avoid call-stack limits on larger
    // binaries (images of a few KB are fine, but keep this robust).
    let s = "";
    const CHUNK = 8192;
    for (let i = 0; i < bin.length; i += CHUNK) {
      s += String.fromCharCode.apply(null, bin.subarray(i, i + CHUNK));
    }
    return { name, content: btoa(s), encoding: "base64" };
  }))).filter(Boolean);

  return json(200, { title: meta.title || "", version: meta.version, files });
}

async function handleGetThumbnail(env, gameId) {
  // Try to serve a thumbnail image from published files
  const key = `published/${gameId}/latest/thumbnail.png`;
  const obj = await env.BUCKET.get(key);
  if (!obj) {
    // Return a 1x1 transparent PNG as fallback
    return new Response(null, { status: 404, headers: { "Access-Control-Allow-Origin": "*" } });
  }
  return new Response(obj.body, {
    headers: {
      "Content-Type": "image/png",
      "Access-Control-Allow-Origin": "*",
      "Cache-Control": "public, max-age=3600",
    },
  });
}

// ── Firestore (service account) ──

let cachedAccessToken = null;
let accessTokenExpiry = 0;

async function getAccessToken(env) {
  if (cachedAccessToken && Date.now() < accessTokenExpiry) return cachedAccessToken;

  const now = Math.floor(Date.now() / 1000);
  const header = { alg: "RS256", typ: "JWT" };
  const payload = {
    iss: env.FIREBASE_CLIENT_EMAIL,
    sub: env.FIREBASE_CLIENT_EMAIL,
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
    scope: "https://www.googleapis.com/auth/datastore",
  };

  const enc = (obj) => btoa(JSON.stringify(obj)).replace(/=/g, "").replace(/\+/g, "-").replace(/\//g, "_");
  const signingInput = enc(header) + "." + enc(payload);

  // Import RSA private key
  const pem = env.FIREBASE_PRIVATE_KEY.replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\n/g, "");
  const keyData = Uint8Array.from(atob(pem), c => c.charCodeAt(0));
  const key = await crypto.subtle.importKey("pkcs8", keyData, { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"]);

  // Sign
  const sig = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(signingInput));
  const sigB64 = btoa(String.fromCharCode(...new Uint8Array(sig))).replace(/=/g, "").replace(/\+/g, "-").replace(/\//g, "_");
  const jwt = signingInput + "." + sigB64;

  // Exchange for access token
  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${jwt}`,
  });
  const data = await res.json();
  if (!data.access_token) throw new Error("Failed to get access token: " + JSON.stringify(data));

  cachedAccessToken = data.access_token;
  accessTokenExpiry = Date.now() + (data.expires_in - 60) * 1000;
  return cachedAccessToken;
}

async function firestorePatch(env, docPath, fields) {
  const token = await getAccessToken(env);
  const projectId = env.FIREBASE_PROJECT_ID;
  const url = `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents/${docPath}?` +
    Object.keys(fields).map(k => `updateMask.fieldPaths=${k}`).join("&");
  const res = await fetch(url, {
    method: "PATCH",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${token}`,
    },
    body: JSON.stringify({ fields }),
  });
  if (!res.ok) {
    const err = await res.text();
    throw new Error(`Firestore update failed: ${err}`);
  }
}

// ── Auth ──

const GOOGLE_JWK_URL = "https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com";
let cachedKeys = null;
let keysExpiry = 0;

async function verifyAuth(request, env) {
  const header = request.headers.get("Authorization");
  if (!header || !header.startsWith("Bearer ")) return null;
  const token = header.slice(7);

  const parts = token.split(".");
  if (parts.length !== 3) return null;

  const headerJson = JSON.parse(atob(parts[0].replace(/-/g, "+").replace(/_/g, "/")));
  const payload = JSON.parse(atob(parts[1].replace(/-/g, "+").replace(/_/g, "/")));

  // Claims check
  const now = Math.floor(Date.now() / 1000);
  if (payload.iss !== `https://securetoken.google.com/${env.FIREBASE_PROJECT_ID}`) return null;
  if (payload.aud !== env.FIREBASE_PROJECT_ID) return null;
  if (payload.exp < now) return null;
  if (payload.iat > now + 5) return null;

  // Get JWK keys and find matching kid
  const keys = await getGoogleKeys();
  const jwk = keys.find((k) => k.kid === headerJson.kid);
  if (!jwk) return null;

  const key = await crypto.subtle.importKey("jwk", jwk, { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["verify"]);
  const data = new TextEncoder().encode(parts[0] + "." + parts[1]);
  const signature = Uint8Array.from(atob(parts[2].replace(/-/g, "+").replace(/_/g, "/")), (c) => c.charCodeAt(0));

  const valid = await crypto.subtle.verify("RSASSA-PKCS1-v1_5", key, signature, data);
  return valid ? payload.sub : null;
}

async function getGoogleKeys() {
  if (cachedKeys && Date.now() < keysExpiry) return cachedKeys;
  const res = await fetch(GOOGLE_JWK_URL);
  const data = await res.json();
  cachedKeys = data.keys;
  const maxAge = res.headers.get("cache-control")?.match(/max-age=(\d+)/)?.[1];
  keysExpiry = Date.now() + (maxAge ? parseInt(maxAge) * 1000 : 3600_000);
  return cachedKeys;
}

// ── Helpers ──

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

function corsResponse() {
  return new Response(null, {
    status: 204,
    headers: {
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Methods": "GET, POST, PUT, DELETE, OPTIONS",
      "Access-Control-Allow-Headers": "Authorization, Content-Type",
      "Access-Control-Max-Age": "86400",
    },
  });
}
