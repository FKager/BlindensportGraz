// Sends the schedule pushes ("Neues Training", "Training abgesagt", …) for
// one changed event. Called only by the events_notify_schedule trigger
// (migration 20261014000001_push), which authenticates with a shared secret
// instead of a user JWT — deploy with --no-verify-jwt.
//
// Recipients: approved accounts with a team membership in one of the
// event's teams, minus the person who made the change. The alert carries
// localization keys from the app's Localizable.xcstrings, so the text stays
// German (and translatable) in the app, not here.
//
// Secrets: NOTIFY_SCHEDULE_SECRET, APNS_KEY_ID, APNS_TEAM_ID,
// APNS_PRIVATE_KEY (contents of the .p8), APNS_TOPIC (bundle id).
import { createClient } from "npm:@supabase/supabase-js@2.45.4";
import { importPKCS8, SignJWT } from "npm:jose@5.9.6";

type Change = "created" | "updated" | "cancelled";

interface Payload {
  event_id: string;
  kind: "training" | "tournament";
  change: Change;
  title: string;
  location: string;
  team_ids: string[];
  actor: string | null;
}

const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });

const apnsHosts: Record<string, string> = {
  sandbox: "https://api.sandbox.push.apple.com",
  production: "https://api.push.apple.com",
};

// APNs accepts a provider token for up to an hour and rejects refreshing it
// more often than every 20 minutes; one per warm instance, renewed after 50.
let cachedJWT: { token: string; issuedAt: number } | undefined;

async function providerToken(): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cachedJWT && now - cachedJWT.issuedAt < 50 * 60) return cachedJWT.token;
  const key = await importPKCS8(Deno.env.get("APNS_PRIVATE_KEY")!, "ES256");
  const token = await new SignJWT({})
    .setProtectedHeader({ alg: "ES256", kid: Deno.env.get("APNS_KEY_ID")! })
    .setIssuer(Deno.env.get("APNS_TEAM_ID")!)
    .setIssuedAt(now)
    .sign(key);
  cachedJWT = { token, issuedAt: now };
  return token;
}

// Same keys the CloudKit subscriptions used, e.g. training_cancelled_title.
function alertFor(p: Payload) {
  const prefix = `${p.kind}_${p.change}`;
  return {
    "title-loc-key": `${prefix}_title`,
    "loc-key": `${prefix}_body`,
    "loc-args": [p.title, p.location],
  };
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json(405, { error: "method not allowed" });
  const secret = Deno.env.get("NOTIFY_SCHEDULE_SECRET");
  if (!secret || req.headers.get("X-Notify-Secret") !== secret) {
    return json(401, { error: "unauthorized" });
  }

  const p = (await req.json()) as Payload;
  if (!p.event_id || !Array.isArray(p.team_ids) || p.team_ids.length === 0) {
    return json(400, { error: "bad payload" });
  }

  const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

  const { data: memberships, error: mError } = await admin
    .from("team_memberships").select("user_id").in("team_id", p.team_ids).not("user_id", "is", null);
  if (mError) return json(500, { error: "recipients_failed" });
  const candidates = [...new Set(memberships.map((m) => m.user_id as string))]
    .filter((id) => id !== p.actor);
  if (candidates.length === 0) return json(200, { sent: 0 });

  // Same rule as is_approved(): approved, or admin/root.
  const [{ data: approvals }, { data: admins }] = await Promise.all([
    admin.from("account_approvals").select("user_id").in("user_id", candidates),
    admin.from("user_roles").select("user_id").in("user_id", candidates).in("role", ["admin", "root"]),
  ]);
  const recipients = new Set([...(approvals ?? []), ...(admins ?? [])].map((r) => r.user_id as string));
  if (recipients.size === 0) return json(200, { sent: 0 });

  const { data: tokens, error: tError } = await admin
    .from("device_tokens").select("token, apns_env").in("user_id", [...recipients]);
  if (tError) return json(500, { error: "tokens_failed" });
  if (tokens.length === 0) return json(200, { sent: 0 });

  const jwt = await providerToken();
  const body = JSON.stringify({ aps: { alert: alertFor(p), sound: "default" } });
  const stale: string[] = [];
  let sent = 0;

  await Promise.all(tokens.map(async ({ token, apns_env }) => {
    const res = await fetch(`${apnsHosts[apns_env]}/3/device/${token}`, {
      method: "POST",
      headers: {
        authorization: `bearer ${jwt}`,
        "apns-topic": Deno.env.get("APNS_TOPIC")!,
        "apns-push-type": "alert",
        // A later change to the same event replaces an undelivered one.
        "apns-collapse-id": p.event_id,
      },
      body,
    });
    if (res.ok) {
      sent++;
      return;
    }
    const reason = ((await res.json().catch(() => ({}))) as { reason?: string }).reason ?? "";
    console.error(`APNs ${res.status} ${reason} for ${apns_env} token …${token.slice(-6)}`);
    if (res.status === 410 || reason === "BadDeviceToken" || reason === "Unregistered") stale.push(token);
  }));

  if (stale.length > 0) await admin.from("device_tokens").delete().in("token", stale);
  return json(200, { sent, removed: stale.length });
});
