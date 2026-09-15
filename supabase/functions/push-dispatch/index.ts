import { withSupabase } from "@supabase/server";
import {
  authorizedWorker,
  type Claim,
  type Delivery,
  dispatch,
  type Outcome,
} from "./handler.ts";
import { makeFcmSender } from "./fcm.ts";

// Custom scheduler credential is narrowly scoped to this endpoint. auth:none
// delegates ONLY credential verification to this handler; it is not public work.
export default {
  fetch: withSupabase({ auth: "none" }, async (request, context) => {
    const key = Deno.env.get("PUSH_WORKER_SECRET") ?? "";
    if (!await authorizedWorker(request, key)) {
      return new Response(null, { status: 401 });
    }
    let send;
    try {
      send = makeFcmSender(
        Deno.env.get("FCM_SERVICE_ACCOUNT_JSON") ?? "",
        Deno.env.get("FCM_PROJECT_ID") ?? "",
      );
    } catch {
      return Response.json({ error: "push_configuration_unavailable" }, {
        status: 503,
      });
    }
    const client = context.supabaseAdmin as unknown as {
      rpc(
        name: string,
        args: Record<string, unknown>,
      ): Promise<{ data: unknown; error: unknown }>;
    };
    async function rpc<T>(
      name: string,
      args: Record<string, unknown>,
    ): Promise<T> {
      const { data, error } = await client.rpc(name, args);
      if (error) throw new Error("Push database unavailable");
      return data as T;
    }
    return dispatch(request, key, {
      claim: () => rpc<Claim[]>("claim_push_deliveries", { batch_size: 20 }),
      prepare: (c: Claim) =>
        rpc<Delivery | null>("prepare_push_delivery", {
          target_delivery_id: c.delivery_id,
          delivery_lease: c.delivery_lease,
        }),
      finish: (c: Claim, o: Outcome, h: string | null) =>
        rpc<void>("finish_push_delivery", {
          target_delivery_id: c.delivery_id,
          delivery_lease: c.delivery_lease,
          outcome: o.outcome,
          token_hash: h,
          retry_after_seconds: o.retryAfter ?? 60,
        }),
    }, send);
  }),
};
