// End-to-end netplay signaling test via Puppeteer + real Firestore.
//
// Spins up a local HTTP server, opens N puppeteer pages simultaneously
// (staggered by ~150 ms — well within the ICE-gathering window that
// triggers the legacy race), watches each page's console for the
// matchmaker's role assignment, and asserts everyone reached
// "Opening data channel…" — i.e. signaling completed.
//
// We do NOT assert the WebRTC DataChannel actually opens. Two puppeteer
// browser contexts on the same host frequently can't establish a peer
// connection (mDNS-hidden host IPs, headless-Chrome WebRTC quirks); the
// failure mode is environmental, not in the matchmaker. The signaling
// phase is what this test guards.
//
// Hits the production Firestore project (mono-5b951). Each test uses
// the pong-2p cart param; rooms are ephemeral and self-clean within
// 30 s. Skipped unless RUN_E2E=1 because the test needs network +
// Firebase auth.

import { test } from "node:test";
import assert from "node:assert";
import http from "node:http";
import path from "node:path";
import fs from "node:fs";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = path.resolve(__dirname, "..", "..");

const SKIP = process.env.RUN_E2E !== "1";

// ── HTTP server ───────────────────────────────────────────────────────────

const MIME = {
  ".html": "text/html",
  ".js":   "application/javascript",
  ".mjs":  "application/javascript",
  ".css":  "text/css",
  ".lua":  "text/plain",
  ".png":  "image/png",
  ".svg":  "image/svg+xml",
  ".json": "application/json",
  ".ico":  "image/x-icon",
};

function startServer(port) {
  return new Promise((resolve) => {
    const srv = http.createServer((req, res) => {
      const url = req.url.split("?")[0];
      let fp = path.join(REPO_ROOT, url === "/" ? "/index.html" : url);
      if (!fp.startsWith(REPO_ROOT)) { res.statusCode = 403; res.end("nope"); return; }
      fs.stat(fp, (err, st) => {
        if (err) { res.statusCode = 404; res.end("not found: " + url); return; }
        if (st.isDirectory()) fp = path.join(fp, "index.html");
        const ext = path.extname(fp).toLowerCase();
        res.setHeader("Content-Type", MIME[ext] || "application/octet-stream");
        // Permissive CORS so the Firebase SDK + game assets load cleanly.
        res.setHeader("Access-Control-Allow-Origin", "*");
        fs.createReadStream(fp).pipe(res);
      });
    });
    srv.listen(port, "127.0.0.1", () => resolve(srv));
  });
}

// ── Test harness ──────────────────────────────────────────────────────────

