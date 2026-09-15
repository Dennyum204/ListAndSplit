export type Claim = { delivery_id: string; delivery_lease: string };
export type Delivery = {
  delivery_id: string;
  binding_id: string;
  recipient_id: string;
  token: string;
  kind: "chat" | "notification";
  list_id: string | null;
  expires_at: string;
};
export type Outcome = {
  outcome: "sent" | "retry" | "invalid" | "discarded";
  retryAfter?: number;
};
export interface PushStore {
  claim(): Promise<Claim[]>;
  prepare(claim: Claim): Promise<Delivery | null>;
  finish(
    claim: Claim,
    result: Outcome,
    tokenHash: string | null,
  ): Promise<void>;
}
export type Sender = (delivery: Delivery) => Promise<Outcome>;

export async function tokenHash(token: string): Promise<string> {
  const bytes = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(token),
  );
  return [...new Uint8Array(bytes)].map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}
export async function authorizedWorker(
  request: Request,
  expected: string,
): Promise<boolean> {
  const supplied = request.headers.get("x-push-worker-key") ?? "";
  if (expected.length < 32 || supplied.length > 512) return false;
  const a = await tokenHash(expected);
  const b = await tokenHash(supplied);
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

export async function dispatch(
  request: Request,
  key: string,
  store: PushStore,
  send: Sender,
): Promise<Response> {
  if (!await authorizedWorker(request, key)) {
    return new Response(null, { status: 401 });
  }
  if (request.method !== "POST") return new Response(null, { status: 405 });
  if (Number(request.headers.get("content-length") ?? "0") > 1024) {
    return new Response(null, { status: 413 });
  }
  let completed = 0;
  try {
    const claims = await store.claim();
    if (claims.length > 20) throw new Error("Invalid bounded batch");
    // Four concurrent sends, one HTTP attempt each. Database leases/backoff own
    // all retries, including a worker exit after an uncertain network result.
    for (let start = 0; start < claims.length; start += 4) {
      await Promise.all(
        claims.slice(start, start + 4).map(async (claim) => {
          const delivery = await store.prepare(claim); // Recheck immediately before HTTP.
          if (!delivery) return;
          let result: Outcome;
          try {
            result = await send(delivery);
          } catch {
            result = { outcome: "retry" };
          }
          await store.finish(claim, result, await tokenHash(delivery.token));
          completed++;
        }),
      );
    }
    return Response.json({ processed: completed });
  } catch {
    // No request body, token, account, FCM error payload or credentials in logs.
    return Response.json({ error: "push_dispatch_unavailable" }, {
      status: 503,
    });
  }
}
