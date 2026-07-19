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
    userId: "11111111-1111-4111-8111-111111111111",
    validate: () => Promise.resolve(),
    hardDelete: () => Promise.resolve(),
    ...overrides,
  };
}

async function responseJson(response: Response): Promise<unknown> {
  return JSON.parse(await response.text());
}

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
