import { withSupabase } from "@supabase/server";
import { handleDeleteAccount } from "./handler.ts";
import {
  hardDeleteAuthenticatedUser,
  type UserScopedDeletionClient,
  validateDeletion,
} from "./supabase_adapters.ts";

export default {
  fetch: withSupabase({ auth: "user" }, async (request, context) => {
    const userId = context.userClaims?.id ?? "";
    return handleDeleteAccount(request, {
      userId,
      validate: (confirmation) =>
        validateDeletion(
          context.supabase as unknown as UserScopedDeletionClient,
          confirmation,
        ),
      hardDelete: (authenticatedUserId) =>
        hardDeleteAuthenticatedUser(
          context.supabaseAdmin,
          authenticatedUserId,
        ),
    });
  }),
};
