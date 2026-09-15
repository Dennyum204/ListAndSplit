import { withSupabase } from "@supabase/server";
import { handleDeleteAccount } from "./handler.ts";
import {
  type AvatarClient,
  deleteAvatarBeforeAccount,
} from "../_shared/avatar_service.ts";
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
        deleteAvatarBeforeAccount(
          context.supabaseAdmin as unknown as AvatarClient,
          authenticatedUserId,
          () =>
            hardDeleteAuthenticatedUser(
              context.supabaseAdmin,
              authenticatedUserId,
            ),
        ),
    });
  }),
};
