import { handleAvatar } from "./handler.ts";
import {
  AvatarClient,
  AvatarOperation,
  deleteAvatarBeforeAccount,
  readAuthorizedAvatar,
} from "../_shared/avatar_service.ts";
import { readAvatarBody, validateAvatarPng } from "../_shared/avatar_png.ts";

function equal(actual: unknown, expected: unknown) {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(
      `Mismatch: ${JSON.stringify(actual)} != ${JSON.stringify(expected)}`,
    );
  }
}
async function rejects(action: () => Promise<unknown>) {
  let rejected = false;
  try {
    await action();
  } catch (_) {
    rejected = true;
  }
  equal(rejected, true);
}
const actor = "11111111-1111-4111-8111-111111111111";
const requestId = "22222222-2222-4222-8222-222222222222";
const endpoint = "http://localhost/functions/v1/profile-avatar";
function request(
  method: string,
  body?: Uint8Array,
  extra: Record<string, string> = {},
) {
  return new Request(endpoint, {
    method,
    body,
    headers: {
      "x-request-id": requestId,
      "if-match": "0",
      "content-type": "image/png",
      ...extra,
    },
  });
}
import { png } from "./avatar_fixture.ts";
class Fake implements AvatarClient {
  calls: string[] = [];
  args: Record<string, unknown>[] = [];
  current: string | null = null;
  files: string[] = [];
  completed = false;
  version = 0;
  failure: string | null = null;
  failureCode = "40001";
  failureMessage: string | undefined;
  deniedAfterDownload = false;
  resolves = 0;
  bytes = new Uint8Array(100);
  rpc(name: string, args: Record<string, unknown> = {}) {
    this.calls.push(name);
    this.args.push(args);
    if (this.failure === name) {
      return Promise.resolve({
        data: null,
        error: { code: this.failureCode, message: this.failureMessage },
      });
    }
    let data: unknown = null;
    if (name === "begin_profile_avatar_operation") {
      data = {
        lease: "lease",
        version: this.version,
        current_file: this.current,
        files: [...this.files],
        completed: this.completed,
      };
    }
    if (name === "get_own_profile_avatar") {
      data = { version: this.version, has_image: this.current != null };
    }
    if (name === "stage_profile_avatar_file") {
      data = "new";
      this.files.push("new");
    }
    if (name === "forget_profile_avatar_file") {
      this.files = this.files.filter((x) => x !== args.file_id);
    }
    if (name === "commit_profile_avatar") {
      this.current = args.file_id as string | null;
      this.version++;
      data = { version: this.version, has_image: this.current != null };
    }
    if (name === "resolve_profile_avatar") {
      data = this.deniedAfterDownload && this.resolves++ > 0
        ? null
        : this.current;
    }
    if (name === "export_own_account_data_v12") {
      data = {
        schema_version: 12,
        auth_identity: { id: actor },
        authored_chat_messages: [],
      };
    }
    return Promise.resolve({ data, error: null });
  }
  storage = {
    from: (bucket: string) => {
      equal(bucket, "profile-avatars");
      return {
        upload: (
          path: string,
          _bytes: Uint8Array,
          options: { contentType: string; upsert: boolean },
        ) => {
          this.calls.push("upload:" + path);
          equal(options, { contentType: "image/png", upsert: false });
          return Promise.resolve({
            error: this.failure === "upload" ? {} : null,
          });
        },
        remove: (paths: string[]) => {
          this.calls.push("remove:" + paths.join(","));
          return Promise.resolve({
            error: this.failure === "remove" ? {} : null,
          });
        },
        download: (path: string) => {
          this.calls.push("download:" + path);
          return Promise.resolve({
            data: new Blob([this.bytes]),
            error: this.failure === "download" ? {} : null,
          });
        },
      };
    },
  };
}
Deno.test("private gateway configuration and verified caller boundary are mandatory", async () => {
  const config = await Deno.readTextFile(
    new URL("../../config.toml", import.meta.url),
  );
  const index = await Deno.readTextFile(new URL("./index.ts", import.meta.url));
  equal(
    config.match(/\[functions\.profile-avatar\]([\s\S]*?)(?=\n\[|$)/)?.[1]
      .includes("verify_jwt = false"),
    true,
  );
  for (
    const text of [
      '{ auth: "user" }',
      "context.userClaims?.id",
      "context.supabase as unknown",
      "context.supabaseAdmin as unknown",
    ]
  ) equal(index.includes(text), true);
  const deletion = await Deno.readTextFile(
    new URL("../delete-account/index.ts", import.meta.url),
  );
  equal(deletion.includes("deleteAvatarBeforeAccount"), true);
  equal(deletion.includes("hardDeleteAuthenticatedUser"), true);
});
Deno.test("canonical thumbnail passes full structural and pixel validation", async () => {
  await validateAvatarPng(await png());
});
for (
  const [name, options] of Object.entries({
    dimensions: { width: 255 },
    truncatedPixels: { rows: 255 },
    decompressionBomb: { rows: 3000 },
    filter: { filter: 5 },
    metadata: { metadata: true },
    deflate: { badDeflate: true },
  })
) {
  Deno.test(`reject ${name} before any Storage write`, async () => {
    const fake = new Fake();
    const response = await handleAvatar(
      request("PUT", await png(options)),
      actor,
      fake,
      fake,
    );
    equal(response.status, 422);
    equal(fake.calls.includes("begin_profile_avatar_operation"), false);
  });
}
Deno.test("CRC corruption and trailing content are rejected", async () => {
  const bytes = await png();
  bytes[29] ^= 1;
  await rejects(() => validateAvatarPng(bytes));
  await rejects(async () =>
    validateAvatarPng(new Uint8Array([...await png(), 0]))
  );
});
Deno.test("streaming body is bounded without trusting Content-Length", async () => {
  await rejects(() => readAvatarBody(request("PUT", new Uint8Array(327681))));
});
Deno.test("missing verified caller never reaches repositories", async () => {
  const fake = new Fake();
  equal((await handleAvatar(request("DELETE"), "", fake, fake)).status, 401);
  equal(fake.calls, []);
});
for (
  const [header, value] of [["x-request-id", "invalid"], ["if-match", "-1"], [
    "content-type",
    "image/svg+xml",
  ]]
) {
  Deno.test(`invalid ${header} cannot begin mutation`, async () => {
    const fake = new Fake();
    equal(
      (await handleAvatar(
        request("PUT", await png(), { [header]: value }),
        actor,
        fake,
        fake,
      )).status,
      422,
    );
    equal(fake.calls.includes("begin_profile_avatar_operation"), false);
  });
}
Deno.test("replace stages before upload, commits before deleting old and clears lease last", async () => {
  const fake = new Fake();
  fake.current = "old";
  fake.files = ["old", "retired"];
  const response = await handleAvatar(
    request("PUT", await png()),
    actor,
    fake,
    fake,
  );
  equal(response.status, 200);
  equal(fake.calls, [
    "get_own_profile_avatar",
    "begin_profile_avatar_operation",
    "remove:retired.png",
    "forget_profile_avatar_file",
    "stage_profile_avatar_file",
    "upload:new.png",
    "commit_profile_avatar",
    "remove:old.png",
    "forget_profile_avatar_file",
    "finish_profile_avatar_operation",
  ]);
  equal(fake.args.find((x) => x.target_profile)?.target_profile, actor);
  equal(fake.files, ["new"]);
  equal(response.headers.get("cache-control"), "no-store");
});
Deno.test("completed upload retry neither uploads nor increments version", async () => {
  const fake = new Fake();
  fake.completed = true;
  fake.version = 3;
  fake.current = "current";
  fake.files = ["current"];
  const operation = await AvatarOperation.start(
    fake,
    actor,
    requestId,
    "same",
    0,
  );
  equal(await operation.replace(await png()), { version: 3, has_image: true });
  equal(fake.calls, ["begin_profile_avatar_operation"]);
});
for (
  const [code, message, expectedStatus, expectedError] of [
    ["PT409", "avatar changed", 409, "stale"],
    ["40001", "avatar changed", 409, "stale"],
    [
      "40001",
      "could not serialize access due to concurrent update",
      503,
      "retryable",
    ],
  ] as const
) {
  Deno.test(`avatar conflict mapping ${code}/${message} makes one attempt`, async () => {
    const fake = new Fake();
    fake.current = "old";
    fake.files = ["old"];
    fake.version = 7;
    fake.failure = "begin_profile_avatar_operation";
    fake.failureCode = code;
    fake.failureMessage = message;
    const response = await handleAvatar(request("DELETE"), actor, fake, fake);
    equal(response.status, expectedStatus);
    equal(await response.json(), { error: expectedError });
    equal(fake.calls, [
      "get_own_profile_avatar",
      "begin_profile_avatar_operation",
    ]);
    equal(fake.version, 7);
    equal(fake.files, ["old"]);
    fake.failure = null;
    equal(
      (await handleAvatar(request("DELETE"), actor, fake, fake)).status,
      200,
    );
  });
}
Deno.test("legacy compatibility does not relabel serialization errors from other RPCs", async () => {
  const fake = new Fake();
  fake.failure = "get_own_profile_avatar";
  fake.failureMessage = "avatar changed";
  const response = await handleAvatar(request("DELETE"), actor, fake, fake);
  equal(response.status, 503);
  equal(await response.json(), { error: "retryable" });
  equal(fake.calls, ["get_own_profile_avatar"]);
});
for (const failure of ["upload", "remove", "commit_profile_avatar"]) {
  Deno.test(`${failure} failure retains recovery fence and never reports success`, async () => {
    const fake = new Fake();
    fake.failure = failure;
    fake.current = "old";
    fake.files = ["old"];
    const response = await handleAvatar(
      request("PUT", await png()),
      actor,
      fake,
      fake,
    );
    equal(response.status === 200, false);
    equal(fake.calls.includes("finish_profile_avatar_operation"), false);
  });
}
Deno.test("remove deletes bytes before clearing metadata and forgets once", async () => {
  const fake = new Fake();
  fake.current = "old";
  fake.files = ["old"];
  equal((await handleAvatar(request("DELETE"), actor, fake, fake)).status, 200);
  equal(fake.calls, [
    "get_own_profile_avatar",
    "begin_profile_avatar_operation",
    "remove:old.png",
    "commit_profile_avatar",
    "forget_profile_avatar_file",
    "finish_profile_avatar_operation",
  ]);
});
Deno.test("account deletion cleans all keys first and keeps fence until Auth cascade", async () => {
  const fake = new Fake();
  fake.current = "old";
  fake.files = ["old", "retired"];
  await deleteAvatarBeforeAccount(fake, actor, () => {
    fake.calls.push("auth-delete");
    equal(fake.files, []);
    return Promise.resolve();
  });
  equal(fake.calls.at(-1), "auth-delete");
  equal(fake.calls.includes("finish_profile_avatar_operation"), false);
});
Deno.test("failed binary cleanup forbids Auth deletion", async () => {
  const fake = new Fake();
  fake.current = "old";
  fake.files = ["old"];
  fake.failure = "remove";
  let deleted = false;
  await rejects(() =>
    deleteAvatarBeforeAccount(fake, actor, () => {
      deleted = true;
      return Promise.resolve();
    })
  );
  equal(deleted, false);
});
Deno.test("failed Auth deletion preserves account after photo has gone", async () => {
  const fake = new Fake();
  fake.current = "old";
  fake.files = ["old"];
  await rejects(() =>
    deleteAvatarBeforeAccount(
      fake,
      actor,
      () => Promise.reject(new Error("Auth unavailable")),
    )
  );
  equal(fake.current, null);
  equal(fake.files, []);
  equal(fake.calls.includes("finish_profile_avatar_operation"), false);
});
Deno.test("incomplete account without avatar can pass cleanup", async () => {
  const fake = new Fake();
  let deleted = false;
  await deleteAvatarBeforeAccount(fake, actor, () => {
    deleted = true;
    return Promise.resolve();
  });
  equal(deleted, true);
});
Deno.test("blocked or unavailable image returns no bytes or Storage lookup", async () => {
  const fake = new Fake();
  equal(await readAuthorizedAvatar(fake, fake, "profile", actor), null);
  equal(fake.calls, ["resolve_profile_avatar"]);
});
Deno.test("authorization is checked again after download", async () => {
  const fake = new Fake();
  fake.current = "old";
  fake.deniedAfterDownload = true;
  equal(await readAuthorizedAvatar(fake, fake, "chat", requestId), null);
  equal(fake.calls, [
    "resolve_profile_avatar",
    "download:old.png",
    "resolve_profile_avatar",
  ]);
});
Deno.test("binary response is compatible with the pinned Flutter functions client", async () => {
  const fake = new Fake();
  fake.current = "old";
  fake.bytes = await png();
  const response = await handleAvatar(request("GET"), actor, fake, fake);
  equal(response.status, 200);
  equal(response.headers.get("content-type"), "application/octet-stream");
  equal(new Uint8Array(await response.arrayBuffer()), fake.bytes);
});
Deno.test("export v13 includes only own current thumbnail without URLs", async () => {
  const fake = new Fake();
  fake.current = "old";
  fake.bytes = await png();
  const response = await handleAvatar(request("POST"), actor, fake, fake);
  const doc = await response.json();
  equal(response.status, 200);
  equal(doc.schema_version, 13);
  equal(doc.avatar.width, 256);
  equal(Object.keys(doc.avatar).sort(), [
    "data_base64",
    "height",
    "mime_type",
    "width",
  ]);
  equal(fake.args.find((x) => x.target_id)?.target_id, actor);
  equal(fake.calls.at(-1), "finish_profile_avatar_operation");
});
Deno.test("export v13 preserves an incomplete no-image account", async () => {
  const fake = new Fake();
  const response = await handleAvatar(request("POST"), actor, fake, fake);
  equal((await response.json()).avatar, null);
  equal(fake.calls.includes("resolve_profile_avatar"), false);
});
Deno.test("unexpected exceptions are private and never successful", async () => {
  const fake = new Fake();
  fake.rpc = () => {
    throw new Error("sensitive transport detail");
  };
  const response = await handleAvatar(request("DELETE"), actor, fake, fake);
  equal(response.status, 503);
  equal(await response.json(), { error: "retryable" });
});
