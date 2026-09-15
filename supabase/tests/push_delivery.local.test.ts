import { createClient } from "@supabase/supabase-js";
import { tokenHash } from "../functions/push-dispatch/handler.ts";
Deno.test("isolated HTTP push auth, lifecycle, current access and request deduplication", async () => {
  const url = Deno.env.get("AVATAR_LOCAL_URL");
  if (url !== "http://127.0.0.1:54321" && url !== "http://localhost:54321") {
    throw new Error("Isolated local endpoint required");
  }
  const key = Deno.env.get("AVATAR_LOCAL_ANON") ?? "";
  const service = Deno.env.get("AVATAR_LOCAL_SERVICE") ?? "";
  const admin = createClient(url, service, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const users: { id: string; token: string }[] = [];
  const run = crypto.randomUUID();
  const check = (value: unknown, message: string) => {
    if (!value) throw new Error(message);
  };
  let requests = 0;
  async function raw(
    name: string,
    args: unknown,
    actor: number | "admin" | "anon" = 0,
  ) {
    requests++;
    return fetch(`${url}/rest/v1/rpc/${name}`, {
      method: "POST",
      headers: {
        apikey: key,
        Authorization: `Bearer ${
          actor === "admin"
            ? service
            : actor === "anon"
            ? key
            : users[actor].token
        }`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(args),
      signal: AbortSignal.timeout(5000),
    });
  }
  async function denied(
    name: string,
    args: unknown,
    actor: number | "admin" | "anon",
  ) {
    const response = await raw(name, args, actor);
    await response.body?.cancel();
    return !response.ok;
  }
  async function rpc<T>(
    name: string,
    args: unknown,
    actor: number | "admin" | "anon" = 0,
  ): Promise<T> {
    const r = await raw(name, args, actor);
    check(r.ok, `${name} HTTP ${r.status}`);
    const text = await r.text();
    return (text ? JSON.parse(text) : undefined) as T;
  }
  type Claim = { delivery_id: string; delivery_lease: string };
  type Prepared = {
    recipient_id: string;
    binding_id: string;
    kind: string;
    list_id?: string;
    token: string;
  };
  const claim = () =>
    rpc<Claim[]>("claim_push_deliveries", { batch_size: 20 }, "admin");
  const prepare = (c: Claim) =>
    rpc<Prepared | null>("prepare_push_delivery", {
      target_delivery_id: c.delivery_id,
      delivery_lease: c.delivery_lease,
    }, "admin");
  const finish = (c: Claim, outcome: string, hash: string | null = null) =>
    rpc("finish_push_delivery", {
      target_delivery_id: c.delivery_id,
      delivery_lease: c.delivery_lease,
      outcome,
      token_hash: hash,
    }, "admin");
  const installations = [
    crypto.randomUUID(),
    crypto.randomUUID(),
    crypto.randomUUID(),
  ];
  const bindings = [
    crypto.randomUUID(),
    crypto.randomUUID(),
    crypto.randomUUID(),
  ];
  const tokens = installations.map((id) => `local-fcm-${id}`);
  const register = (index: number, actor: number, enable = true) =>
    rpc("register_push_device", {
      installation_key: installations[index],
      binding_id: bindings[index],
      device_token: tokens[index],
      expected_account_id: users[actor].id,
      enable_delivery: enable,
    }, actor);
  try {
    for (let i = 0; i < 2; i++) {
      const email = `push-${run}-${i}@example.test`;
      const password = crypto.randomUUID() + "aB7!";
      const created = await admin.auth.admin.createUser({
        email,
        password,
        email_confirm: true,
      });
      check(!created.error && created.data.user, "task-owned local account");
      users.push({ id: created.data.user!.id, token: "" });
      const client = createClient(url, key, {
        auth: { persistSession: false, autoRefreshToken: false },
      });
      const login = await client.auth.signInWithPassword({ email, password });
      check(!login.error && login.data.session, "local login");
      users[i].token = login.data.session!.access_token;
      const profile = await client.from("profiles").update({
        username: "ps" + users[i].id.replaceAll("-", "").slice(0, 14),
        display_name: "Local push fixture",
      }).eq("id", users[i].id);
      check(!profile.error, "local onboarding");
    }
    check(
      await denied("register_push_device", {
        installation_key: installations[0],
        binding_id: bindings[0],
        device_token: tokens[0],
        expected_account_id: users[0].id,
      }, "anon"),
      "anonymous enrollment denied",
    );
    check(
      await denied("claim_push_deliveries", { batch_size: 20 }, 0),
      "user cannot claim other device data",
    );
    check(
      await denied("register_push_device", {
        installation_key: installations[0],
        binding_id: bindings[0],
        device_token: tokens[0],
        expected_account_id: users[1].id,
      }, 0),
      "caller identity guard",
    );
    await register(0, 0);
    await register(1, 1);
    await rpc("send_friend_request", {
      target_profile_id: users[1].id,
      expected_relationship_version: null,
    });
    await register(2, 1); // Enabling a second device must not replay the preceding event.
    const first = await claim();
    check(first.length === 1, "one new-event recipient and no history replay");
    const notice = await prepare(first[0]);
    check(
      notice?.recipient_id === users[1].id && notice.kind === "notification",
      "correct recipient only",
    );
    check(
      await rpc("resolve_push_destination", {
        target_delivery_id: first[0].delivery_id,
        expected_binding_id: bindings[1],
      }, 0) === null,
      "different account cannot route",
    );
    await finish(first[0], "sent");
    check(
      (await claim()).length === 0,
      "acknowledged event cannot be reclaimed",
    );
    await rpc("accept_friend_request", {
      target_profile_id: users[0].id,
      expected_relationship_version: 1,
    }, 1);
    const [list] = await rpc<{ list_id: string }[]>("create_active_list", {
      new_title: "Local push fixture",
      creation_request_id: crypto.randomUUID(),
    });
    await rpc("invite_active_list_member", {
      target_list_id: list.list_id,
      target_profile_id: users[1].id,
      expected_access_version: null,
    });
    const invites = await claim();
    check(
      invites.length === 2,
      "multiple registered devices receive new event",
    );
    await rpc("accept_active_list_invitation", {
      target_list_id: list.list_id,
      expected_access_version: 1,
    }, 1);
    for (const c of invites) {
      check(
        await prepare(c) === null,
        "resolved invitation rechecked before sending",
      );
    }
    const requestId = crypto.randomUUID();
    const sendArgs = {
      target_list_id: list.list_id,
      request_id: requestId,
      raw_body: "Synthetic local Chat content",
    };
    const message = await rpc<{ id: string }>(
      "send_active_list_chat_message",
      sendArgs,
    );
    const duplicate = await rpc<{ id: string }>(
      "send_active_list_chat_message",
      sendArgs,
    );
    check(
      message.id === duplicate.id,
      "server send retry resolves same identity",
    );
    const chat = await claim();
    check(
      chat.length === 2,
      "no push duplicate from repeated business request",
    );
    const prepared = await Promise.all(chat.map(prepare));
    check(
      prepared.every((p) =>
        p?.kind === "chat" && p.list_id === list.list_id &&
        p.recipient_id === users[1].id
      ),
      "Chat current recipient and no self alert",
    );
    check(
      prepared.every((p) => !("body" in p!)),
      "payload preparation excludes message bodies",
    );
    const index = prepared.findIndex((p) => p?.binding_id === bindings[1]);
    const newToken = `new-${tokens[1]}`;
    check(
      await rpc("rotate_push_token", {
        installation_key: crypto.randomUUID(),
        expected_binding_id: bindings[1],
        previous_token: tokens[1],
        replacement_token: newToken,
      }, "anon") === false,
      "rotation needs the original capability",
    );
    check(
      await rpc("rotate_push_token", {
        installation_key: installations[1],
        expected_binding_id: bindings[1],
        previous_token: tokens[1],
        replacement_token: newToken,
      }, "anon") === true,
      "actual background rotation HTTP path",
    );
    await finish(chat[index], "invalid", await tokenHash(tokens[1]));
    tokens[1] = newToken;
    await finish(chat[1 - index], "retry");
    const before = requests;
    check(
      (await claim()).length === 0 && requests === before + 1,
      "bounded retry has no immediate loop",
    );
    await rpc("send_active_list_chat_message", {
      ...sendArgs,
      request_id: crypto.randomUUID(),
      raw_body: "Fresh after rotation",
    });
    const fresh = await claim();
    check(
      fresh.length === 2,
      "stale invalid-token result does not disable a fresh rotated token",
    );
    await register(1, 1, false);
    const remaining = await Promise.all(fresh.map(prepare));
    check(
      remaining.filter(Boolean).length === 1,
      "logout removes only its device and queued work",
    );
    for (let i = 0; i < fresh.length; i++) {
      if (remaining[i]) await finish(fresh[i], "sent");
    }
    bindings[1] = crypto.randomUUID();
    await register(1, 0); // Same installation changes authenticated owner.
    await rpc("send_active_list_chat_message", {
      ...sendArgs,
      request_id: crypto.randomUUID(),
      raw_body: "No previous-account device",
    });
    const switched = await claim();
    check(
      switched.length === 1,
      "account switch never delivers old-user events to this installation",
    );
    await rpc("block_profile", { target_profile_id: users[0].id }, 1);
    check(
      await prepare(switched[0]) === null,
      "blocking/revoked shared access cancels pending delivery",
    );
  } finally {
    for (const user of users.reverse()) {
      const result = await admin.auth.admin.deleteUser(user.id);
      check(!result.error, "delete only task-owned local fixtures");
    }
  }
  check(
    (await claim()).length === 0,
    "account deletion removes delivery registrations and work",
  );
});
