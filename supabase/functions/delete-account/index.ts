// Deletes the calling user's auth account. All rows in public.* cascade
// from auth.users. The last root account is protected by the
// user_roles_guard_last_root trigger, which makes the delete fail.
import { createClient } from "npm:@supabase/supabase-js@2.45.4";

const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });

Deno.serve(async (req) => {
  if (req.method !== "POST") return json(405, { error: "method not allowed" });

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return json(401, { error: "missing authorization" });

  const url = Deno.env.get("SUPABASE_URL")!;
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

  // Resolve the caller from their own JWT; never trust a user id in the body.
  const asCaller = createClient(url, anonKey, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: { user }, error: userError } = await asCaller.auth.getUser();
  if (userError || !user) return json(401, { error: "invalid session" });

  const admin = createClient(url, serviceKey);

  // GoTrue reports trigger failures only as a generic database error, so
  // check the last-root rule up front for a meaningful response.
  const { data: roots, error: rootsError } = await admin
    .from("user_roles").select("user_id").eq("role", "root");
  if (rootsError) return json(500, { error: "delete_failed" });
  if (roots.length === 1 && roots[0].user_id === user.id) {
    return json(409, { error: "last_root" });
  }

  const { error } = await admin.auth.admin.deleteUser(user.id);
  if (error) return json(500, { error: "delete_failed" });
  return json(200, { deleted: true });
});
