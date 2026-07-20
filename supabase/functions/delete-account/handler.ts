const maximumBodyBytes = 1024;
const maximumConfirmationLength = 320;

export type AccountDeletionFailureKind =
  | "authentication_required"
  | "reauthentication_required"
  | "confirmation_mismatch"
  | "retryable";

export class AccountDeletionBoundaryError extends Error {
  constructor(readonly kind: AccountDeletionFailureKind) {
    super(kind);
    this.name = "AccountDeletionBoundaryError";
  }
}

export interface AccountDeletionRequestContext {
  readonly userId: string;
  validate(confirmation: string): Promise<void>;
  hardDelete(userId: string): Promise<void>;
}

export async function handleDeleteAccount(
  request: Request,
  context: AccountDeletionRequestContext,
): Promise<Response> {
  if (request.method === "OPTIONS") {
    return new Response(null, {
      status: 204,
      headers: { allow: "POST, OPTIONS" },
    });
  }

  if (request.method !== "POST") {
    return jsonResponse("method_not_allowed", 405, {
      allow: "POST, OPTIONS",
    });
  }

  if (context.userId.length === 0) {
    return jsonResponse("authentication_required", 401);
  }

  let confirmation: string;
  try {
    confirmation = await readConfirmation(request);
  } catch (_) {
    return jsonResponse("invalid_request", 400);
  }

  try {
    await context.validate(confirmation);
    await context.hardDelete(context.userId);
    return Response.json({ deleted: true });
  } catch (error) {
    if (error instanceof AccountDeletionBoundaryError) {
      return switchFailure(error.kind);
    }
    return jsonResponse("retryable_failure", 503);
  }
}

async function readConfirmation(request: Request): Promise<string> {
  const contentType = request.headers.get("content-type")?.toLowerCase() ?? "";
  if (!contentType.startsWith("application/json")) {
    throw new Error("invalid request");
  }

  const declaredLength = request.headers.get("content-length");
  if (declaredLength != null) {
    const parsedLength = Number(declaredLength);
    if (
      !Number.isSafeInteger(parsedLength) ||
      parsedLength < 0 ||
      parsedLength > maximumBodyBytes
    ) {
      throw new Error("invalid request");
    }
  }

  const body = await readBoundedBody(request);
  const decoded = JSON.parse(body) as unknown;
  if (
    decoded == null ||
    typeof decoded !== "object" ||
    Array.isArray(decoded)
  ) {
    throw new Error("invalid request");
  }

  const record = decoded as Record<string, unknown>;
  if (
    Object.keys(record).length !== 1 ||
    !("confirmation" in record) ||
    typeof record.confirmation !== "string" ||
    record.confirmation.length === 0 ||
    record.confirmation.length > maximumConfirmationLength
  ) {
    throw new Error("invalid request");
  }

  return record.confirmation;
}

async function readBoundedBody(request: Request): Promise<string> {
  if (request.body == null) throw new Error("invalid request");

  const reader = request.body.getReader();
  const chunks: Uint8Array[] = [];
  let totalBytes = 0;

  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      totalBytes += value.byteLength;
      if (totalBytes > maximumBodyBytes) {
        await reader.cancel();
        throw new Error("invalid request");
      }
      chunks.push(value);
    }
  } finally {
    reader.releaseLock();
  }

  const bytes = new Uint8Array(totalBytes);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return new TextDecoder("utf-8", { fatal: true }).decode(bytes);
}

function switchFailure(kind: AccountDeletionFailureKind): Response {
  switch (kind) {
    case "authentication_required":
      return jsonResponse("authentication_required", 401);
    case "reauthentication_required":
      return jsonResponse("reauthentication_required", 409);
    case "confirmation_mismatch":
      return jsonResponse("confirmation_mismatch", 422);
    case "retryable":
      return jsonResponse("retryable_failure", 503);
  }
}

function jsonResponse(
  code: string,
  status: number,
  headers: HeadersInit = {},
): Response {
  return Response.json(
    { error: code },
    {
      status,
      headers: {
        "cache-control": "no-store",
        ...headers,
      },
    },
  );
}
