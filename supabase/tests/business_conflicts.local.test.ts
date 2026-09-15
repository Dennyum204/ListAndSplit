// Actual PostgREST HTTP regression; never accepts a hosted target.
import { createClient } from "@supabase/supabase-js";

Deno.test("local business conflicts return once, preserve state and allow fresh writes", async () => {
  const url = Deno.env.get("AVATAR_LOCAL_URL");
  if (url !== "http://127.0.0.1:54321" && url !== "http://localhost:54321") {
    throw new Error("Explicit isolated local endpoint required");
  }
  const key = Deno.env.get("AVATAR_LOCAL_ANON") ?? "";
  const admin = createClient(url, Deno.env.get("AVATAR_LOCAL_SERVICE") ?? "", {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const users: { id: string; token: string }[] = [];
  const run = crypto.randomUUID();
  let requests = 0;
  const require = (ok: boolean, message: string) => {
    if (!ok) throw new Error(message);
  };
  async function request(name: string, args: unknown, actor = 0) {
    requests++;
    return await fetch(`${url}/rest/v1/rpc/${name}`, {
      method: "POST",
      headers: {
        apikey: key,
        Authorization: `Bearer ${users[actor].token}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(args),
      signal: AbortSignal.timeout(5000),
    });
  }
  async function rpc<T>(name: string, args: unknown, actor = 0): Promise<T> {
    const response = await request(name, args, actor);
    require(response.ok, `Local RPC failed: ${name}, HTTP ${response.status}`);
    const body = await response.text();
    return body ? JSON.parse(body) : undefined;
  }
  async function conflict(name: string, args: unknown, actor = 0) {
    const before = requests;
    const started = performance.now();
    const response = await request(name, args, actor);
    const body = await response.json();
    require(
      response.status === 409 && body.code === "PT409",
      `${name}: exact conflict`,
    );
    require(
      requests === before + 1 && performance.now() - started < 5000,
      `${name}: bounded single request`,
    );
  }
  type Row = { list_id: string; template_id: string; version: number };
  try {
    for (let i = 0; i < 2; i++) {
      const email = `conflict-${run}-${i}@example.test`;
      const password = crypto.randomUUID() + "aB7!";
      const created = await admin.auth.admin.createUser({
        email,
        password,
        email_confirm: true,
      });
      require(!created.error && !!created.data.user, "Local account creation");
      const id = created.data.user!.id;
      users.push({ id, token: "" });
      const client = createClient(url, key, {
        auth: { persistSession: false, autoRefreshToken: false },
      });
      const login = await client.auth.signInWithPassword({ email, password });
      require(!login.error && !!login.data.session, "Local login");
      users[i].token = login.data.session!.access_token;
      const profile = await client.from("profiles").update({
        username: "cf" + id.replaceAll("-", "").slice(0, 14),
        display_name: "Local conflict QA",
      }).eq("id", id);
      require(!profile.error, "Local onboarding");
    }
    await rpc("send_friend_request", {
      target_profile_id: users[1].id,
      expected_relationship_version: null,
    });
    await conflict("accept_friend_request", {
      target_profile_id: users[0].id,
      expected_relationship_version: 99,
    }, 1);
    await rpc("accept_friend_request", {
      target_profile_id: users[0].id,
      expected_relationship_version: 1,
    }, 1);

    const [list] = await rpc<Row[]>("create_active_list", {
      new_title: "Local conflict QA",
      creation_request_id: crypto.randomUUID(),
    });
    const listArgs = { target_list_id: list.list_id };
    const before = await rpc<Row[]>("get_active_list", listArgs);
    await conflict("rename_active_list", {
      ...listArgs,
      new_title: "Must not persist",
      expected_list_version: 99,
    });
    require(
      JSON.stringify(await rpc("get_active_list", listArgs)) ===
        JSON.stringify(before),
      "Stale list preserves authoritative state",
    );
    await rpc("rename_active_list", {
      ...listArgs,
      new_title: "Fresh write",
      expected_list_version: list.version,
    });
    const [current] = await rpc<Row[]>("get_active_list", listArgs);
    const split = await rpc<{ settings: { version: number } }>(
      "enable_active_list_split",
      {
        ...listArgs,
        new_currency_code: "CHF",
        expected_list_version: current.version,
      },
    );
    const beforeSplit = await rpc("get_active_list_split", listArgs);
    await conflict("change_active_list_split_currency", {
      ...listArgs,
      new_currency_code: "EUR",
      expected_split_version: 99,
    });
    require(
      JSON.stringify(await rpc("get_active_list_split", listArgs)) ===
        JSON.stringify(beforeSplit),
      "Stale Split preserves ledger and version",
    );
    await rpc("change_active_list_split_currency", {
      ...listArgs,
      new_currency_code: "EUR",
      expected_split_version: split.settings.version,
    });

    const [template] = await rpc<Row[]>("create_private_template", {
      new_name: "Local template",
      target_category_id: null,
      creation_request_id: crypto.randomUUID(),
    });
    const update = {
      target_template_id: template.template_id,
      new_name: "Fresh template",
      target_category_id: null,
    };
    await conflict("update_private_template", {
      ...update,
      expected_template_version: 99,
    });
    const [updated] = await rpc<Row[]>("update_private_template", {
      ...update,
      expected_template_version: template.version,
    });
    require(
      updated.version === template.version + 1,
      "Only the fresh template write advances version",
    );
  } finally {
    // Only the UUIDs created by this isolated test; no avatar files were created.
    for (const user of users.reverse()) {
      const result = await admin.auth.admin.deleteUser(user.id);
      require(!result.error, "Local fixture cleanup");
    }
  }
});
