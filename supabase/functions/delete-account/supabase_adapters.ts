import { AccountDeletionBoundaryError } from "./handler.ts";

interface RpcResult {
  readonly data: unknown;
  readonly error: { readonly code?: string } | null;
}

export interface UserScopedDeletionClient {
  rpc(
    functionName: string,
    parameters: Record<string, unknown>,
  ): PromiseLike<RpcResult>;
}

interface DeleteUserResult {
  readonly error: unknown | null;
}

export interface AccountDeletionAdminClient {
  readonly auth: {
    readonly admin: {
      deleteUser(
        userId: string,
        shouldSoftDelete: boolean,
      ): PromiseLike<DeleteUserResult>;
    };
  };
}

export async function validateDeletion(
  client: UserScopedDeletionClient,
  confirmation: string,
): Promise<void> {
  const { data, error } = await client.rpc("validate_account_deletion", {
    deletion_confirmation: confirmation,
  });

  if (error != null) {
    switch (error.code) {
      case "42501":
        throw new AccountDeletionBoundaryError("authentication_required");
      case "55000":
        throw new AccountDeletionBoundaryError("reauthentication_required");
      case "22023":
        throw new AccountDeletionBoundaryError("confirmation_mismatch");
      default:
        throw new AccountDeletionBoundaryError("retryable");
    }
  }

  if (data !== true) {
    throw new AccountDeletionBoundaryError("retryable");
  }
}

export async function hardDeleteAuthenticatedUser(
  client: AccountDeletionAdminClient,
  userId: string,
): Promise<void> {
  const { error } = await client.auth.admin.deleteUser(userId, false);
  if (error != null) {
    throw new AccountDeletionBoundaryError("retryable");
  }
}
