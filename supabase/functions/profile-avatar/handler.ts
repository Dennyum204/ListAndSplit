import {
  AvatarClient,
  AvatarError,
  AvatarOperation,
  avatarRpc,
  readAuthorizedAvatar,
} from "../_shared/avatar_service.ts";
import { readAvatarBody } from "../_shared/avatar_png.ts";
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const headers = {
  "cache-control": "no-store",
  "x-content-type-options": "nosniff",
};
export async function handleAvatar(
  request: Request,
  userId: string,
  user: AvatarClient,
  admin: AvatarClient,
): Promise<Response> {
  if (!uuid.test(userId)) {
    return Response.json({ error: "authentication_required" }, {
      status: 401,
      headers,
    });
  }
  try {
    const url = new URL(request.url);
    if (request.method === "GET") {
      const kind = url.searchParams.get("kind") ?? "profile";
      const id = url.searchParams.get("id") ?? userId;
      if (!uuid.test(id) || !["profile", "chat", "split"].includes(kind)) {
        throw new AvatarError("22023");
      }
      const bytes = await readAuthorizedAvatar(user, admin, kind, id);
      return bytes == null
        ? new Response(null, { status: 404, headers })
        : new Response(bytes, {
          headers: {
            ...headers,
            "content-type": "application/octet-stream",
            "x-avatar-content-type": "image/png",
          },
        });
    }
    if (!["PUT", "DELETE", "POST"].includes(request.method)) {
      return new Response(null, { status: 405, headers });
    }
    if (request.method !== "POST") {
      await avatarRpc(user, "get_own_profile_avatar");
    }
    const requestId = request.headers.get("x-request-id") ?? "";
    if (!uuid.test(requestId)) throw new AvatarError("22023");
    if (request.method === "POST") {
      const document = await avatarRpc(
        user,
        "export_own_account_data_v12",
      ) as Record<string, unknown>;
      const operation = await AvatarOperation.start(
        admin,
        userId,
        requestId,
        "export",
        null,
      );
      let avatar: unknown = null;
      if (operation.state.current_file != null) {
        const bytes = await readAuthorizedAvatar(
          user,
          admin,
          "profile",
          userId,
        );
        if (bytes == null) throw new AvatarError("retryable");
        let binary = "";
        for (const byte of bytes) binary += String.fromCharCode(byte);
        avatar = {
          mime_type: "image/png",
          width: 256,
          height: 256,
          data_base64: btoa(binary),
        };
      }
      await operation.finish();
      return Response.json({ ...document, schema_version: 13, avatar }, {
        headers,
      });
    }
    const versionText = request.headers.get("if-match") ?? "";
    if (!/^\d{1,15}$/.test(versionText)) throw new AvatarError("22023");
    const version = Number(versionText);
    let bytes: Uint8Array | null = null;
    let fingerprint = "remove";
    if (request.method === "PUT") {
      if (request.headers.get("content-type") !== "image/png") {
        throw new AvatarError("invalid_image");
      }
      bytes = await readAvatarBody(request);
      const hash = new Uint8Array(await crypto.subtle.digest("SHA-256", bytes));
      fingerprint = Array.from(
        hash,
        (value) => value.toString(16).padStart(2, "0"),
      ).join("");
    }
    const operation = await AvatarOperation.start(
      admin,
      userId,
      requestId,
      fingerprint,
      version,
    );
    const result = bytes == null
      ? await operation.remove()
      : await operation.replace(bytes);
    await operation.finish();
    return Response.json(result, { headers });
  } catch (error) {
    const code = error instanceof AvatarError
      ? error.code
      : error instanceof Error && error.message === "invalid_image"
      ? "invalid_image"
      : "retryable";
    const status = code === "42501"
      ? 401
      : code === "PT409" || code === "55P03"
      ? 409
      : code === "22023" || code === "invalid_image"
      ? 422
      : 503;
    return Response.json({
      error: code === "55P03"
        ? "busy"
        : code === "PT409"
        ? "stale"
        : status === 422
        ? "invalid_image"
        : status === 401
        ? "authentication_required"
        : "retryable",
    }, { status, headers });
  }
}
