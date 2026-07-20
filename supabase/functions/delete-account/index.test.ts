import { withSupabase } from "@supabase/server";
import {
  AccountDeletionBoundaryError,
  type AccountDeletionRequestContext,
  handleDeleteAccount,
} from "./handler.ts";
import {
  hardDeleteAuthenticatedUser,
  validateDeletion,
} from "./supabase_adapters.ts";

const endpoint = "http://localhost/functions/v1/delete-account";
const authenticatedUserId = "11111111-1111-4111-8111-111111111111";
const publishableKey = "sb_publishable_delete_account_test";
const secretKey = "sb_secret_delete_account_test";
const jwtKeyId = "delete-account-test-key";
const jwtSecret = new TextEncoder().encode(
  "delete-account-wrapper-test-secret-with-at-least-32-bytes",
);

const wrapperEnvironment = {
  url: "http://127.0.0.1:54321",
  publishableKeys: { default: publishableKey },
  secretKeys: { default: secretKey },
  jwks: {
    keys: [
      {
        kty: "oct",
        alg: "HS256",
        kid: jwtKeyId,
        k: base64Url(jwtSecret),
      },
    ],
  },
};

function assert(
  condition: unknown,
  message = "assertion failed",
): asserts condition {
  if (!condition) throw new Error(message);
}

function assertEquals(actual: unknown, expected: unknown): void {
  const actualJson = JSON.stringify(actual);
  const expectedJson = JSON.stringify(expected);
  if (actualJson !== expectedJson) {
    throw new Error(`expected ${expectedJson}, received ${actualJson}`);
  }
}

function assertIncludes(actual: string, expected: string): void {
  assert(
    actual.includes(expected),
    `expected ${JSON.stringify(actual)} to include ${JSON.stringify(expected)}`,
  );
}

function base64Url(value: Uint8Array | string): string {
  const bytes = typeof value === "string"
    ? new TextEncoder().encode(value)
    : value;
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary)
    .replaceAll("+", "-")
    .replaceAll("/", "_")
    .replace(/=+$/, "");
}

async function userJwt(
  secret = jwtSecret,
  subject = authenticatedUserId,
): Promise<string> {
  const header = base64Url(JSON.stringify({
    alg: "HS256",
    kid: jwtKeyId,
    typ: "JWT",
  }));
  const payload = base64Url(JSON.stringify({
    aud: "authenticated",
    exp: Math.floor(Date.now() / 1000) + 300,
    iat: Math.floor(Date.now() / 1000),
    role: "authenticated",
    sub: subject,
  }));
  const signingInput = `${header}.${payload}`;
  const key = await crypto.subtle.importKey(
    "raw",
    secret,
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = new Uint8Array(
    await crypto.subtle.sign(
      "HMAC",
      key,
      new TextEncoder().encode(signingInput),
    ),
  );
  return `${signingInput}.${base64Url(signature)}`;
}

function wrapperRequest(headers: HeadersInit = {}): Request {
  return new Request(endpoint, {
    method: "POST",
    headers,
  });
}

function post(body: string, headers: HeadersInit = {}): Request {
  return new Request(endpoint, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      ...headers,
    },
    body,
  });
}

function context(
  overrides: Partial<AccountDeletionRequestContext> = {},
): AccountDeletionRequestContext {
  return {
    userId: authenticatedUserId,
    validate: () => Promise.resolve(),
    hardDelete: () => Promise.resolve(),
    ...overrides,
  };
}

async function responseJson(response: Response): Promise<unknown> {
  return JSON.parse(await response.text());
}

