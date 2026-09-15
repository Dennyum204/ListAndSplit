import {
  type Claim,
  type Delivery,
  dispatch,
  type PushStore,
} from "./handler.ts";
import { makeFcmSender } from "./fcm.ts";
function equal(actual: unknown, expected: unknown) {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(
      `Expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`,
    );
  }
}
const secret = "local-worker-test-key-not-a-hosted-credential";
const claim: Claim = { delivery_id: "delivery", delivery_lease: "lease" };
const delivery: Delivery = {
  delivery_id: "delivery",
  binding_id: "binding",
  recipient_id: "account",
  token: "local-token",
  kind: "chat",
  list_id: "list",
  expires_at: new Date(Date.now() + 600000).toISOString(),
};
function request(key = secret) {
  return new Request("http://localhost/push", {
    method: "POST",
    headers: { "x-push-worker-key": key },
  });
}
Deno.test("worker rejects user/anonymous/incorrect keys before touching storage", async () => {
  let calls = 0;
  const store: PushStore = {
    claim: async () => {
      calls++;
      return [];
    },
    prepare: async () => null,
    finish: async () => {},
  };
  for (const key of ["", "sb_publishable_fixture", "wrong"]) {
    equal(
      (await dispatch(
        request(key),
        secret,
        store,
        async () => ({ outcome: "sent" }),
      )).status,
      401,
    );
  }
  equal(calls, 0);
});
Deno.test("access revoked at prepare causes no external send", async () => {
  let sent = 0;
  const response = await dispatch(request(), secret, {
    claim: async () => [claim],
    prepare: async () => null,
    finish: async () => {
      throw new Error("not expected");
    },
  }, async () => {
    sent++;
    return { outcome: "sent" };
  });
  equal(response.status, 200);
  equal(sent, 0);
});
Deno.test("uncertain HTTP is one attempt and handed to durable bounded retry", async () => {
  let sent = 0;
  const outcomes: string[] = [];
  const response = await dispatch(request(), secret, {
    claim: async () => [claim],
    prepare: async () => delivery,
    finish: async (_c, o) => {
      outcomes.push(o.outcome);
    },
  }, async () => {
    sent++;
    throw new Error("network");
  });
  equal(response.status, 200);
  equal(sent, 1);
  equal(outcomes, ["retry"]);
});
Deno.test("completion failure leaves lease authoritative without another send", async () => {
  let sent = 0;
  const response = await dispatch(request(), secret, {
    claim: async () => [claim],
    prepare: async () => delivery,
    finish: async () => {
      throw new Error("database");
    },
  }, async () => {
    sent++;
    return { outcome: "sent" };
  });
  equal(response.status, 503);
  equal(sent, 1);
});
Deno.test("FCM project mismatch fails closed", () => {
  let rejected = false;
  try {
    makeFcmSender('{"project_id":"unrelated"}', "list-and-split-test");
  } catch {
    rejected = true;
  }
  equal(rejected, true);
});
Deno.test("actual FCM HTTP adapter uses signed OAuth, private data, bounded response mapping", async () => {
  const pair = await crypto.subtle.generateKey(
    {
      name: "RSASSA-PKCS1-v1_5",
      modulusLength: 2048,
      publicExponent: new Uint8Array([1, 0, 1]),
      hash: "SHA-256",
    },
    true,
    ["sign", "verify"],
  );
  const der = new Uint8Array(
    await crypto.subtle.exportKey("pkcs8", pair.privateKey),
  );
  const account = {
    project_id: "list-and-split-test",
    client_email: "sender@list-and-split-test.iam.gserviceaccount.com",
    private_key: `-----BEGIN PRIVATE KEY-----\n${
      btoa(String.fromCharCode(...der))
    }\n-----END PRIVATE KEY-----`,
  };
  let calls = 0;
  let status = 200;
  let code = "";
  let oauthCalls = 0;
  const mock: typeof fetch = async (input, init) => {
    calls++;
    if (String(input).includes("oauth2.googleapis.com")) {
      oauthCalls++;
      const assertion = (init!.body as URLSearchParams).get("assertion")!;
      const parts = assertion.split(".");
      const decode = (s: string) =>
        Uint8Array.from(
          atob(s.replaceAll("-", "+").replaceAll("_", "/")),
          (c) => c.charCodeAt(0),
        );
      equal(
        await crypto.subtle.verify(
          "RSASSA-PKCS1-v1_5",
          pair.publicKey,
          decode(parts[2]),
          new TextEncoder().encode(parts.slice(0, 2).join(".")),
        ),
        true,
      );
      return Response.json({
        access_token: "ephemeral-test-token",
        expires_in: 3600,
      });
    }
    equal(
      String(input),
      "https://fcm.googleapis.com/v1/projects/list-and-split-test/messages:send",
    );
    const payload = JSON.parse(init!.body as string);
    equal(payload.message.notification, undefined);
    equal(Object.keys(payload.message.data).sort(), [
      "binding_id",
      "delivery_id",
      "kind",
      "list_id",
      "recipient_id",
      "v",
    ]);
    equal(payload.message.android, { priority: "HIGH", ttl: "300s" });
    return status === 200
      ? Response.json({ name: "accepted" })
      : Response.json({ error: { details: [{ errorCode: code }] } }, {
        status,
        headers: { "Retry-After": "120" },
      });
  };
  const send = makeFcmSender(
    JSON.stringify(account),
    "list-and-split-test",
    mock,
  );
  equal((await send(delivery)).outcome, "sent");
  status = 429;
  equal(await send(delivery), { outcome: "retry", retryAfter: 120 });
  status = 404;
  code = "UNREGISTERED";
  equal((await send(delivery)).outcome, "invalid");
  status = 400;
  code = "INVALID_ARGUMENT";
  equal((await send(delivery)).outcome, "discarded");
  equal(oauthCalls, 1);
  equal(calls, 5); // No immediate application retry.
});
