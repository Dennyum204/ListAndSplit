// Explicit opt-in local-only integration. Never accepts a hosted endpoint.
import { createClient } from "@supabase/supabase-js";
import { handleAvatar } from "./handler.ts";
import {
  AvatarClient,
  deleteAvatarBeforeAccount,
} from "../_shared/avatar_service.ts";
import { png } from "./avatar_fixture.ts";

Deno.test("local Storage/RPC upload, authorized read, export, removal and Auth-root deletion", async () => {
  const url = Deno.env.get("AVATAR_LOCAL_URL");
  if (url !== "http://127.0.0.1:54321" && url !== "http://localhost:54321") {
    throw new Error("Explicit local endpoint required");
  }
  const anon = Deno.env.get("AVATAR_LOCAL_ANON") ?? "";
  const service = Deno.env.get("AVATAR_LOCAL_SERVICE") ?? "";
  const admin = createClient(url, service, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const user = createClient(url, anon, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const email = `avatar-${crypto.randomUUID()}@example.test`,
    password = crypto.randomUUID() + "aB7!";
  const created = await admin.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
  });
  if (created.error || !created.data.user) {
    throw new Error("Local fixture creation failed");
  }
  const id = created.data.user.id;
  let deleted = false;
  const server = admin as unknown as AvatarClient,
    caller = user as unknown as AvatarClient;
  function requireSuccess(value: { error: unknown }) {
    if (value.error) throw new Error("Local operation failed");
  }
  async function invoke(method: string, version = 0, body?: Uint8Array) {
    return handleAvatar(
      new Request("http://localhost/avatar", {
        method,
        body,
        headers: {
          "content-type": "image/png",
          "if-match": String(version),
          "x-request-id": crypto.randomUUID(),
        },
      }),
      id,
      caller,
      server,
    );
  }
  try {
    requireSuccess(await user.auth.signInWithPassword({ email, password }));
    requireSuccess(
      await user.from("profiles").update({
        username: "avatar" + id.replaceAll("-", "").slice(0, 12),
        display_name: "Local avatar fixture",
      }).eq("id", id),
    );
    const bytes = await png();
    if ((await invoke("PUT", 0, bytes)).status !== 200) {
      throw new Error("Local upload failed");
    }
    // Exercise the deployed local Edge wrapper and real PostgREST HTTP path.
    // Direct pgTAP/handler calls miss PostgREST 14's 40001 retry behaviour.
    const session = (await user.auth.getSession()).data.session;
    if (!session) throw new Error("Local fixture session missing");
    const staleRequest = crypto.randomUUID();
    const started = performance.now();
    const stale = await fetch(`${url}/functions/v1/profile-avatar`, {
      method: "PUT",
      headers: {
        apikey: anon,
        Authorization: `Bearer ${session.access_token}`,
        "content-type": "image/png",
        "if-match": "0",
        "x-request-id": staleRequest,
      },
      body: bytes,
      signal: AbortSignal.timeout(5000),
    });
    if (
      stale.status !== 409 || (await stale.json()).error !== "stale" ||
      performance.now() - started >= 5000
    ) throw new Error("Local HTTP stale request did not promptly conflict");
    const directStale = await fetch(
      `${url}/rest/v1/rpc/begin_profile_avatar_operation`,
      {
        method: "POST",
        headers: {
          apikey: service,
          Authorization: `Bearer ${service}`,
          "content-type": "application/json",
        },
        body: JSON.stringify({
          target_profile: id,
          request_id: crypto.randomUUID(),
          fingerprint: "remove",
          expected_version: 0,
        }),
        signal: AbortSignal.timeout(5000),
      },
    );
    if (
      directStale.status !== 409 || (await directStale.json()).code !== "PT409"
    ) {
      throw new Error("Local RPC did not preserve exact PT409 SQLSTATE");
    }
    // Acquiring a fresh lease proves stale calls did not leave an operation open;
    // inspect all durable keys without granting direct metadata access.
    const probeLease = await admin.rpc("begin_profile_avatar_operation", {
      target_profile: id,
      request_id: crypto.randomUUID(),
      fingerprint: "probe-after-stale",
      expected_version: 1,
    });
    requireSuccess(probeLease);
    if (
      probeLease.data.version !== 1 || probeLease.data.files.length !== 1 ||
      probeLease.data.files[0] !== probeLease.data.current_file ||
      probeLease.data.completed
    ) {
      throw new Error(
        "Stale request mutated version, request binding or file ledger",
      );
    }
    requireSuccess(
      await admin.rpc("finish_profile_avatar_operation", {
        target_profile: id,
        token: probeLease.data.lease,
      }),
    );
    const fresh = await fetch(`${url}/functions/v1/profile-avatar`, {
      method: "PUT",
      headers: {
        apikey: anon,
        Authorization: `Bearer ${session.access_token}`,
        "content-type": "image/png",
        "if-match": "1",
        "x-request-id": crypto.randomUUID(),
      },
      body: bytes,
      signal: AbortSignal.timeout(5000),
    });
    if (fresh.status !== 200 || (await fresh.json()).version !== 2) {
      throw new Error("Fresh HTTP replacement failed after stale conflict");
    }
    const read = await invoke("GET");
    if (
      read.status !== 200 ||
      (await read.arrayBuffer()).byteLength !== bytes.length
    ) throw new Error("Local authorized read failed");
    const blocked = await user.storage.from("profile-avatars").list();
    if (blocked.data?.length) {
      throw new Error("Direct client Storage enumerated files");
    }
    const file = await user.rpc("resolve_profile_avatar", {
      target_kind: "profile",
      target_id: id,
    });
    requireSuccess(file);
    const direct = await user.storage.from("profile-avatars").download(
      file.data + ".png",
    );
    if (!direct.error) {
      throw new Error("Direct client downloaded a private object");
    }
    const forged = await user.storage.from("profile-avatars").upload(
      "forged.png",
      bytes,
      { contentType: "image/png" },
    );
    if (!forged.error) {
      throw new Error("Direct client bypassed image validation");
    }
    const exp = await invoke("POST");
    if (exp.status !== 200 || (await exp.json()).schema_version !== 13) {
      throw new Error("Local export failed");
    }
    if (
      (await invoke("DELETE", 2)).status !== 200 ||
      (await invoke("GET")).status !== 404
    ) throw new Error("Local remove failed");
    if ((await invoke("PUT", 3, bytes)).status !== 200) {
      throw new Error("Local replacement failed");
    }
    const list = await user.rpc("create_active_list", {
      new_title: "Local avatar lifecycle",
      creation_request_id: crypto.randomUUID(),
    });
    // Contract signature is asserted separately below by the returned RPC result.
    requireSuccess(list);
    const row = Array.isArray(list.data) ? list.data[0] : list.data;
    requireSuccess(
      await user.rpc("enable_active_list_split", {
        target_list_id: row.list_id,
        new_currency_code: "CHF",
        expected_list_version: row.version,
      }),
    );
    await deleteAvatarBeforeAccount(server, id, async () => {
      requireSuccess(await admin.auth.admin.deleteUser(id, false));
    });
    deleted = true;
    const probe = await admin.auth.admin.getUserById(id);
    if (!probe.error) throw new Error("Local Auth deletion did not complete");
  } finally {
    if (!deleted) {
      // Do not erase an uncertain upload behind its recovery fence. The fixture
      // remains isolated for diagnosis and the next local reset removes it.
      console.error(
        "Local-only fixture needs cleanup/reset; no hosted resource was accessed.",
      );
    }
    await user.auth.signOut({ scope: "local" });
  }
});