Deno.test("configuration delegates delete-account authentication to the SDK wrapper", async () => {
  const config = await Deno.readTextFile(
    new URL("../../config.toml", import.meta.url),
  );
  const entrypoint = await Deno.readTextFile(
    new URL("./index.ts", import.meta.url),
  );
  const functionSection = config.match(
    /\[functions\.delete-account\]([\s\S]*?)(?=\n\[|$)/,
  )?.[1] ?? "";

  assertIncludes(functionSection, "enabled = true");
  assertIncludes(functionSection, "verify_jwt = false");
  assert(!functionSection.includes("verify_jwt = true"));
  assertIncludes(entrypoint, 'withSupabase({ auth: "user" }');
  assertIncludes(entrypoint, "context.userClaims?.id");
  assertIncludes(entrypoint, "context.supabase as unknown");
  assertIncludes(entrypoint, "context.supabaseAdmin");
});

for (
  const [name, headers] of [
    ["missing authentication", {}],
    ["a malformed user JWT", { authorization: "Bearer not-a-jwt" }],
    [
      "a publishable key without a user session",
      {
        apikey: publishableKey,
        authorization: `Bearer ${publishableKey}`,
      },
    ],
    [
      "a secret key presented as a user request",
      { apikey: secretKey, authorization: `Bearer ${secretKey}` },
    ],
  ] as const
) {
  Deno.test(`the SDK user wrapper rejects ${name}`, async () => {
    let handlerCalled = false;
    const wrapped = withSupabase(
      { auth: "user", env: wrapperEnvironment },
      () => {
        handlerCalled = true;
        return Promise.resolve(Response.json({ accepted: true }));
      },
    );

    const response = await wrapped(wrapperRequest(headers));

    assertEquals(response.status, 401);
    assertEquals(handlerCalled, false);
  });
}

Deno.test("the SDK user wrapper rejects an invalidly signed user JWT", async () => {
  let handlerCalled = false;
  const wrapped = withSupabase(
    { auth: "user", env: wrapperEnvironment },
    () => {
      handlerCalled = true;
      return Promise.resolve(Response.json({ accepted: true }));
    },
  );
  const invalidJwt = await userJwt(
    new TextEncoder().encode(
      "different-wrapper-test-secret-with-at-least-32-bytes",
    ),
  );

  const response = await wrapped(
    wrapperRequest({ authorization: `Bearer ${invalidJwt}` }),
  );

  assertEquals(response.status, 401);
  assertEquals(handlerCalled, false);
});

Deno.test("a valid user receives verified identity and both scoped clients", async () => {
  let observed: unknown;
  const requests: Request[] = [];
  const token = await userJwt();
  const wrapped = withSupabase(
    {
      auth: "user",
      env: wrapperEnvironment,
      supabaseOptions: {
        global: {
          fetch: (input, init) => {
            requests.push(new Request(input, init));
            return Promise.resolve(
              new Response("null", {
                status: 200,
                headers: { "content-type": "application/json" },
              }),
            );
          },
        },
      },
    },
    async (_request, wrapperContext) => {
      await wrapperContext.supabase.rpc("user_scope_probe");
      await wrapperContext.supabaseAdmin.rpc("admin_scope_probe");
      observed = {
        authMode: wrapperContext.authMode,
        userId: wrapperContext.userClaims?.id,
        hasUserClient: wrapperContext.supabase != null,
        hasAdminClient: wrapperContext.supabaseAdmin != null,
        clientsAreDistinct:
          wrapperContext.supabase !== wrapperContext.supabaseAdmin,
      };
      return Response.json({ accepted: true });
    },
  );

  const response = await wrapped(
    wrapperRequest({
      apikey: publishableKey,
      authorization: `Bearer ${token}`,
    }),
  );

  assertEquals(response.status, 200);
  assertEquals(observed, {
    authMode: "user",
    userId: authenticatedUserId,
    hasUserClient: true,
    hasAdminClient: true,
    clientsAreDistinct: true,
  });
  assertEquals(requests.length, 2);
  assertIncludes(requests[0].url, "/rest/v1/rpc/user_scope_probe");
  assertEquals(requests[0].headers.get("apikey"), publishableKey);
  assertEquals(requests[0].headers.get("authorization"), `Bearer ${token}`);
  assertIncludes(requests[1].url, "/rest/v1/rpc/admin_scope_probe");
  assertEquals(requests[1].headers.get("apikey"), secretKey);
});

Deno.test("OPTIONS returns an empty preflight response without deletion", async () => {
  let called = false;
  const response = await handleDeleteAccount(
    new Request(endpoint, { method: "OPTIONS" }),
    context({
      validate: () => {
        called = true;
        return Promise.resolve();
      },
    }),
  );

  assertEquals(response.status, 204);
  assertEquals(response.headers.get("allow"), "POST, OPTIONS");
  assertEquals(called, false);
});

Deno.test("unsupported methods are rejected before validation", async () => {
  let called = false;
  const response = await handleDeleteAccount(
    new Request(endpoint, { method: "DELETE" }),
    context({
      validate: () => {
        called = true;
        return Promise.resolve();
      },
    }),
  );

  assertEquals(response.status, 405);
  assertEquals(await responseJson(response), { error: "method_not_allowed" });
  assertEquals(called, false);
});

Deno.test("a missing authenticated caller is rejected", async () => {
  const response = await handleDeleteAccount(
    post('{"confirmation":"delete_me"}'),
    context({ userId: "" }),
  );

  assertEquals(response.status, 401);
  assertEquals(await responseJson(response), {
    error: "authentication_required",
  });
});

for (
  const [name, request] of [
    [
      "missing JSON content type",
      new Request(endpoint, { method: "POST", body: "{}" }),
    ],
    ["malformed JSON", post("{")],
    ["missing confirmation", post("{}")],
    ["extra body field", post('{"confirmation":"delete_me","id":"other"}')],
    ["non-string confirmation", post('{"confirmation":12}')],
    ["empty confirmation", post('{"confirmation":""}')],
  ] as const
) {
  Deno.test(`${name} is rejected before validation`, async () => {
    let called = false;
    const response = await handleDeleteAccount(
      request,
      context({
        validate: () => {
          called = true;
          return Promise.resolve();
        },
      }),
    );

    assertEquals(response.status, 400);
    assertEquals(await responseJson(response), { error: "invalid_request" });
    assertEquals(called, false);
  });
}

Deno.test("a declared oversized body is rejected", async () => {
  const response = await handleDeleteAccount(
    post('{"confirmation":"delete_me"}', { "content-length": "1025" }),
    context(),
  );
  assertEquals(response.status, 400);
});

Deno.test("an undeclared oversized body is bounded while streaming", async () => {
  const response = await handleDeleteAccount(
    post(JSON.stringify({ confirmation: "x".repeat(1100) })),
    context(),
  );
  assertEquals(response.status, 400);
});

Deno.test("confirmation is forwarded exactly and validation precedes deletion", async () => {
  const exactConfirmation = " Delete_Me\t";
  const events: string[] = [];
  let validatedConfirmation: string | null = null;
  let deletedUserId: string | null = null;
  const response = await handleDeleteAccount(
    post(JSON.stringify({ confirmation: exactConfirmation })),
    context({
      validate: (confirmation) => {
        events.push("validate");
        validatedConfirmation = confirmation;
        return Promise.resolve();
      },
      hardDelete: (userId) => {
        events.push("delete");
        deletedUserId = userId;
        return Promise.resolve();
      },
    }),
  );

  assertEquals(response.status, 200);
  assertEquals(await responseJson(response), { deleted: true });
  assertEquals(validatedConfirmation, exactConfirmation);
  assertEquals(deletedUserId, "11111111-1111-4111-8111-111111111111");
  assertEquals(events, ["validate", "delete"]);
});

for (
  const [kind, status, responseCode] of [
    ["authentication_required", 401, "authentication_required"],
    ["reauthentication_required", 409, "reauthentication_required"],
    ["confirmation_mismatch", 422, "confirmation_mismatch"],
    ["retryable", 503, "retryable_failure"],
  ] as const
) {
  Deno.test(`${kind} validation failure is privacy-safe`, async () => {
    let deleted = false;
    const response = await handleDeleteAccount(
      post('{"confirmation":"private-value"}'),
      context({
        validate: () => Promise.reject(new AccountDeletionBoundaryError(kind)),
        hardDelete: () => {
          deleted = true;
          return Promise.resolve();
        },
      }),
    );

    const body = await response.text();
    assertEquals(response.status, status);
    assertEquals(JSON.parse(body), { error: responseCode });
    assert(!body.includes("private-value"));
    assertEquals(deleted, false);
  });
}

Deno.test("an admin deletion failure never reports success", async () => {
  const response = await handleDeleteAccount(
    post('{"confirmation":"delete_me"}'),
    context({
      hardDelete: () =>
        Promise.reject(new AccountDeletionBoundaryError("retryable")),
    }),
  );

  assertEquals(response.status, 503);
  assertEquals(await responseJson(response), { error: "retryable_failure" });
});

Deno.test("unexpected infrastructure failures remain retryable and redacted", async () => {
  const response = await handleDeleteAccount(
    post('{"confirmation":"private-confirmation"}'),
    context({
      validate: () => Promise.reject(new Error("database identity details")),
    }),
  );
  const body = await response.text();

  assertEquals(response.status, 503);
  assertEquals(JSON.parse(body), { error: "retryable_failure" });
  assert(!body.includes("private-confirmation"));
  assert(!body.includes("database identity details"));
});

Deno.test("the RPC adapter sends only the exact confirmation", async () => {
  let call: unknown;
  await validateDeletion(
    {
      rpc: (functionName, parameters) => {
        call = { functionName, parameters };
        return Promise.resolve({ data: true, error: null });
      },
    },
    " Exact@Example.test ",
  );

  assertEquals(call, {
    functionName: "validate_account_deletion",
    parameters: { deletion_confirmation: " Exact@Example.test " },
  });
});

for (
  const [sqlState, kind] of [
    ["42501", "authentication_required"],
    ["55000", "reauthentication_required"],
    ["22023", "confirmation_mismatch"],
    ["XX000", "retryable"],
  ] as const
) {
  Deno.test(`the RPC adapter maps ${sqlState} safely`, async () => {
    let caught: unknown;
    try {
      await validateDeletion(
        {
          rpc: () => Promise.resolve({ data: null, error: { code: sqlState } }),
        },
        "confirmation",
      );
    } catch (error) {
      caught = error;
    }

    assert(caught instanceof AccountDeletionBoundaryError);
    assertEquals(caught.kind, kind);
  });
}

Deno.test("a non-true validation result is rejected", async () => {
  let caught: unknown;
  try {
    await validateDeletion(
      {
        rpc: () => Promise.resolve({ data: false, error: null }),
      },
      "confirmation",
    );
  } catch (error) {
    caught = error;
  }
  assert(caught instanceof AccountDeletionBoundaryError);
  assertEquals(caught.kind, "retryable");
});

Deno.test("the admin adapter hard-deletes only the authenticated caller", async () => {
  let argumentsReceived: unknown;
  await hardDeleteAuthenticatedUser(
    {
      auth: {
        admin: {
          deleteUser: (userId, shouldSoftDelete) => {
            argumentsReceived = [userId, shouldSoftDelete];
            return Promise.resolve({ error: null });
          },
        },
      },
    },
    "11111111-1111-4111-8111-111111111111",
  );

  assertEquals(argumentsReceived, [
    "11111111-1111-4111-8111-111111111111",
    false,
  ]);
});

Deno.test("the admin adapter surfaces deletion failure as retryable", async () => {
  let caught: unknown;
  try {
    await hardDeleteAuthenticatedUser(
      {
        auth: {
          admin: {
            deleteUser: () => Promise.resolve({ error: new Error("failed") }),
          },
        },
      },
      "11111111-1111-4111-8111-111111111111",
    );
  } catch (error) {
    caught = error;
  }

  assert(caught instanceof AccountDeletionBoundaryError);
  assertEquals(caught.kind, "retryable");
});

Deno.test("successful and failed handlers write no sensitive logs", async () => {
  const captured: unknown[] = [];
  const original = {
    log: console.log,
    error: console.error,
    warn: console.warn,
    info: console.info,
  };
  const capture = (...values: unknown[]) => captured.push(...values);
  console.log = capture;
  console.error = capture;
  console.warn = capture;
  console.info = capture;

  try {
    await handleDeleteAccount(
      post('{"confirmation":"private-confirmation"}'),
      context(),
    );
    await handleDeleteAccount(
      post('{"confirmation":"private-confirmation"}'),
      context({
        validate: () =>
          Promise.reject(
            new AccountDeletionBoundaryError("confirmation_mismatch"),
          ),
      }),
    );
  } finally {
    console.log = original.log;
    console.error = original.error;
    console.warn = original.warn;
    console.info = original.info;
  }

  assertEquals(captured, []);
});
