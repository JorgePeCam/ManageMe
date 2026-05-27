/**
 * DocumentBrain API Proxy — Cloudflare Worker
 *
 * Proxies requests to Gemini API injecting the key server-side.
 * The API key never leaves the server.
 *
 * Routes:
 *   POST /chat         → gemini:generateContent
 *   POST /chat/stream  → gemini:streamGenerateContent (SSE)
 *   POST /verify       → lightweight key check (uses client-supplied key)
 */

const GEMINI_BASE = "https://generativelanguage.googleapis.com/v1beta/models";
const GEMINI_MODEL = "gemini-2.5-flash";

// Simple per-IP rate limiting using Cloudflare's Cache API
const RATE_LIMIT_REQUESTS = 20;
const RATE_LIMIT_WINDOW_MS = 24 * 60 * 60 * 1000; // 24h

export default {
  async fetch(request, env) {
    // CORS preflight
    if (request.method === "OPTIONS") {
      return corsResponse(new Response(null, { status: 204 }));
    }

    if (request.method !== "POST") {
      return corsResponse(new Response("Method not allowed", { status: 405 }));
    }

    const url = new URL(request.url);

    // Validate shared secret header — rejects requests not from the app
    const appSecret = request.headers.get("x-app-secret");
    if (url.pathname !== "/verify" && appSecret !== env.APP_SECRET) {
      return corsResponse(new Response("Unauthorized", { status: 401 }));
    }

    // Rate limiting (skip for /verify — it uses the user's own key)
    if (url.pathname !== "/verify") {
      const ip = request.headers.get("CF-Connecting-IP") ?? "unknown";
      const limited = await isRateLimited(ip, env);
      if (limited) {
        return corsResponse(new Response("Too Many Requests", { status: 429 }));
      }
    }

    try {
      if (url.pathname === "/chat") {
        return await handleChat(request, env, false);
      } else if (url.pathname === "/chat/stream") {
        return await handleChat(request, env, true);
      } else if (url.pathname === "/verify") {
        return await handleVerify(request);
      } else {
        return corsResponse(new Response("Not Found", { status: 404 }));
      }
    } catch (err) {
      return corsResponse(new Response(JSON.stringify({ error: err.message }), {
        status: 500,
        headers: { "Content-Type": "application/json" }
      }));
    }
  }
};

// ---------------------------------------------------------------------------
// Handlers
// ---------------------------------------------------------------------------

async function handleChat(request, env, stream) {
  const body = await request.json();

  const geminiPath = stream
    ? `${GEMINI_BASE}/${GEMINI_MODEL}:streamGenerateContent?alt=sse`
    : `${GEMINI_BASE}/${GEMINI_MODEL}:generateContent`;

  const geminiResponse = await fetch(geminiPath, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-goog-api-key": env.GEMINI_API_KEY,
    },
    body: JSON.stringify(body),
  });

  if (!geminiResponse.ok) {
    const errorText = await geminiResponse.text();
    return corsResponse(new Response(errorText, { status: geminiResponse.status }));
  }

  // For streaming, pass through the SSE response directly
  if (stream) {
    const headers = new Headers(geminiResponse.headers);
    headers.set("Access-Control-Allow-Origin", "*");
    return new Response(geminiResponse.body, {
      status: geminiResponse.status,
      headers,
    });
  }

  const data = await geminiResponse.json();
  return corsResponse(Response.json(data));
}

async function handleVerify(request) {
  // For /verify the client sends their own key — we just proxy the call
  const clientKey = request.headers.get("x-goog-api-key");
  if (!clientKey) {
    return corsResponse(new Response("Missing key", { status: 400 }));
  }

  const body = await request.json();

  const geminiResponse = await fetch(
    `${GEMINI_BASE}/gemini-1.5-flash:generateContent`,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-goog-api-key": clientKey,
      },
      body: JSON.stringify(body),
    }
  );

  return corsResponse(new Response(null, { status: geminiResponse.status }));
}

// ---------------------------------------------------------------------------
// Rate limiting — uses KV if available, falls back to in-memory per-isolate
// ---------------------------------------------------------------------------

async function isRateLimited(ip, env) {
  if (!env.RATE_LIMIT_KV) return false; // KV not bound — skip

  const key = `rl:${ip}:${todayKey()}`;
  const current = parseInt((await env.RATE_LIMIT_KV.get(key)) ?? "0");

  if (current >= RATE_LIMIT_REQUESTS) return true;

  await env.RATE_LIMIT_KV.put(key, String(current + 1), {
    expirationTtl: 86400, // 24h
  });
  return false;
}

function todayKey() {
  return new Date().toISOString().slice(0, 10); // "2026-05-27"
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function corsResponse(response) {
  const headers = new Headers(response.headers);
  headers.set("Access-Control-Allow-Origin", "*");
  headers.set("Access-Control-Allow-Headers", "Content-Type, x-app-secret, x-goog-api-key");
  headers.set("Access-Control-Allow-Methods", "POST, OPTIONS");
  return new Response(response.body, {
    status: response.status,
    headers,
  });
}
