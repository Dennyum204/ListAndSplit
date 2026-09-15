export const avatarBucket = "profile-avatars";
export interface AvatarClient {
  rpc(
    name: string,
    args?: Record<string, unknown>,
  ): PromiseLike<{
    data: unknown;
    error: { code?: string; message?: string } | null;
  }>;
  storage: {
    from(bucket: string): {
      upload(
        path: string,
        bytes: Uint8Array,
        options: { contentType: string; upsert: boolean },
      ): PromiseLike<{ error: unknown }>;
      remove(paths: string[]): PromiseLike<{ error: unknown }>;
      download(
        path: string,
      ): PromiseLike<{ data: Blob | null; error: unknown }>;
    };
  };
}
export class AvatarError extends Error {
  constructor(readonly code: string) {
    super(code);
  }
}
export async function avatarRpc(
  client: AvatarClient,
  name: string,
  args?: Record<string, unknown>,
): Promise<unknown> {
  const result = await client.rpc(name, args);
  if (result.error != null) {
    // Compatibility with the already-deployed avatar migration only. Native
    // serialization errors and errors from other RPCs must retain their code.
    if (
      name === "begin_profile_avatar_operation" &&
      result.error.code === "40001" &&
      result.error.message === "avatar changed"
    ) throw new AvatarError("PT409");
    throw new AvatarError(result.error.code ?? "retryable");
  }
  return result.data;
}
interface Lease {
  lease: string;
  version: number;
  current_file: string | null;
  completed: boolean;
  files: string[];
}
export const avatarPath = (id: string) => id + ".png";
/** Uncertain failures retain the fenced lease and durable keys for safe recovery. */
export class AvatarOperation {
  private constructor(
    private readonly admin: AvatarClient,
    readonly userId: string,
    readonly requestId: string,
    readonly fingerprint: string,
    readonly state: Lease,
  ) {}
  static async start(
    admin: AvatarClient,
    userId: string,
    requestId: string,
    fingerprint: string,
    version: number | null,
  ): Promise<AvatarOperation> {
    const state = await avatarRpc(admin, "begin_profile_avatar_operation", {
      target_profile: userId,
      request_id: requestId,
      fingerprint,
      expected_version: version,
    }) as Lease;
    return new AvatarOperation(admin, userId, requestId, fingerprint, state);
  }
  private get args() {
    return { target_profile: this.userId, token: this.state.lease };
  }
  private async erase(id: string): Promise<void> {
    const { error } = await this.admin.storage.from(avatarBucket).remove([
      avatarPath(id),
    ]);
    if (error != null) throw new AvatarError("retryable");
    await avatarRpc(this.admin, "forget_profile_avatar_file", {
      ...this.args,
      file_id: id,
    });
  }
  async cleanRetired(): Promise<void> {
    for (const id of this.state.files) {
      if (id !== this.state.current_file) await this.erase(id);
    }
  }
  private async commit(file: string | null): Promise<unknown> {
    return await avatarRpc(this.admin, "commit_profile_avatar", {
      ...this.args,
      file_id: file,
      request_id: this.requestId,
      fingerprint: this.fingerprint,
    });
  }
  async replace(bytes: Uint8Array): Promise<unknown> {
    await this.cleanRetired();
    if (this.state.completed) return this.metadata();
    const file = await avatarRpc(
      this.admin,
      "stage_profile_avatar_file",
      this.args,
    ) as string;
    const { error } = await this.admin.storage.from(avatarBucket).upload(
      avatarPath(file),
      bytes,
      { contentType: "image/png", upsert: false },
    );
    if (error != null) throw new AvatarError("retryable");
    const result = await this.commit(file);
    if (this.state.current_file != null) {
      await this.erase(this.state.current_file);
    }
    return result;
  }
  async remove(): Promise<unknown> {
    await this.cleanRetired();
    if (this.state.current_file != null) {
      const { error } = await this.admin.storage.from(avatarBucket).remove([
        avatarPath(this.state.current_file),
      ]);
      if (error != null) throw new AvatarError("retryable");
    }
    const result = await this.commit(null);
    if (this.state.current_file != null) {
      await avatarRpc(this.admin, "forget_profile_avatar_file", {
        ...this.args,
        file_id: this.state.current_file,
      });
    }
    return result;
  }
  metadata(): unknown {
    return {
      version: this.state.version,
      has_image: this.state.current_file != null,
    };
  }
  async finish(): Promise<void> {
    await avatarRpc(this.admin, "finish_profile_avatar_operation", this.args);
  }
}
export async function readAuthorizedAvatar(
  user: AvatarClient,
  admin: AvatarClient,
  kind: string,
  id: string,
): Promise<Uint8Array | null> {
  const parameters = { target_kind: kind, target_id: id };
  const file = await avatarRpc(user, "resolve_profile_avatar", parameters);
  if (file == null) return null;
  const { data, error } = await admin.storage.from(avatarBucket).download(
    avatarPath(file as string),
  );
  if (error != null || data == null) throw new AvatarError("retryable");
  if (data.size < 57 || data.size > 327680) throw new AvatarError("retryable");
  if (await avatarRpc(user, "resolve_profile_avatar", parameters) !== file) {
    return null;
  }
  return new Uint8Array(await data.arrayBuffer());
}

export async function deleteAvatarBeforeAccount(
  admin: AvatarClient,
  userId: string,
  hardDelete: () => Promise<void>,
): Promise<void> {
  const operation = await AvatarOperation.start(
    admin,
    userId,
    crypto.randomUUID(),
    "account-delete",
    null,
  );
  await operation.remove();
  // Keep the lease until Auth deletion cascades the metadata. Never allow an
  // upload between Storage cleanup and Auth deletion. Failures remain retryable.
  await hardDelete();
}
