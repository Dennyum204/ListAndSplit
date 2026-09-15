import { withSupabase } from "@supabase/server";
import { handleAvatar } from "./handler.ts";
import type { AvatarClient } from "../_shared/avatar_service.ts";
export default {
  fetch: withSupabase(
    { auth: "user" },
    (request, context) =>
      handleAvatar(
        request,
        context.userClaims?.id ?? "",
        context.supabase as unknown as AvatarClient,
        context.supabaseAdmin as unknown as AvatarClient,
      ),
  ),
};