async function runPairingScenario(peerCount, staggerMs, port, cartParam) {
  const puppeteer = (await import("puppeteer")).default;
  const browser = await puppeteer.launch({
    headless: true,
    args: [
      "--no-sandbox",
      "--disable-setuid-sandbox",
      // mDNS hostname obfuscation breaks WebRTC between two browser
      // contexts on the same host (each generates a unique .local name
      // the other can't resolve). Disable so peers see raw host IPs.
      "--disable-features=WebRtcHideLocalIpsWithMdns",
      "--autoplay-policy=no-user-gesture-required",
      "--mute-audio",
    ],
  });
  const peers = [];
  try {
    for (let i = 0; i < peerCount; i++) {
      const label = "P" + i;
      // Separate browser contexts: independent storage so each gets its
      // own anonymous Firebase auth user. (Same-context tabs share
      // IndexedDB, which makes them log in as the same uid — fine for
      // signaling but unrealistic.)
      const ctx = await browser.createBrowserContext();
      const page = await ctx.newPage();
      const outcome = { label, role: null, signalingDone: false, error: null, log: [] };
      page.on("console", (msg) => {
        const text = msg.text();
        outcome.log.push(text);
        const m = text.match(/\[netplay\]\s*(.+)/);
        if (!m) return;
        const status = m[1];
        // Role assignment fires once the matchmaker commits this peer
        // to host or joiner. The last role wins because the matchmaker
        // may defer (reserve-then-confirm) and retry — but in steady
        // state the final value is the role we actually played.
        if (/Generating offer/i.test(status))    outcome.role = "host";
        if (/Generating answer/i.test(status))   outcome.role = "joiner";
        // Signaling is done once the peer reaches "Opening data
        // channel…" — both SDP halves have been exchanged via
        // Firestore. The DataChannel may or may not open after, but
        // that's a WebRTC-environment concern, not a matchmaker one.
        if (/Opening data channel/i.test(status)) outcome.signalingDone = true;
        if (/Connected as host/i.test(status))    { outcome.role = "host"; outcome.dcOpen = true; }
        if (/Connected as joiner/i.test(status))  { outcome.role = "joiner"; outcome.dcOpen = true; }
      });
      page.on("pageerror", (e) => { outcome.error = "pageerror: " + e.message; });
      peers.push({ label, ctx, page, outcome });
    }

    // Launch with stagger.
    for (let i = 0; i < peerCount; i++) {
      const url = `http://127.0.0.1:${port}/play.html?game=${encodeURIComponent(cartParam)}`;
      peers[i].page.goto(url, { waitUntil: "load" }).catch((e) => {
        peers[i].outcome.error = "goto: " + e.message;
      });
      if (i < peerCount - 1) await new Promise((r) => setTimeout(r, staggerMs));
    }

    // Wait for everyone to either finish signaling or error out. We
    // don't wait the full 30 s DataChannel timeout because we're only
    // verifying matchmaking; ~12 s covers ICE + Firestore + retry.
    const DEADLINE = Date.now() + 12_000;
    while (Date.now() < DEADLINE) {
      const done = peers.filter((p) => p.outcome.signalingDone || p.outcome.error).length;
      if (done === peers.length) break;
      await new Promise((r) => setTimeout(r, 200));
    }
    return peers.map((p) => p.outcome);
  } finally {
    await browser.close().catch(() => {});
  }
}

// ── Tests ─────────────────────────────────────────────────────────────────

function summarize(results) {
  return results.map((r) => `${r.label}:role=${r.role || "?"},done=${r.signalingDone}`).join(" | ");
}
function logTail(r) { return (r.log || []).slice(-12).join("\n      "); }

test("E2E: 2 peers within ICE window — signaling completes for both as host+joiner", { skip: SKIP }, async () => {
  const srv = await startServer(0);
  const port = srv.address().port;
  try {
    const results = await runPairingScenario(2, 150, port, "pong-2p");
    for (const r of results) {
      assert.ok(r.signalingDone,
        `${r.label} never finished signaling. error=${r.error}\n  log tail:\n      ${logTail(r)}`);
    }
    const hosts   = results.filter((r) => r.role === "host").length;
    const joiners = results.filter((r) => r.role === "joiner").length;
    assert.equal(hosts,   1, "expected 1 host; got: "   + summarize(results));
    assert.equal(joiners, 1, "expected 1 joiner; got: " + summarize(results));
  } finally {
    srv.close();
  }
});

test("E2E: 4 peers within ICE window — signaling completes for all as 2 pairs", { skip: SKIP }, async () => {
  const srv = await startServer(0);
  const port = srv.address().port;
  try {
    const results = await runPairingScenario(4, 200, port, "pong-2p");
    for (const r of results) {
      assert.ok(r.signalingDone,
        `${r.label} never finished signaling. error=${r.error}\n  log tail:\n      ${logTail(r)}`);
    }
    const hosts   = results.filter((r) => r.role === "host").length;
    const joiners = results.filter((r) => r.role === "joiner").length;
    assert.equal(hosts,   2, "expected 2 hosts; got: "   + summarize(results));
    assert.equal(joiners, 2, "expected 2 joiners; got: " + summarize(results));
  } finally {
    srv.close();
  }
});
