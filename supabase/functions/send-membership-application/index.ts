// Mails a filled GVSC Beitrittserklärung (.docx, built by the app) to the
// club. Allowed for members.manage on any roster entry and for an account on
// its own approved entry — checked by public.mark_gvsc_application(), which
// also marks the entry as applied. Recipient, sender and subject are fixed
// here, so the function can't be used to mail anyone else. The profile photo
// of the account linked to the entry is attached server-side.
//
// Secret: RESEND_API_KEY (send-only key for mail.a11y.it).
import { createClient } from "npm:@supabase/supabase-js@2.45.4";
import { encodeBase64 } from "jsr:@std/encoding@1.0.5/base64";

const RECIPIENT = "blindensport.gvsc@gmail.com";
const SENDER = "Blindensport Graz <no-reply@mail.a11y.it>";
const MAX_DOCX_BYTES = 2 * 1024 * 1024;

const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });

// "Müller-Öz" → "Mueller-Oez": ASCII-only attachment file names.
const fileSafe = (s: string) =>
  s.replace(/ä/g, "ae").replace(/ö/g, "oe").replace(/ü/g, "ue")
    .replace(/Ä/g, "Ae").replace(/Ö/g, "Oe").replace(/Ü/g, "Ue").replace(/ß/g, "ss")
    .replace(/[^A-Za-z0-9-]+/g, "_").replace(/^_+|_+$/g, "");

Deno.serve(async (req) => {
  if (req.method !== "POST") return json(405, { error: "method not allowed" });

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return json(401, { error: "missing authorization" });

  let body: { member_id?: string; docx_base64?: string; own_photo?: boolean };
  try {
    body = await req.json();
  } catch {
    return json(400, { error: "invalid body" });
  }
  const memberID = body.member_id ?? "";
  const docxBase64 = body.docx_base64 ?? "";
  if (!/^[0-9a-f-]{36}$/i.test(memberID) || docxBase64.length === 0) {
    return json(400, { error: "invalid body" });
  }
  let docx: Uint8Array;
  try {
    docx = Uint8Array.from(atob(docxBase64), (c) => c.charCodeAt(0));
  } catch {
    return json(400, { error: "invalid docx" });
  }
  // A .docx is a zip: "PK\x03\x04".
  if (docx.length > MAX_DOCX_BYTES || docx[0] !== 0x50 || docx[1] !== 0x4b) {
    return json(400, { error: "invalid docx" });
  }

  const resendKey = Deno.env.get("RESEND_API_KEY");
  if (!resendKey) return json(500, { error: "mail_not_configured" });

  const url = Deno.env.get("SUPABASE_URL")!;
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

  const asCaller = createClient(url, anonKey, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: { user }, error: userError } = await asCaller.auth.getUser();
  if (userError || !user) return json(401, { error: "invalid session" });

  const admin = createClient(url, serviceKey);
  const { data: member, error: memberError } = await admin
    .from("members").select("first_name, last_name, gvsc_applied_at")
    .eq("id", memberID).maybeSingle();
  if (memberError) return json(500, { error: "send_failed" });
  if (!member) return json(404, { error: "member_not_found" });

  // Authorization + "beantragt" mark, as the caller.
  const { data: linkedUserID, error: markError } = await asCaller
    .rpc("mark_gvsc_application", { p_member_id: memberID });
  if (markError) {
    if (markError.code === "42501") return json(403, { error: "not_allowed" });
    if (markError.code === "P0002") return json(404, { error: "member_not_found" });
    if (markError.code === "22023") {
      return json(409, {
        error: markError.message === "already a member" ? "already_member" : "just_sent",
      });
    }
    return json(500, { error: "send_failed" });
  }

  const name = `${member.first_name} ${member.last_name}`.trim();
  const baseName = fileSafe(`${member.last_name}_${member.first_name}`) || "Mitglied";
  const attachments = [{
    filename: `Beitrittserklaerung_${baseName}.docx`,
    content: encodeBase64(docx),
  }];

  // The linked account's photo; sent from the caller's own Account screen
  // (e.g. an admin whose entry isn't linked), the caller's own photo.
  const photoUserID = linkedUserID ?? (body.own_photo === true ? user.id : null);
  let hasPhoto = false;
  if (photoUserID) {
    const { data: photo } = await admin.storage
      .from("profile-photos").download(`${photoUserID}.jpg`);
    if (photo) {
      attachments.push({
        filename: `Foto_${baseName}.jpg`,
        content: encodeBase64(new Uint8Array(await photo.arrayBuffer())),
      });
      hasPhoto = true;
    }
  }

  const text = [
    `Neue Beitrittserklärung zum Grazer Versehrtensportclub für ${name}.`,
    "",
    `Gesendet von ${user.email ?? "unbekannt"} über die Blindensport-Graz-App.`,
    hasPhoto ? "Das Profilfoto ist angehängt." : "Es ist kein Profilfoto vorhanden.",
    "",
    "Die Beitrittserklärung ist vorausgefüllt und muss noch unterschrieben werden.",
    "Nach Eingang der Unterschrift bitte die Mitgliedschaft in der App bestätigen.",
  ].join("\n");

  const response = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${resendKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      from: SENDER,
      to: [RECIPIENT],
      reply_to: user.email ? [user.email] : undefined,
      subject: `Beitrittserklärung: ${name}`,
      text,
      attachments,
    }),
  });

  if (!response.ok) {
    // Not sent: restore the previous "beantragt" date so the entry doesn't
    // look applied.
    await admin.from("members")
      .update({ gvsc_applied_at: member.gvsc_applied_at }).eq("id", memberID);
    console.error("resend failed", response.status, await response.text());
    return json(502, { error: "send_failed" });
  }
  return json(200, { sent: true, photo: hasPhoto });
});
