import type { Delivery, Outcome } from "./handler.ts";
type ServiceAccount = {
  project_id: string;
  client_email: string;
  private_key: string;
  token_uri?: string;
};
type Http = typeof fetch;
const oauth = "https://oauth2.googleapis.com/token";
const scope = "https://www.googleapis.com/auth/firebase.messaging";
const encoder = new TextEncoder();
function base64(bytes: Uint8Array): string {
  return btoa(String.fromCharCode(...bytes)).replaceAll("+", "-").replaceAll(
    "/",
    "_",
  ).replace(/=+$/, "");
}

export function makeFcmSender(
  raw: string,
  expectedProject: string,
  http: Http = fetch,
) {
  let config: ServiceAccount;
  try {
    config = JSON.parse(raw);
  } catch {
    throw new Error("FCM configuration unavailable");
  }
  if (
    !/^list-and-split-[a-z0-9-]+$/.test(expectedProject) ||
    config.project_id !== expectedProject ||
    !config.client_email.endsWith(
      `@${expectedProject}.iam.gserviceaccount.com`,
    ) ||
    (config.token_uri && config.token_uri !== oauth) ||
    !config.private_key.includes("BEGIN PRIVATE KEY")
  ) {
    throw new Error("FCM project/configuration mismatch");
  }
  let access: string | null = null;
  let expires = 0;
  let obtaining: Promise<string> | null = null;
  async function acquire(): Promise<string> {
    const iat = Math.floor(Date.now() / 1000);
    const parts = [
      base64(encoder.encode(JSON.stringify({ alg: "RS256", typ: "JWT" }))),
      base64(
        encoder.encode(
          JSON.stringify({
            iss: config.client_email,
            scope,
            aud: oauth,
            iat,
            exp: iat + 3600,
          }),
        ),
      ),
    ];
    const der = Uint8Array.from(
      atob(config.private_key.replace(/-----[^-]+-----|\s/g, "")),
      (c) => c.charCodeAt(0),
    );
    const key = await crypto.subtle.importKey(
      "pkcs8",
      der,
      { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
      false,
      ["sign"],
    );
    parts.push(
      base64(
        new Uint8Array(
          await crypto.subtle.sign(
            "RSASSA-PKCS1-v1_5",
            key,
            encoder.encode(parts.join(".")),
          ),
        ),
      ),
    );
    const response = await http(oauth, {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
        assertion: parts.join("."),
      }),
      signal: AbortSignal.timeout(8000),
    });
    if (!response.ok) throw new Error("FCM authorization unavailable");
    const result = await response.json();
    if (
      typeof result.access_token !== "string" ||
      !Number.isFinite(result.expires_in)
    ) throw new Error("FCM authorization invalid");
    access = result.access_token;
    expires = Date.now() + Math.min(result.expires_in, 3300) * 1000;
    return access!;
  }
  async function getAccess(): Promise<string> {
    if (access && expires > Date.now()) return access;
    obtaining ??= acquire().finally(() => {
      obtaining = null;
    });
    return obtaining;
  }
  return async (delivery: Delivery): Promise<Outcome> => {
    const remaining = Math.floor(
      (Date.parse(delivery.expires_at) - Date.now()) / 1000,
    );
    if (!(remaining > 0)) return { outcome: "discarded" };
    const data: Record<string, string> = {
      v: "1",
      delivery_id: delivery.delivery_id,
      binding_id: delivery.binding_id,
      recipient_id: delivery.recipient_id,
      kind: delivery.kind,
    };
    if (delivery.kind === "chat" && delivery.list_id) {
      data.list_id = delivery.list_id;
    }
    // Data-only: the native service checks the current account/binding before
    // rendering generic localized text. System auto-display would bypass it.
    const response = await http(
      `https://fcm.googleapis.com/v1/projects/${expectedProject}/messages:send`,
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${await getAccess()}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          message: {
            token: delivery.token,
            data,
            android: { priority: "HIGH", ttl: `${Math.min(300, remaining)}s` },
          },
        }),
        signal: AbortSignal.timeout(8000),
      },
    );
    if (response.ok) {
      await response.text();
      return { outcome: "sent" };
    }
    let body: { error?: { details?: { errorCode?: string }[] } } = {};
    try {
      body = await response.json();
    } catch { /* Opaque upstream failure. */ }
    if (body.error?.details?.some((d) => d.errorCode === "UNREGISTERED")) {
      return { outcome: "invalid" };
    }
    if (response.status === 401) {
      access = null;
      expires = 0;
    }
    if (
      response.status === 429 || response.status >= 500 ||
      response.status === 401 || response.status === 403
    ) {
      const retry = Number(response.headers.get("Retry-After"));
      return {
        outcome: "retry",
        retryAfter: Number.isFinite(retry)
          ? Math.max(60, Math.min(900, retry))
          : 60,
      };
    }
    return { outcome: "discarded" };
  };
}
